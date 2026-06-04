// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCConstants} from "../src/constants/OTCConstants.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {IOTCClientVaultErrors} from "../src/interfaces/IOTCClientVaultErrors.sol";
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

/// @dev Registers a vault with zero vault/client address to exercise the require checks in registerVault.
contract MockBadFactory {
    OTCFactoryRegistry private immutable _registry;

    constructor(OTCFactoryRegistry registry_) {
        _registry = registry_;
    }

    function registerZeroVault(address client) external {
        _registry.registerVault(address(0), client);
    }

    function registerZeroClient(address vault) external {
        _registry.registerVault(vault, address(0));
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

        registry = new OTCFactoryRegistry(protocolOwner, protocolReceiver, 1_000);

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        factory =
            OTCOperatorFactory(registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, config));

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
        return vault.proposeLock(token, duration, block.timestamp + 1 days);
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

    function _createSwap(
        address proposer,
        OTCTypes.SwapAccessLevel level,
        address cp,
        address tokenOut,
        uint256 amountOut,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256) {
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

    // ── Group 1: receive() and withdrawal edge cases ──────────────────────────────

    function testReceive_AcceptsEth() public {
        vm.deal(address(this), 1 ether);
        (bool ok,) = address(vault).call{value: 1 ether}("");
        assertTrue(ok);
        assertEq(address(vault).balance, 1 ether);
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

    function testWithdrawAll_RevertsZeroToken() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.withdrawAll(address(0), recipient);
    }

    function testWithdrawAll_RevertsZeroTo() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.withdrawAll(address(usdt), address(0));
    }

    function testWithdrawAll_RevertsTokenLocked() public {
        _deposit(address(usdt), 1_000);
        uint256 lockId = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(lockId);

        uint256 unlocksAt = vault.tokenLockUntil(address(usdt));
        vm.prank(client);
        vm.expectRevert(abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), unlocksAt));
        vault.withdrawAll(address(usdt), recipient);
    }

    // ── Group 2: Lock proposal edge cases ────────────────────────────────────────

    function testProposeLock_RevertsZeroToken() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vault.proposeLock(address(0), 1 days, block.timestamp + 1 days);
    }

    function testProposeLock_RevertsDurationTooLarge() public {
        uint256 tooLong = OTCConstants.MAX_LOCK_DURATION + 1;
        vm.prank(operatorAdmin);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCClientVaultErrors.LockDurationTooLarge.selector, tooLong, OTCConstants.MAX_LOCK_DURATION
            )
        );
        vault.proposeLock(address(usdt), tooLong, block.timestamp + 1 days);
    }

    function testProposeLock_RevertsDeadlinePast() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidDeadline.selector);
        vault.proposeLock(address(usdt), 1 days, block.timestamp);
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

        (,, uint256 newLockUntil, uint256 deadline,,,) = vault.lockProposals(lockId);
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

        // No lock inheritance should happen (expectedReceivedToken == address(0))
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

    // ── Group 4: Fee edge cases ───────────────────────────────────────────────────

    function testChargeFee_ZeroBps() public {
        OTCTypes.OperatorFeeConfig memory zeroFeeConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 0, deliveryFeeBps: 0, openP2PFeeBps: 0});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(zeroFeeConfig);

        _deposit(address(usdt), 1_000);
        uint256 id = _proposeDirectDelivery(address(usdt), 500, recipient, emptyExtraFee);
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vault.executeDelivery(id);

        assertEq(usdt.balanceOf(recipient), 500);
        assertEq(usdt.balanceOf(protocolReceiver), 0);
        assertEq(usdt.balanceOf(operatorReceiver), 0);
    }

    function testChargeFee_FullProtocolFeeShare() public {
        // Set protocol fee share to 100% so operator net fee = 0
        vm.prank(protocolOwner);
        registry.setCustomProtocolFeeShareBps(address(factory), 10_000);

        // Deposit extra to cover fee: delivery = 10_000, fee = 10_000 * 100bps / 10_000 = 100
        _deposit(address(usdt), 10_100);
        uint256 id = _proposeDirectDelivery(address(usdt), 10_000, recipient, emptyExtraFee);
        vm.prank(client);
        vault.acceptDeliveryProposal(id);
        vault.executeDelivery(id);

        // protocolShare = 10_000/10_000 → all 100 to protocol, 0 to operator
        assertEq(usdt.balanceOf(recipient), 10_000);
        assertEq(usdt.balanceOf(protocolReceiver), 100);
        assertEq(usdt.balanceOf(operatorReceiver), 0);
    }

    function testInheritLock_NoUpdateWhenTokenInAlreadyLonger() public {
        _deposit(address(usdt), 10_000);
        weth.mint(counterparty, 1_000);
        vm.prank(counterparty);
        weth.approve(address(vault), 1_000);

        // Lock tokenIn (weth) for 30 days
        uint256 wethLock = _proposeLock(address(weth), 30 days);
        vm.prank(client);
        vault.acceptLockProposal(wethLock);
        uint256 wethLockedUntil = vault.tokenLockUntil(address(weth));

        // Lock tokenOut (usdt) for only 1 day
        uint256 usdtLock = _proposeLock(address(usdt), 1 days);
        vm.prank(client);
        vault.acceptLockProposal(usdtLock);

        // Execute a SupplierOnly swap: usdt out, weth in
        // _inheritLock(usdt, weth): outLock(usdt) < tokenLockUntil(weth), so no update
        uint256 swapId = _createSwap(
            operatorAdmin,
            OTCTypes.SwapAccessLevel.SupplierOnly,
            counterparty,
            address(usdt),
            5_000,
            address(weth),
            1_000
        );
        vm.prank(client);
        vault.approveSwap(swapId);
        vm.prank(counterparty);
        vault.executeSwap(swapId);

        // weth lock should remain unchanged (it was already longer)
        assertEq(vault.tokenLockUntil(address(weth)), wethLockedUntil);
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

    function testCreateSwap_RevertsNoneLevel() public {
        vm.prank(client);
        vm.expectRevert(IOTCClientVaultErrors.InvalidSwapLevel.selector);
        vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.None,
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

    function testCreateSwap_RevertsOpenP2PWithLockedToken() public {
        vm.prank(client);
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

    function testApproveSwap_OpenP2P_RevertsLockedToken() public {
        _deposit(address(usdt), 1_000);
        vm.prank(client);
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
        vault.approveSwap(swapId);
    }

    function testApproveSwap_RevertsNotParticipant() public {
        uint256 swapId = _createSwap(
            operatorAdmin, OTCTypes.SwapAccessLevel.SupplierOnly, counterparty, address(usdt), 100, address(weth), 100
        );

        vm.prank(stranger);
        vm.expectRevert(IOTCClientVaultErrors.NotSwapParticipant.selector);
        vault.approveSwap(swapId);
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

        vm.prank(client);
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

        // Downgrade vault access to SupplierOnly after proposal creation
        vm.prank(client);
        vault.setSwapAccessLevel(OTCTypes.SwapAccessLevel.SupplierOnly);

        // Approve all parties
        vm.prank(operatorAdmin);
        vault.approveSwap(swapId);
        vm.prank(counterparty);
        vault.approveSwap(swapId);

        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
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
            keccak256(abi.encode(address(mockFactory), uint256(2))), // slot 2: isOperatorFactory mapping
            bytes32(uint256(1))
        );

        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        mockFactory.registerZeroVault(client);
    }

    function testRegisterVault_RevertsZeroClient() public {
        MockBadFactory mockFactory = new MockBadFactory(registry);

        vm.store(address(registry), keccak256(abi.encode(address(mockFactory), uint256(2))), bytes32(uint256(1)));

        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        mockFactory.registerZeroClient(address(vault));
    }
}
