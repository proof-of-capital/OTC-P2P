// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCConstants} from "../src/constants/OTCConstants.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {IOTCClientVaultErrors} from "../src/interfaces/IOTCClientVaultErrors.sol";
import {IOTCClientVaultEvents} from "../src/interfaces/IOTCClientVaultEvents.sol";
import {IOTCFactoryRegistryErrors} from "../src/interfaces/IOTCFactoryRegistryErrors.sol";

contract MockERC20 is ERC20 {
    constructor(string memory n, string memory s) ERC20(n, s) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @dev Simulates a swap target that always reverts — used to test DeliveryCallFailed.
contract RevertingTarget {
    fallback() external {
        revert("forced revert");
    }
}

/// @dev Simulates a swap target that consumes the allowance and sends back a token.
contract SimpleSwapTarget {
    using SafeERC20 for IERC20;

    function swap(address tokenIn, address from, uint256 amountIn, address tokenOut, uint256 amountOut) external {
        IERC20(tokenIn).safeTransferFrom(from, address(this), amountIn);
        IERC20(tokenOut).safeTransfer(msg.sender, amountOut);
    }
}

/// @dev Registers a vault with a zero vault address to exercise the require check in registerVault.
contract MockBadFactory {
    OTCFactoryRegistry private immutable _registry;

    constructor(OTCFactoryRegistry registry_) {
        _registry = registry_;
    }

    function registerZeroVault() external {
        _registry.registerVault(address(0));
    }
}

contract OTCCoverageGapsTest is Test {
    address protocolOwner = address(0x1001);
    address protocolReceiver = address(0x1002);
    address operatorOwner = address(0x2001);
    address operatorAdmin = address(0x2002);
    address operatorReceiver = address(0x2003);
    address client = address(0x3001);
    address counterparty = address(0x4001);
    address recipient = address(0x5001);
    address extraReceiver = address(0x5002);
    address stranger = address(0x9999);

    OTCFactoryRegistry registry;
    OTCOperatorFactory factory;
    OTCClientVault vault;
    MockERC20 usdt;
    MockERC20 weth;

    OTCTypes.ExtraFee emptyExtraFee = OTCTypes.ExtraFee({token: address(0), amount: 0, receiver: address(0)});

    function setUp() public {
        usdt = new MockERC20("USDT", "USDT");
        weth = new MockERC20("WETH", "WETH");

        registry = new OTCFactoryRegistry(protocolOwner, protocolReceiver, 1_000, 2_000);

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        factory = OTCOperatorFactory(
            registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, config, "")
        );

        vm.prank(operatorAdmin);
        vault = OTCClientVault(payable(factory.deployClientVault(client)));
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────

    function _deposit(address token, uint256 amount) internal {
        MockERC20(token).mint(client, amount);
        vm.startPrank(client);
        IERC20(token).approve(address(vault), amount);
        vault.deposit(token, amount);
        vm.stopPrank();
    }

    function _proposeLock(address token, uint256 duration) internal returns (uint256) {
        vm.prank(operatorAdmin);
        return vault.proposeLock(token, block.timestamp + duration, block.timestamp + 1 days);
    }

    function _proposeDirectDelivery(address token, uint256 amount, address to, OTCTypes.ExtraFee memory extra)
        internal
        returns (uint256)
    {
        vm.prank(operatorAdmin);
        return vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: token,
                amount: amount,
                deliveryAddress: to,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            extra
        );
    }

    function _enableSwapLevel(OTCTypes.SwapAccessLevel level) internal {
        if (vault.swapAccessLevel() == OTCTypes.SwapAccessLevel.DeliveryOnly) {
            vm.prank(operatorAdmin);
        } else {
            vm.prank(client);
        }
        vault.setSwapAccessLevel(level);
    }

    function _createSwap(
        address proposer,
        OTCTypes.SwapAccessLevel level,
        address cp,
        address tokenOut,
        uint256 amountOut,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256) {
        if (uint8(level) > uint8(vault.swapAccessLevel())) {
            _enableSwapLevel(level);
        }
        vm.prank(proposer);
        return vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: level,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: cp,
                tokenOut: tokenOut,
                amountOut: amountOut,
                tokenIn: tokenIn,
                amountIn: amountIn,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    // ── Group 1: withdrawal edge cases ────────────────────────────────────────────

    function testReceive_RevertsEthTransfer() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertFalse(ok);
        assertEq(address(vault).balance, 0);
    }

    function testDeposit_RevertsNotOwner() public {
        usdt.mint(stranger, 100);
        vm.startPrank(stranger);
        usdt.approve(address(vault), 100);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vault.deposit(address(usdt), 100);
        vm.stopPrank();
    }

    function testDeposit_RevertsZeroToken() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.deposit(address(0), 100);
    }

    function testDeposit_RevertsZeroAmount() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAmount.selector);
        vault.deposit(address(usdt), 0);
    }

    function testInitialize_RevertsZeroFactory() public {
        address impl = registry.clientVaultImplementation();
        address proxy = Clones.clone(impl);
        OTCTypes.DefaultLockConfig[] memory locks = new OTCTypes.DefaultLockConfig[](0);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        OTCClientVault(payable(proxy)).initialize(address(0), client, locks);
    }

    function testInitialize_RevertsZeroClient() public {
        address impl = registry.clientVaultImplementation();
        address proxy = Clones.clone(impl);
        OTCTypes.DefaultLockConfig[] memory locks = new OTCTypes.DefaultLockConfig[](0);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        OTCClientVault(payable(proxy)).initialize(address(factory), address(0), locks);
    }

    function testDeployClientVault_RevertsDefaultLockZeroToken() public {
        vm.prank(operatorOwner);
        factory.setDefaultLockDuration(address(usdt), 1 days);

        vm.prank(operatorOwner);
        factory.setDefaultLockDuration(address(usdt), 0);

        OTCTypes.DefaultLockConfig[] memory locks = new OTCTypes.DefaultLockConfig[](1);
        locks[0] = OTCTypes.DefaultLockConfig({token: address(0), duration: 1 days});

        address impl = registry.clientVaultImplementation();
        address proxy = Clones.clone(impl);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        OTCClientVault(payable(proxy)).initialize(address(factory), client, locks);
    }

    function testDeployClientVault_RevertsDefaultLockDurationTooLarge() public {
        uint256 tooLarge = OTCConstants.MAX_LOCK_DURATION + 1;
        OTCTypes.DefaultLockConfig[] memory locks = new OTCTypes.DefaultLockConfig[](1);
        locks[0] = OTCTypes.DefaultLockConfig({token: address(usdt), duration: tooLarge});

        address impl = registry.clientVaultImplementation();
        address proxy = Clones.clone(impl);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCClientVaultErrors.LockDurationTooLarge.selector, tooLarge, OTCConstants.MAX_LOCK_DURATION
            )
        );
        OTCClientVault(payable(proxy)).initialize(address(factory), client, locks);
    }

    function testDirectTransfer_IncreasesVaultBalance() public {
        usdt.mint(client, 1_000);
        vm.prank(client);
        assertTrue(usdt.transfer(address(vault), 1_000));

        assertEq(usdt.balanceOf(address(vault)), 1_000);

        vm.prank(client);
        vault.withdraw(address(usdt), 400, recipient);
        assertEq(usdt.balanceOf(recipient), 400);
        assertEq(usdt.balanceOf(address(vault)), 600);
    }

    function testWithdraw_RevertsZeroToken() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.withdraw(address(0), 1, recipient);
    }

    function testWithdraw_RevertsZeroAmount() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAmount.selector);
        vault.withdraw(address(usdt), 0, recipient);
    }

    function testWithdraw_RevertsZeroTo() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.withdraw(address(usdt), 1, address(0));
    }

    function testWithdraw_RevertsZeroTokenAll() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.withdraw(address(0), type(uint256).max, recipient);
    }

    function testWithdraw_RevertsZeroToAll() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.withdraw(address(usdt), type(uint256).max, address(0));
    }

    function testWithdraw_RevertsTokenLockedAll() public {
        _deposit(address(usdt), 1_000);
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        uint256 unlocksAt = vault.tokenLockUntil(address(usdt));
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), unlocksAt));
        vault.withdraw(address(usdt), type(uint256).max, recipient);
    }

    // ── Group 2: Lock proposal edge cases ────────────────────────────────────────

    function testProposeLock_RevertsZeroToken() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.proposeLock(address(0), block.timestamp + 1 days, block.timestamp + 1 days);
    }

    function testProposeLock_RevertsDurationTooLarge() public {
        uint256 tooLong = OTCConstants.MAX_LOCK_DURATION + 1;
        vm.prank(operatorAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCClientVaultErrors.LockDurationTooLarge.selector, tooLong, OTCConstants.MAX_LOCK_DURATION
            )
        );
        vault.proposeLock(address(usdt), block.timestamp + tooLong, block.timestamp + 1 days);
    }

    function testProposeLock_RevertsDeadlinePast() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidDeadline.selector);
        vault.proposeLock(address(usdt), block.timestamp + 1 days, block.timestamp);
    }

    function testProposeLock_RevertsInvalidLockUntil() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidLockUntil.selector);
        vault.proposeLock(address(usdt), block.timestamp, block.timestamp + 1 days);
    }

    function testCancelLockProposal_RevertsInvalidProposal() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidProposal.selector);
        vault.cancelLockProposal(999);
    }

    function testCancelLockProposal_RevertsAlreadyExecuted() public {
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyExecuted.selector);
        vault.cancelLockProposal(lockId);
    }

    function testCancelLockProposal_RevertsAlreadyCancelled() public {
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.cancelLockProposal(lockId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vault.cancelLockProposal(lockId);
    }

    function testAcceptLockProposal_RevertsProposalExpired() public {
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.warp(block.timestamp + 2 days);

        (, uint256 newLockUntil, uint256 deadline,,,) = vault.lockProposals(lockId);
        (newLockUntil); // silence unused variable

        vm.prank(client);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCClientVaultErrors.ProposalExpired.selector, deadline, block.timestamp)
        );
        vault.acceptLockProposal(lockId);
    }

    function testAcceptLockProposal_RevertsAlreadyExecuted() public {
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyExecuted.selector);
        vault.acceptLockProposal(lockId);
    }

    function testAcceptLockProposal_RevertsAlreadyCancelled() public {
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.cancelLockProposal(lockId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vault.acceptLockProposal(lockId);
    }

    function testProposeLock_RevertsNotAdmin() public {
        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotFactoryAdmin.selector);
        vault.proposeLock(address(usdt), block.timestamp + 1 days, block.timestamp + 1 days);
    }

    function testCancelLockProposal_RevertsStranger() public {
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelLockProposal(lockId);
    }

    function testAdminDecreaseLock_RevertsZeroToken() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.adminDecreaseLock(address(0), block.timestamp + 1 days);
    }

    // ── Group 3: Delivery proposal edge cases ────────────────────────────────────

    function testCancelDeliveryProposal_RevertsInvalidProposal() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidProposal.selector);
        vault.cancelDeliveryProposal(999);
    }

    function testCancelDeliveryProposal_RevertsAlreadyExecuted() public {
        _deposit(address(usdt), 1_000);
        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vault.executeDelivery(id);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyExecuted.selector);
        vault.cancelDeliveryProposal(id);
    }

    function testCancelDeliveryProposal_RevertsAlreadyCancelled() public {
        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(client);
        vault.cancelDeliveryProposal(id);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vault.cancelDeliveryProposal(id);
    }

    function testCancelDelivery_OpenP2P_Unlocked_OnlyClientCanCancel() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 clientId = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(client);
        vault.cancelDeliveryProposal(clientId);
        assertTrue(vault.deliveryProposals(clientId).cancelled);

        uint256 adminId = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelDeliveryProposal(adminId);

        uint256 ownerId = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelDeliveryProposal(ownerId);
    }

    function testCancelDelivery_OpenP2P_Locked_AdminCanCancel() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(operatorAdmin);
        vault.cancelDeliveryProposal(id);
        assertTrue(vault.deliveryProposals(id).cancelled);
    }

    function testCancelDelivery_DeliveryOnly_AdminCanCancel() public {
        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);

        vm.prank(operatorOwner);
        vault.cancelDeliveryProposal(id);
        assertTrue(vault.deliveryProposals(id).cancelled);
    }

    function testDeliveryExecute_OpenP2P_UnlockedSkipsAdminApproval() public {
        _deposit(address(usdt), 1_000);
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(client);
        vault.executeDelivery(id);

        assertEq(usdt.balanceOf(recipient), 100);
    }

    function testDeliveryExecute_OpenP2P_LockedWithoutAdminApprovalReverts() public {
        _deposit(address(usdt), 1_000);
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        uint256 unlocksAt = vault.tokenLockUntil(address(usdt));
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), unlocksAt));
        vault.executeDelivery(id);
    }

    function testDeliveryExecute_OpenP2P_RevertsWhenExtraFeeTokenLockedWithoutAdminApproval() public {
        _deposit(address(usdt), 1_000);
        _deposit(address(weth), 100);
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 lockId = _proposeLock(address(weth), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        OTCTypes.ExtraFee memory extraFee =
            OTCTypes.ExtraFee({token: address(weth), amount: 10, receiver: extraReceiver});

        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            extraFee
        );

        uint256 unlocksAt = vault.tokenLockUntil(address(weth));
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(weth), unlocksAt));
        vault.executeDelivery(id);
    }

    function testDeliveryExecute_OpenP2P_AllowsExtraFeeWhenExtraFeeTokenUnlockedWithoutAdminApproval() public {
        _deposit(address(usdt), 1_000);
        _deposit(address(weth), 100);
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        OTCTypes.ExtraFee memory extraFee =
            OTCTypes.ExtraFee({token: address(weth), amount: 10, receiver: extraReceiver});

        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            extraFee
        );

        vm.prank(client);
        vault.executeDelivery(id);

        assertEq(usdt.balanceOf(recipient), 100);
        assertEq(weth.balanceOf(extraReceiver), 10);
    }

    function testDeliveryExecute_DeliveryOnlyWithoutAdminApprovalReverts() public {
        _deposit(address(usdt), 1_000);

        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.AdminNotApproved.selector);
        vault.executeDelivery(id);
    }

    function testDeliveryExecute_AutoApprovesOperatorRoleFromExecutor() public {
        _deposit(address(usdt), 1_000);

        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(operatorOwner);
        vault.executeDelivery(id);

        OTCTypes.DeliveryProposal memory proposal = vault.deliveryProposals(id);
        assertTrue(proposal.adminApproved);
        assertTrue(proposal.executed);
        assertEq(usdt.balanceOf(recipient), 100);
    }

    function testDeliveryApprovalRoles_OperatorOwnerAndAdminCanApprove() public {
        vm.prank(client);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        OTCTypes.DeliveryProposal memory first = vault.deliveryProposals(id);
        assertTrue(first.clientApproved);
        assertFalse(first.adminApproved);

        vm.prank(operatorOwner);
        vault.acceptDeliveryProposal(id);

        OTCTypes.DeliveryProposal memory afterOwnerApprove = vault.deliveryProposals(id);
        assertTrue(afterOwnerApprove.adminApproved);

        vm.prank(operatorAdmin);
        vault.acceptDeliveryProposal(id);
        OTCTypes.DeliveryProposal memory afterAdminApprove = vault.deliveryProposals(id);
        assertTrue(afterAdminApprove.adminApproved);
    }

    function testDeliveryApprovalRoles_RevertsForStranger() public {
        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);

        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.acceptDeliveryProposal(id);
    }

    function testDeliveryBase_RevertsInvalidExpectedAmount() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidExpectedAmount.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 1,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testAllowanceCallDelivery_NoExpectedToken() public {
        _deposit(address(usdt), 1_000);
        SimpleSwapTarget target = new SimpleSwapTarget();
        weth.mint(address(target), 500);

        bytes memory callData =
            abi.encodeCall(SimpleSwapTarget.swap, (address(usdt), address(vault), 500, address(weth), 500));

        vm.prank(operatorAdmin);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: true,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 500,
                deliveryAddress: address(target),
                target: address(target),
                callData: callData,
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vault.executeDelivery(id);

        // No lock update should happen when expectedReceivedToken is not set.
        assertEq(vault.tokenLockUntil(address(weth)), 0);
    }

    function testAllowanceCallDelivery_RevertsCallFailed() public {
        _deposit(address(usdt), 1_000);
        RevertingTarget target = new RevertingTarget();

        bytes memory callData = abi.encodeWithSignature("doesNotExist()");

        vm.prank(operatorAdmin);
        uint256 id = vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: true,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 500,
                deliveryAddress: address(target),
                target: address(target),
                callData: callData,
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vm.expectRevert(IOTCClientVaultErrors.DeliveryCallFailed.selector);
        vault.executeDelivery(id);
    }

    function testDeliveryProposals_ReturnsStruct() public {
        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        OTCTypes.DeliveryProposal memory proposal = vault.deliveryProposals(id);

        assertFalse(proposal.useAllowanceCall);
        assertEq(proposal.token, address(usdt));
        assertEq(proposal.amount, 100);
        assertEq(proposal.deliveryAddress, recipient);
        assertTrue(proposal.adminApproved);
        assertFalse(proposal.clientApproved);
        assertFalse(proposal.executed);
        assertFalse(proposal.cancelled);
    }

    function testCancelDeliveryProposal_RevertsStranger() public {
        uint256 id = _proposeDirectDelivery(address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelDeliveryProposal(id);
    }

    function testAcceptDeliveryProposal_RevertsInvalidProposal() public {
        vm.expectRevert(IOTCClientVaultErrors.InvalidProposal.selector);
        vault.acceptDeliveryProposal(999);
    }

    function testProposeDelivery_RevertsZeroToken() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(0),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testProposeDelivery_RevertsZeroAmount() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAmount.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 0,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testProposeDelivery_RevertsExpiredDeadline() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidDeadline.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp
            }),
            emptyExtraFee
        );
    }

    function testProposeDelivery_RevertsZeroExtraFeeReceiver() public {
        // amount>0, token set, receiver=0 → covers line 547 (InvalidExtraFeeReceiver for nonzero amount)
        OTCTypes.ExtraFee memory badFee = OTCTypes.ExtraFee({token: address(usdt), amount: 10, receiver: address(0)});
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidExtraFeeReceiver.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            badFee
        );
    }

    function testProposeDelivery_RevertsExtraFeeZeroAmountNonZeroReceiver() public {
        // amount=0, token=0, receiver nonzero → covers line 543 (InvalidExtraFeeReceiver inside amount==0 branch)
        OTCTypes.ExtraFee memory badFee = OTCTypes.ExtraFee({token: address(0), amount: 0, receiver: extraReceiver});
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidExtraFeeReceiver.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            badFee
        );
    }

    // ── Group 4: Fee edge cases ───────────────────────────────────────────────────

    function testChargeFee_ZeroBps() public {
        // 5 < 100 (current) → sync is allowed; 500 * 5 / 10_000 = 0 so no fees are charged
        OTCTypes.OperatorFeeConfig memory zeroFeeConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 5, deliveryFeeBps: 5, openP2PFeeBps: 5});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(zeroFeeConfig);
        vm.prank(client);
        vault.syncFeeFromFactory();

        _deposit(address(usdt), 1_000);
        uint256 id = _proposeDirectDelivery(address(usdt), 500, recipient, emptyExtraFee);
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vault.executeDelivery(id);

        assertEq(usdt.balanceOf(recipient), 500);
        assertEq(usdt.balanceOf(protocolReceiver), 0);
        assertEq(usdt.balanceOf(operatorReceiver), 0);
    }

    function testExtraFee_RevertsNonZeroAmountZeroToken() public {
        OTCTypes.ExtraFee memory badFee = OTCTypes.ExtraFee({token: address(0), amount: 100, receiver: extraReceiver});
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidExtraFeeToken.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            badFee
        );
    }

    function testExtraFee_RevertsNonZeroAmountZeroReceiver() public {
        OTCTypes.ExtraFee memory badFee = OTCTypes.ExtraFee({token: address(usdt), amount: 100, receiver: address(0)});
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidExtraFeeReceiver.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            badFee
        );
    }

    function testExtraFee_RevertsZeroAmountNonZeroToken() public {
        OTCTypes.ExtraFee memory badFee = OTCTypes.ExtraFee({token: address(usdt), amount: 0, receiver: address(0)});
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidExtraFeeToken.selector);
        vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            badFee
        );
    }

    // ── Group 5: Swap proposal edge cases ────────────────────────────────────────

    function testCreateSwap_RevertsDeliveryOnlyLevel() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidSwapLevel.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.DeliveryOnly,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwap_RevertsWhenVaultIsDeliveryOnly() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.SupplierOnly,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwap_RevertsSupplierOnlyByNonAdmin() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.SupplierOnly);
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.NotFactoryAdmin.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.SupplierOnly,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwap_RevertsManagedP2PByStranger() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotSwapParticipant.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwap_OpenP2P_AllowsFactoryAdmin() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        vm.prank(operatorAdmin);
        uint256 swapId = vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        OTCTypes.SwapProposal memory proposal = vault.swapProposals(swapId);
        assertEq(proposal.proposer, operatorAdmin);
        assertTrue(proposal.adminApproved);
    }

    function testCreateSwap_RevertsOpenP2PWithLockedToken() public {
        vm.prank(operatorAdmin);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        uint256 unlocksAt = vault.tokenLockUntil(address(usdt));
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), unlocksAt));
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testExecuteSwap_OpenP2P_RevertsLockedToken() public {
        _deposit(address(usdt), 1_000);
        vm.prank(operatorAdmin);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 swapId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);

        // Lock usdt after proposal creation
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        uint256 unlocksAt = vault.tokenLockUntil(address(usdt));
        vm.prank(counterparty);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), unlocksAt));
        vault.executeSwap(swapId);
    }

    function testApproveSwap_RevertsNotParticipant() public {
        uint256 swapId = _createSwap(
            operatorAdmin, OTCTypes.SwapAccessLevel.SupplierOnly, counterparty, address(usdt), 100, address(weth), 100
        );

        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotSwapParticipant.selector);
        vault.approveSwap(swapId);
    }

    function testSwapProposals_ReturnsStruct() public {
        uint256 swapId = _createSwap(
            client, OTCTypes.SwapAccessLevel.ManagedP2P, counterparty, address(usdt), 100, address(weth), 120
        );
        OTCTypes.SwapProposal memory proposal = vault.swapProposals(swapId);

        assertEq(uint256(proposal.level), uint256(OTCTypes.SwapAccessLevel.ManagedP2P));
        assertEq(proposal.proposer, client);
        assertEq(proposal.counterparty, counterparty);
        assertEq(proposal.tokenOut, address(usdt));
        assertEq(proposal.amountOut, 100);
        assertEq(proposal.tokenIn, address(weth));
        assertEq(proposal.amountIn, 120);
        assertTrue(proposal.clientApproved);
        assertFalse(proposal.counterpartyApproved);
        assertFalse(proposal.executed);
        assertFalse(proposal.cancelled);
    }

    function testCancelSwap_ByCounterparty() public {
        uint256 swapId = _createSwap(
            client, OTCTypes.SwapAccessLevel.ManagedP2P, counterparty, address(usdt), 100, address(weth), 100
        );

        vm.prank(counterparty);
        vault.cancelSwapProposal(swapId);

        // Verify cancelled: trying to approve should revert
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vault.approveSwap(swapId);
    }

    function testCancelSwap_OpenP2P_Unlocked_OnlyOwnerOrCounterpartyCanCancel() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 ownerId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);
        vm.prank(client);
        vault.cancelSwapProposal(ownerId);
        assertTrue(vault.swapProposals(ownerId).cancelled);

        uint256 adminId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelSwapProposal(adminId);

        uint256 factoryOwnerId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelSwapProposal(factoryOwnerId);

        uint256 counterpartyId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);
        vm.prank(counterparty);
        vault.cancelSwapProposal(counterpartyId);
        assertTrue(vault.swapProposals(counterpartyId).cancelled);
    }

    function testCancelSwap_OpenP2P_Locked_AdminCanCancel() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 swapId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);

        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        vm.prank(operatorAdmin);
        vault.cancelSwapProposal(swapId);
        assertTrue(vault.swapProposals(swapId).cancelled);
    }

    function testCancelSwap_RevertsInvalidProposal() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidProposal.selector);
        vault.cancelSwapProposal(999);
    }

    function testCancelSwap_RevertsAlreadyExecuted() public {
        _deposit(address(usdt), 1_000);
        weth.mint(counterparty, 100);
        vm.prank(counterparty);
        weth.approve(address(vault), 100);

        vm.prank(operatorAdmin);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 swapId =
            _createSwap(client, OTCTypes.SwapAccessLevel.OpenP2P, counterparty, address(usdt), 100, address(weth), 100);
        vm.prank(counterparty);
        vault.executeSwap(swapId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyExecuted.selector);
        vault.cancelSwapProposal(swapId);
    }

    function testCancelSwap_RevertsAlreadyCancelled() public {
        uint256 swapId = _createSwap(
            client, OTCTypes.SwapAccessLevel.ManagedP2P, counterparty, address(usdt), 100, address(weth), 100
        );
        vm.prank(client);
        vault.cancelSwapProposal(swapId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vault.cancelSwapProposal(swapId);
    }

    function testCancelSwap_RevertsUnauthorized() public {
        uint256 swapId = _createSwap(
            client, OTCTypes.SwapAccessLevel.ManagedP2P, counterparty, address(usdt), 100, address(weth), 100
        );

        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.cancelSwapProposal(swapId);
    }

    function testExecuteSwap_RevertsLevelDowngraded() public {
        _deposit(address(usdt), 1_000);
        weth.mint(counterparty, 100);
        vm.prank(counterparty);
        weth.approve(address(vault), 100);

        // Create ManagedP2P proposal
        uint256 swapId = _createSwap(
            client, OTCTypes.SwapAccessLevel.ManagedP2P, counterparty, address(usdt), 100, address(weth), 100
        );

        // Approve all parties while current level still permits the proposal.
        vm.prank(operatorAdmin);
        vault.approveSwap(swapId);
        vm.prank(counterparty);
        vault.approveSwap(swapId);

        // Downgrade vault access to SupplierOnly after proposal approvals.
        vm.prank(client);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.SupplierOnly);

        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vault.executeSwap(swapId);
    }

    function testExecuteSwap_OpenP2P_RevertsWhenExtraFeeTokenLockedWithoutAdminApproval() public {
        _deposit(address(usdt), 1_000);
        weth.mint(counterparty, 100);
        vm.prank(counterparty);
        weth.approve(address(vault), 100);
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 lockId = _proposeLock(address(weth), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        OTCTypes.ExtraFee memory extraFee =
            OTCTypes.ExtraFee({token: address(weth), amount: 10, receiver: extraReceiver});
        vm.prank(client);
        uint256 swapId = vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            extraFee
        );

        uint256 unlocksAt = vault.tokenLockUntil(address(weth));
        vm.prank(counterparty);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(weth), unlocksAt));
        vault.executeSwap(swapId);
    }

    function testExecuteSwap_OpenP2P_AdminApprovedBypassesExtraFeeTokenLock() public {
        _deposit(address(usdt), 1_000);
        weth.mint(counterparty, 100);
        vm.prank(counterparty);
        weth.approve(address(vault), 100);
        _enableSwapLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 lockId = _proposeLock(address(weth), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        OTCTypes.ExtraFee memory extraFee =
            OTCTypes.ExtraFee({token: address(weth), amount: 10, receiver: extraReceiver});
        vm.prank(client);
        uint256 swapId = vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            extraFee
        );

        vm.prank(operatorAdmin);
        vault.approveSwap(swapId);
        vm.prank(counterparty);
        vault.executeSwap(swapId);

        assertEq(weth.balanceOf(extraReceiver), 10);
    }

    function testDeliveryOnlyMode_BlocksSwapApproveAndExecute_ButAllowsCancel() public {
        uint256 swapId = _createSwap(
            client, OTCTypes.SwapAccessLevel.ManagedP2P, counterparty, address(usdt), 100, address(weth), 100
        );

        vm.prank(client);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.DeliveryOnly);

        vm.prank(counterparty);
        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vault.approveSwap(swapId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vault.executeSwap(swapId);

        vm.prank(counterparty);
        vault.cancelSwapProposal(swapId);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vault.approveSwap(swapId);
    }

    function testCreateSwapProposal_RevertsZeroCounterparty() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: address(0),
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwapProposal_RevertsZeroTokens() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidSwapTokens.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(0),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwapProposal_RevertsZeroAmounts() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidSwapAmounts.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 0,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function testCreateSwapProposal_RevertsExpiredDeadline() public {
        _enableSwapLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidDeadline.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: counterparty,
                tokenOut: address(usdt),
                amountOut: 100,
                tokenIn: address(weth),
                amountIn: 100,
                deadline: block.timestamp
            }),
            emptyExtraFee
        );
    }

    function testExecuteSwap_RevertsClientNotApproved() public {
        _deposit(address(usdt), 1_000);
        weth.mint(counterparty, 100);
        vm.prank(counterparty);
        weth.approve(address(vault), 100);

        _enableSwapLevel(OTCTypes.SwapAccessLevel.SupplierOnly);

        // Admin creates the swap — adminApproved=true, but clientApproved=false
        uint256 swapId = _createSwap(
            operatorAdmin, OTCTypes.SwapAccessLevel.SupplierOnly, counterparty, address(usdt), 100, address(weth), 100
        );

        vm.prank(counterparty);
        vault.approveSwap(swapId);

        vm.expectRevert(IOTCClientVaultErrors.ClientNotApproved.selector);
        vault.executeSwap(swapId);
    }

    // ── Group 6: OTCFactoryRegistry edge cases ────────────────────────────────────

    function testRegisterVault_RevertsZeroVault() public {
        // Register the mock factory so it passes the isOperatorFactory check
        // We need to deploy it via registry or spoof registry state.
        // Use a deployed real factory address but call registerVault directly from it.
        // The only way to call registerVault is from a registered factory.
        // We deploy a MockBadFactory, then set it as an operator factory via a hack.
        MockBadFactory mockFactory = new MockBadFactory(registry);

        // Manually register the mock factory as a known operator factory
        vm.store(
            address(registry),
            keccak256(abi.encode(address(mockFactory), uint256(3))), // slot 3: isOperatorFactory mapping
            bytes32(uint256(1))
        );

        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        mockFactory.registerZeroVault();
    }

    // ── Vault fee config caching ─────────────────────────────────────────────────

    function testVaultInitialize_CopiesFeeRatesFromFactory() public view {
        (uint16 takerBps, uint16 deliveryBps, uint16 openBps) = vault.vaultFeeConfig();
        assertEq(takerBps, 100);
        assertEq(deliveryBps, 100);
        assertEq(openBps, 50);
    }

    function testSyncFeeFromFactory_SucceedsWhenFeesDecrease() public {
        OTCTypes.OperatorFeeConfig memory lowerConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 50, deliveryFeeBps: 50, openP2PFeeBps: 25});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(lowerConfig);

        vm.prank(client);
        vault.syncFeeFromFactory();

        (uint16 takerBps, uint16 deliveryBps, uint16 openBps) = vault.vaultFeeConfig();
        assertEq(takerBps, 50);
        assertEq(deliveryBps, 50);
        assertEq(openBps, 25);
    }

    function testSyncFeeFromFactory_SucceedsWhenFeesEqual() public {
        // Same fees as current — allowed (not worse for user)
        vm.prank(client);
        vault.syncFeeFromFactory();

        (uint16 takerBps, uint16 deliveryBps, uint16 openBps) = vault.vaultFeeConfig();
        assertEq(takerBps, 100);
        assertEq(deliveryBps, 100);
        assertEq(openBps, 50);
    }

    function testSyncFeeFromFactory_RevertsWhenAnyFeeIncreases() public {
        OTCTypes.OperatorFeeConfig memory higherConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 50, deliveryFeeBps: 200, openP2PFeeBps: 25});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(higherConfig);

        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.FeeNotImproved.selector);
        vault.syncFeeFromFactory();
    }

    function testSyncFeeFromFactory_EmitsEvent() public {
        OTCTypes.OperatorFeeConfig memory lowerConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 50, deliveryFeeBps: 75, openP2PFeeBps: 25});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(lowerConfig);

        vm.prank(client);
        vm.expectEmit(false, false, false, true);
        emit IOTCClientVaultEvents.VaultFeeConfigSynced(50, 75, 25);
        vault.syncFeeFromFactory();
    }

    function testSyncFeeFromFactory_RevertsStranger() public {
        vm.prank(address(0x9999));
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vault.syncFeeFromFactory();
    }

    function testFeeSnapshot_StaleAfterFactoryFeeIncrease() public {
        // Factory raises fees — sync is blocked, vault keeps original rates
        OTCTypes.OperatorFeeConfig memory newConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 500, deliveryFeeBps: 500, openP2PFeeBps: 500});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(newConfig);

        // Snapshot (captured at proposal creation) should still use vault's stale cached rates
        _deposit(address(usdt), 1_000);
        uint256 id = _proposeDirectDelivery(address(usdt), 500, recipient, emptyExtraFee);
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vault.executeDelivery(id);

        // With old 100 bps delivery fee (Gross): fee = 500 * 100 / 10_000 = 5
        // protocolFee = 5 * 1_000 / 10_000 = 0 (rounds down), operatorFee = 5
        // Key point: NOT using new 500 bps (which would give 25)
        assertEq(usdt.balanceOf(recipient), 500);
        assertEq(usdt.balanceOf(operatorReceiver), 5);
        assertTrue(usdt.balanceOf(operatorReceiver) < 25, "should use old 100bps, not new 500bps");
    }

    // ── Group: setSwapAccessLevel access control ──────────────────────────────────

    function testSetSwapAccessLevel_FromDeliveryOnly_RevertsForOwner() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.NotFactoryAdmin.selector);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
    }

    function testSetSwapAccessLevel_FromDeliveryOnly_SucceedsForAdmin() public {
        vm.prank(operatorAdmin);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
        assertEq(uint8(vault.swapAccessLevel()), uint8(OTCTypes.SwapAccessLevel.OpenP2P));
    }

    function testSetSwapAccessLevel_FromNonDeliveryOnly_SucceedsForOwner() public {
        vm.prank(operatorAdmin);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        vm.prank(client);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
        assertEq(uint8(vault.swapAccessLevel()), uint8(OTCTypes.SwapAccessLevel.ManagedP2P));
    }

    function testSetSwapAccessLevel_FromNonDeliveryOnly_RevertsForAdmin() public {
        vm.prank(operatorAdmin);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        vm.prank(operatorAdmin);
        vm.expectRevert();
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.ManagedP2P);
    }
}
