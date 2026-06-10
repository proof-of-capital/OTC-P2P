// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {IOTCClientVaultErrors} from "../src/interfaces/IOTCClientVaultErrors.sol";
import {IOTCOperatorFactoryErrors} from "../src/interfaces/IOTCOperatorFactoryErrors.sol";
import {IOTCFactoryRegistryErrors} from "../src/interfaces/IOTCFactoryRegistryErrors.sol";

/// @notice Minimal ERC-20 with unrestricted minting for test setup.
contract MockERC20 is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    /// @notice Mints `amount` tokens to `to`. No access control — tests only.
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

/// @notice Simulates an external swap contract: pulls `tokenOut` from caller via approval, sends back `tokenIn`.
contract DeliveryCallTarget {
    using SafeERC20 for IERC20;

    /// @notice Transfers `amountOut` of `tokenOut` from `from`, sends `amountIn` of `tokenIn` to `msg.sender`.
    function pullAndSend(address tokenOut, address from, uint256 amountOut, address tokenIn, uint256 amountIn)
        external
    {
        IERC20(tokenOut).safeTransferFrom(from, address(this), amountOut);
        IERC20(tokenIn).safeTransfer(msg.sender, amountIn);
    }
}

contract OTCP2PTest is Test {
    address protocolOwner = address(0x1001);
    address protocolReceiver = address(0x1002);
    address operatorOwner = address(0x2001);
    address operatorAdmin = address(0x2002);
    address operatorReceiver = address(0x2003);
    address clientA = address(0x3001);
    address clientB = address(0x3002);
    address supplier = address(0x4001);
    address externalParty = address(0x4002);
    address recipient = address(0x5001);
    address extraReceiver = address(0x5002);

    OTCFactoryRegistry registry;
    OTCOperatorFactory factory;
    OTCClientVault vaultA;
    OTCClientVault vaultB;
    MockERC20 usdt;
    MockERC20 weth;
    MockERC20 dai;

    OTCTypes.ExtraFee emptyExtraFee = OTCTypes.ExtraFee({token: address(0), amount: 0, receiver: address(0)});

    function setUp() public {
        usdt = new MockERC20("USD Tether", "USDT");
        weth = new MockERC20("Wrapped Ether", "WETH");
        dai = new MockERC20("Dai", "DAI");

        registry = new OTCFactoryRegistry(protocolOwner, protocolReceiver, 1_000, 2_000);

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        factory =
            OTCOperatorFactory(registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, config));

        vm.prank(operatorAdmin);
        vaultA = OTCClientVault(payable(factory.deployClientVault(clientA)));
        vm.prank(operatorAdmin);
        vaultB = OTCClientVault(payable(factory.deployClientVault(clientB)));
    }

    /// @notice Registry correctly tracks deployed factories and vaults; protocol fee overrides apply in priority order.
    function testRegistryFactoryDeploymentAndProtocolFeeOverrides() public {
        assertTrue(registry.isOperatorFactory(address(factory)));
        assertEq(registry.getOperatorFactoriesCount(), 1);
        assertTrue(registry.isVault(address(vaultA)));
        assertTrue(factory.isFactoryVault(address(vaultA)));
        assertEq(factory.getVaultsCount(), 2);
        assertEq(factory.owner(), operatorOwner);
        assertEq(factory.admin(), operatorAdmin);
        assertEq(registry.getDeliveryOnlyProtocolFeeShareBps(address(factory)), 1_000);
        assertEq(registry.getOtherProtocolFeeShareBps(address(factory)), 2_000);

        // Registry cannot increase — trying to set the same value reverts
        vm.prank(protocolOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.ProtocolFeeCannotIncrease.selector, 1_000, 1_000)
        );
        registry.setFactoryDeliveryOnlyProtocolFeeShareBps(address(factory), 1_000);
    }

    /// @notice Only the factory owner may change admin and fee receiver; changes take effect immediately.
    function testOwnerAdminAccessControlAndFactorySettings() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, address(this)));
        factory.setAdmin(address(0x9999));

        vm.prank(operatorOwner);
        factory.setAdmin(address(0x2222));
        assertEq(factory.admin(), address(0x2222));

        vm.prank(operatorOwner);
        factory.setOperatorFeeReceiver(address(0x3333));
        assertEq(factory.operatorFeeReceiver(), address(0x3333));

        vm.prank(operatorOwner);
        factory.setDefaultLockDuration(address(usdt), 30 days);
        assertEq(factory.defaultLockDuration(address(usdt)), 30 days);
    }

    /// @notice Deposits succeed; withdrawals succeed while unlocked and revert while locked.
    function testDepositWithdrawAndLockedWithdrawReverts() public {
        _deposit(vaultA, usdt, clientA, 1_000);

        vm.prank(clientA);
        vaultA.withdraw(address(usdt), 100, recipient);
        assertEq(usdt.balanceOf(recipient), 100);

        vm.prank(clientA);
        vaultA.withdraw(address(usdt), type(uint256).max, recipient);
        assertEq(usdt.balanceOf(recipient), 1_000);

        _deposit(vaultA, usdt, clientA, 1_000);

        uint256 lockId = _proposeLock(vaultA, address(usdt), 10 days);
        vm.prank(clientA);
        vaultA.acceptLockProposal(lockId);

        uint256 usdtUnlocksAt = vaultA.tokenLockUntil(address(usdt));
        vm.prank(clientA);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), usdtUnlocksAt)
        );
        vaultA.withdraw(address(usdt), 100, recipient);
    }

    /// @notice Accepting a shorter lock does not shorten an existing longer lock; admin can only reduce an active lock.
    function testLockAcceptDoesNotShortenAndAdminDecreaseLock() public {
        _deposit(vaultA, usdt, clientA, 1_000);
        uint256 longLock = _proposeLock(vaultA, address(usdt), 30 days);
        vm.prank(clientA);
        vaultA.acceptLockProposal(longLock);
        uint256 lockedUntil = vaultA.tokenLockUntil(address(usdt));

        uint256 shortLock = _proposeLock(vaultA, address(usdt), 1 days);
        vm.prank(clientA);
        vaultA.acceptLockProposal(shortLock);
        assertEq(vaultA.tokenLockUntil(address(usdt)), lockedUntil);

        vm.warp(block.timestamp + 2 days);
        uint256 decreasedLockUntil = block.timestamp + 5 days;
        vm.prank(operatorAdmin);
        vaultA.adminDecreaseLock(address(usdt), decreasedLockUntil);
        assertEq(vaultA.tokenLockUntil(address(usdt)), decreasedLockUntil);

        vm.prank(clientA);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), decreasedLockUntil)
        );
        vaultA.withdraw(address(usdt), 100, recipient);

        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.LockNotDecreased.selector);
        vaultA.adminDecreaseLock(address(usdt), decreasedLockUntil);

        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidLockUntil.selector);
        vaultA.adminDecreaseLock(address(usdt), block.timestamp);

        vm.warp(decreasedLockUntil + 1);

        vm.prank(clientA);
        vaultA.withdraw(address(usdt), 100, recipient);
        assertEq(usdt.balanceOf(recipient), 100);

        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.TokenNotLocked.selector);
        vaultA.adminDecreaseLock(address(usdt), decreasedLockUntil + 2 days);
    }

    /// @notice Cancelled proposals cannot be accepted or executed.
    function testCancelLockAndDeliveryPermissions() public {
        uint256 lockId = _proposeLock(vaultA, address(usdt), 1 days);
        vm.prank(clientA);
        vaultA.cancelLockProposal(lockId);

        uint256 deliveryId = _proposeDirectDelivery(vaultA, address(usdt), 100, recipient, emptyExtraFee);
        vm.prank(operatorOwner);
        vaultA.cancelDeliveryProposal(deliveryId);

        vm.prank(clientA);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vaultA.acceptDeliveryProposal(deliveryId);
    }

    /// @notice Direct delivery transfers tokens to the recipient and splits fees between operator and protocol.
    function testDirectDeliveryChargesDeliveryAndExtraFees() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        OTCTypes.ExtraFee memory extraFee =
            OTCTypes.ExtraFee({token: address(usdt), amount: 50, receiver: extraReceiver});

        uint256 proposalId = _proposeDirectDelivery(vaultA, address(usdt), 10_000, recipient, extraFee);
        vm.prank(clientA);
        vaultA.acceptDeliveryProposal(proposalId);
        vaultA.executeDelivery(proposalId);

        assertEq(usdt.balanceOf(recipient), 10_000);
        assertEq(usdt.balanceOf(protocolReceiver), 10);
        assertEq(usdt.balanceOf(operatorReceiver), 90);
        assertEq(usdt.balanceOf(extraReceiver), 50);
    }

    function testDeliveryUsesCurrentVaultLevelProtocolShareAtExecution() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        uint256 proposalId = _proposeDirectDelivery(vaultA, address(usdt), 10_000, recipient, emptyExtraFee);

        vm.prank(clientA);
        vaultA.acceptDeliveryProposal(proposalId);
        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
        vaultA.executeDelivery(proposalId);

        assertEq(usdt.balanceOf(protocolReceiver), 20);
        assertEq(usdt.balanceOf(operatorReceiver), 80);
    }

    function testDeliveryUsesCurrentFactoryProtocolShareAtExecution() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        uint256 proposalId = _proposeDirectDelivery(vaultA, address(usdt), 10_000, recipient, emptyExtraFee);

        vm.prank(clientA);
        vaultA.acceptDeliveryProposal(proposalId);
        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
        vm.prank(protocolOwner);
        registry.setFactoryOtherProtocolFeeShareBps(address(factory), 1_000);
        vaultA.executeDelivery(proposalId);

        assertEq(usdt.balanceOf(protocolReceiver), 10);
        assertEq(usdt.balanceOf(operatorReceiver), 90);
    }

    /// @notice Inclusive direct delivery treats amount as the total budget and deducts bps fees from it.
    function testDirectDeliveryInclusiveFeeModeDeductsFeeFromAmount() public {
        // deliveryFeeBps 1_000 > current 100, so we cannot sync existing vault.
        // Deploy new vault after updating factory config so it initializes with the new rates.
        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 5, deliveryFeeBps: 1_000, openP2PFeeBps: 5});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(config);
        vm.prank(operatorAdmin);
        OTCClientVault newVault = OTCClientVault(payable(factory.deployClientVault(clientA)));

        _deposit(newVault, usdt, clientA, 100);
        uint256 proposalId = _proposeDirectDeliveryWithFeeMode(
            newVault, address(usdt), 100, recipient, OTCTypes.FeeMode.Inclusive, emptyExtraFee
        );
        vm.prank(clientA);
        newVault.acceptDeliveryProposal(proposalId);
        newVault.executeDelivery(proposalId);

        assertEq(usdt.balanceOf(recipient), 90);
        assertEq(usdt.balanceOf(protocolReceiver), 1);
        assertEq(usdt.balanceOf(operatorReceiver), 9);
        assertEq(usdt.balanceOf(address(newVault)), 0);
    }

    /// @notice Direct delivery mode rejects non-zero allowance-call fields (target, callData).
    function testDirectDeliveryRejectsAllowanceCallFields() public {
        bytes memory callData = abi.encodeWithSelector(bytes4(0x12345678));

        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.DirectDeliveryInvalidFields.selector);
        vaultA.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 1,
                deliveryAddress: recipient,
                target: address(0x1234),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.DirectDeliveryInvalidFields.selector);
        vaultA.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 1,
                deliveryAddress: recipient,
                target: address(0),
                callData: callData,
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    /// @notice Direct delivery mode rejects a zero delivery address.
    function testDirectDeliveryRejectsZeroDeliveryAddress() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.InvalidAddress.selector);
        vaultA.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 1,
                deliveryAddress: address(0),
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    /// @notice Allowance-call delivery mode rejects a zero delivery address.
    function testAllowanceCallDeliveryRejectsZeroDeliveryAddress() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.AllowanceDeliveryInvalidFields.selector);
        vaultA.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: true,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 1,
                deliveryAddress: address(0),
                target: address(0x1234),
                callData: abi.encodeWithSelector(bytes4(0x12345678)),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    /// @notice Allowance-call delivery resets allowance to zero and validates minimum received amount.
    function testAllowanceCallDeliveryResetsAllowanceAndChecksReceived() public {
        _deposit(vaultA, usdt, clientA, 20_000);

        DeliveryCallTarget target = new DeliveryCallTarget();
        weth.mint(address(target), 7_000);
        bytes memory callData = abi.encodeCall(
            DeliveryCallTarget.pullAndSend, (address(usdt), address(vaultA), 5_000, address(weth), 7_000)
        );

        uint256 proposalId = _proposeAllowanceDelivery(
            vaultA, address(usdt), 5_000, address(target), address(target), callData, address(weth), 7_000
        );
        vm.prank(clientA);
        vaultA.acceptDeliveryProposal(proposalId);
        vaultA.executeDelivery(proposalId);

        assertEq(usdt.allowance(address(vaultA), address(target)), 0);
        assertEq(weth.balanceOf(address(vaultA)), 7_000);
    }

    /// @notice Inclusive allowance-call delivery approves only the net amount after deducting delivery fees.
    function testAllowanceCallDeliveryInclusiveFeeModeApprovesOnlyNetAmount() public {
        // deliveryFeeBps 1_000 > current 100, so we cannot sync existing vault.
        // Deploy new vault after updating factory config so it initializes with the new rates.
        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 5, deliveryFeeBps: 1_000, openP2PFeeBps: 5});
        vm.prank(operatorOwner);
        factory.setDefaultFeeConfig(config);
        vm.prank(operatorAdmin);
        OTCClientVault newVault = OTCClientVault(payable(factory.deployClientVault(clientA)));

        _deposit(newVault, usdt, clientA, 100);
        DeliveryCallTarget target = new DeliveryCallTarget();
        weth.mint(address(target), 90);
        bytes memory callData =
            abi.encodeCall(DeliveryCallTarget.pullAndSend, (address(usdt), address(newVault), 90, address(weth), 90));

        uint256 proposalId = _proposeAllowanceDeliveryWithFeeMode(
            newVault,
            address(usdt),
            100,
            address(target),
            address(target),
            callData,
            address(weth),
            90,
            OTCTypes.FeeMode.Inclusive
        );
        vm.prank(clientA);
        newVault.acceptDeliveryProposal(proposalId);
        newVault.executeDelivery(proposalId);

        assertEq(weth.balanceOf(address(newVault)), 90);
        assertEq(usdt.balanceOf(protocolReceiver), 1);
        assertEq(usdt.balanceOf(operatorReceiver), 9);
        assertEq(usdt.allowance(address(newVault), address(target)), 0);
    }

    /// @notice Allowance-call delivery reverts for missing client approval and insufficient received amount.
    function testAllowanceCallDeliveryRevertsForMissingApprovalAndInsufficientReceived() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        DeliveryCallTarget target = new DeliveryCallTarget();
        weth.mint(address(target), 100);
        bytes memory callData =
            abi.encodeCall(DeliveryCallTarget.pullAndSend, (address(usdt), address(vaultA), 1_000, address(weth), 100));

        uint256 missingApprovalId = _proposeAllowanceDelivery(
            vaultA, address(usdt), 1_000, address(target), address(target), callData, address(weth), 100
        );
        vm.expectRevert(IOTCClientVaultErrors.ClientNotApproved.selector);
        vaultA.executeDelivery(missingApprovalId);

        uint256 insufficientId = _proposeAllowanceDelivery(
            vaultA, address(usdt), 1_000, address(target), address(target), callData, address(weth), 101
        );
        vm.prank(clientA);
        vaultA.acceptDeliveryProposal(insufficientId);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCClientVaultErrors.InsufficientReceived.selector, uint256(100), uint256(101))
        );
        vaultA.executeDelivery(insufficientId);
    }

    /// @notice New vaults default to DeliveryOnly, blocking all swap proposal levels.
    function testConstructorDefaultsSwapAccessLevelToDeliveryOnly() public {
        assertEq(uint8(vaultA.swapAccessLevel()), uint8(OTCTypes.SwapAccessLevel.DeliveryOnly));

        vm.startPrank(clientA);

        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vaultA.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.SupplierOnly,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: supplier,
                tokenOut: address(usdt),
                amountOut: 1,
                tokenIn: address(weth),
                amountIn: 1,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vaultA.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: externalParty,
                tokenOut: address(usdt),
                amountOut: 1,
                tokenIn: address(weth),
                amountIn: 1,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vaultA.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: externalParty,
                tokenOut: address(usdt),
                amountOut: 1,
                tokenIn: address(weth),
                amountIn: 1,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
        vm.stopPrank();
    }

    /// @notice Level 1 SupplierOnly moves tokens and charges taker fees.
    function testSupplierOnlySwapWithEoaCounterpartyTransfersFees() public {
        _deposit(vaultA, usdt, clientA, 120_000);
        weth.mint(supplier, 10_000);
        vm.prank(supplier);
        weth.approve(address(vaultA), 10_000);

        uint256 proposalId = _createSwap(
            vaultA,
            operatorAdmin,
            OTCTypes.SwapAccessLevel.SupplierOnly,
            supplier,
            address(usdt),
            100_000,
            address(weth),
            10_000
        );
        vm.prank(clientA);
        vaultA.approveSwap(proposalId);
        vm.prank(supplier);
        vaultA.executeSwap(proposalId);

        assertEq(usdt.balanceOf(supplier), 100_000);
        assertEq(weth.balanceOf(address(vaultA)), 9_900);
        assertEq(weth.balanceOf(protocolReceiver), 20);
        assertEq(weth.balanceOf(operatorReceiver), 80);
    }

    /// @notice Admin-created gross swaps charge taker fees above amountIn so the vault keeps the full quoted input.
    function testAdminCreatedGrossSwapChargesFeeAboveAmountIn() public {
        _deposit(vaultA, usdt, clientA, 120_000);
        weth.mint(supplier, 10_100);
        vm.prank(supplier);
        weth.approve(address(vaultA), 10_100);

        uint256 proposalId = _createSwapWithFeeMode(
            vaultA,
            operatorAdmin,
            OTCTypes.SwapAccessLevel.SupplierOnly,
            OTCTypes.FeeMode.Gross,
            supplier,
            address(usdt),
            100_000,
            address(weth),
            10_000
        );
        vm.prank(clientA);
        vaultA.approveSwap(proposalId);
        vm.prank(supplier);
        vaultA.executeSwap(proposalId);

        assertEq(usdt.balanceOf(supplier), 100_000);
        assertEq(weth.balanceOf(address(vaultA)), 10_000);
        assertEq(weth.balanceOf(protocolReceiver), 20);
        assertEq(weth.balanceOf(operatorReceiver), 80);
        assertEq(weth.balanceOf(supplier), 0);
    }

    /// @notice Non-admin swap creators are normalized to inclusive mode even when they request gross mode.
    function testNonAdminCreatedSwapNormalizesFeeModeToInclusive() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        weth.mint(externalParty, 10_000);
        vm.prank(externalParty);
        weth.approve(address(vaultA), 10_000);

        uint256 proposalId = _createSwapWithFeeMode(
            vaultA,
            clientA,
            OTCTypes.SwapAccessLevel.ManagedP2P,
            OTCTypes.FeeMode.Gross,
            externalParty,
            address(usdt),
            10_000,
            address(weth),
            5_000
        );
        vm.prank(externalParty);
        vaultA.approveSwap(proposalId);
        vm.prank(operatorAdmin);
        vaultA.executeSwap(proposalId);

        assertEq(weth.balanceOf(address(vaultA)), 4_950);
        assertEq(weth.balanceOf(protocolReceiver), 10);
        assertEq(weth.balanceOf(operatorReceiver), 40);
        assertEq(weth.balanceOf(externalParty), 5_000);
    }

    /// @notice A vault-to-vault swap is composed of a SupplierOnly swap on vaultA and allowance-call delivery on vaultB.
    function testVaultToVaultSwapUsesUnifiedSwapPlusAllowanceDelivery() public {
        _deposit(vaultA, usdt, clientA, 120_000);
        _deposit(vaultB, weth, clientB, 20_000);

        uint256 swapId = _createSwap(
            vaultA,
            operatorAdmin,
            OTCTypes.SwapAccessLevel.SupplierOnly,
            address(vaultB),
            address(usdt),
            100_000,
            address(weth),
            10_000
        );
        vm.prank(clientA);
        vaultA.approveSwap(swapId);

        bytes memory callData = abi.encodeCall(OTCClientVault.executeSwap, (swapId));
        uint256 deliveryId = _proposeAllowanceDelivery(
            vaultB, address(weth), 10_000, address(vaultA), address(vaultA), callData, address(usdt), 100_000
        );
        vm.prank(clientB);
        vaultB.acceptDeliveryProposal(deliveryId);
        vaultB.executeDelivery(deliveryId);

        assertEq(usdt.balanceOf(address(vaultB)), 100_000);
        assertEq(weth.balanceOf(address(vaultA)), 9_900);
        assertEq(weth.allowance(address(vaultB), address(vaultA)), 0);
    }

    /// @notice Level 2 ManagedP2P requires client, counterparty, and admin approvals before execution.
    function testManagedP2PLevelRequiresAllApprovals() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        weth.mint(externalParty, 10_000);
        vm.prank(externalParty);
        weth.approve(address(vaultA), 10_000);

        uint256 proposalId = _createSwap(
            vaultA,
            clientA,
            OTCTypes.SwapAccessLevel.ManagedP2P,
            externalParty,
            address(usdt),
            10_000,
            address(weth),
            5_000
        );

        vm.expectRevert(IOTCClientVaultErrors.CounterpartyNotApproved.selector);
        vaultA.executeSwap(proposalId);

        vm.prank(externalParty);
        vaultA.approveSwap(proposalId);
        vm.expectRevert(IOTCClientVaultErrors.AdminNotApproved.selector);
        vaultA.executeSwap(proposalId);

        vm.prank(operatorAdmin);
        vaultA.executeSwap(proposalId);

        assertEq(usdt.balanceOf(externalParty), 10_000);
        assertEq(weth.balanceOf(address(vaultA)), 4_950);
    }

    /// @notice Counterparty can initiate and later cancel a ManagedP2P proposal; cancelled proposals cannot be approved.
    function testManagedP2PLevelProposalToClientAndCancelByCounterparty() public {
        uint256 proposalId = _createSwap(
            vaultA,
            externalParty,
            OTCTypes.SwapAccessLevel.ManagedP2P,
            externalParty,
            address(usdt),
            1_000,
            address(weth),
            500
        );

        vm.prank(externalParty);
        vaultA.cancelSwapProposal(proposalId);

        vm.prank(clientA);
        vm.expectRevert(IOTCClientVaultErrors.ProposalAlreadyCancelled.selector);
        vaultA.approveSwap(proposalId);
    }

    /// @notice Level 3 OpenP2P succeeds only after the client enables it and charges the openP2PFeeBps.
    function testOpenP2PLevelRequiresUnlockedTokenAndChargesInfrastructureFee() public {
        _deposit(vaultA, usdt, clientA, 20_000);
        weth.mint(externalParty, 10_000);
        vm.prank(externalParty);
        weth.approve(address(vaultA), 10_000);

        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 proposalId = _createSwap(
            vaultA,
            clientA,
            OTCTypes.SwapAccessLevel.OpenP2P,
            externalParty,
            address(usdt),
            10_000,
            address(weth),
            5_000
        );
        vm.prank(externalParty);
        vaultA.executeSwap(proposalId);

        assertEq(usdt.balanceOf(externalParty), 10_000);
        assertEq(weth.balanceOf(address(vaultA)), 4_975);
        assertEq(weth.balanceOf(protocolReceiver), 5);
        assertEq(weth.balanceOf(operatorReceiver), 20);

        uint256 lockId = _proposeLock(vaultA, address(usdt), 1 days);
        vm.prank(clientA);
        vaultA.acceptLockProposal(lockId);

        uint256 usdtLockedUntil = vaultA.tokenLockUntil(address(usdt));
        vm.prank(clientA);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCClientVaultErrors.TokenLocked.selector, address(usdt), usdtLockedUntil)
        );
        vaultA.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: externalParty,
                tokenOut: address(usdt),
                amountOut: 1_000,
                tokenIn: address(weth),
                amountIn: 1_000,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    /// @notice OpenP2P re-checks the lock at execution time; the counterparty can cancel at any time.
    function testOpenP2PLevelRechecksLockAtExecutionAndCanBeCancelledByCounterparty() public {
        _deposit(vaultA, dai, clientA, 20_000);
        weth.mint(externalParty, 5_000);
        vm.prank(externalParty);
        weth.approve(address(vaultA), 5_000);

        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 proposalId = _createSwap(
            vaultA, clientA, OTCTypes.SwapAccessLevel.OpenP2P, externalParty, address(dai), 5_000, address(weth), 2_000
        );
        vm.prank(externalParty);
        vaultA.approveSwap(proposalId);

        uint256 lockId = _proposeLock(vaultA, address(dai), 1 days);
        vm.prank(clientA);
        vaultA.acceptLockProposal(lockId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCClientVaultErrors.TokenLocked.selector, address(dai), vaultA.tokenLockUntil(address(dai))
            )
        );
        vaultA.executeSwap(proposalId);

        uint256 cancelId = _createSwap(
            vaultA, clientA, OTCTypes.SwapAccessLevel.OpenP2P, externalParty, address(usdt), 1_000, address(weth), 1_000
        );
        vm.prank(externalParty);
        vaultA.cancelSwapProposal(cancelId);
    }

    /// @notice Cancellation permissions use the swap level captured in the proposal, even if vault level changes later.
    function testCancelSwapUsesProposalLevelSnapshotWhenVaultLevelChanges() public {
        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        uint256 openId = _createSwap(
            vaultA, clientA, OTCTypes.SwapAccessLevel.OpenP2P, externalParty, address(usdt), 1_000, address(weth), 1_000
        );
        vm.prank(clientA);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.ManagedP2P);

        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vaultA.cancelSwapProposal(openId);

        vm.prank(externalParty);
        vaultA.cancelSwapProposal(openId);
        assertTrue(vaultA.swapProposals(openId).cancelled);

        uint256 managedId = _createSwap(
            vaultA,
            clientA,
            OTCTypes.SwapAccessLevel.ManagedP2P,
            externalParty,
            address(usdt),
            1_000,
            address(weth),
            1_000
        );
        vm.prank(clientA);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);

        vm.prank(operatorAdmin);
        vaultA.cancelSwapProposal(managedId);
        assertTrue(vaultA.swapProposals(managedId).cancelled);
    }

    /// @notice Delivery cancellation also uses the proposal-level snapshot, not the current vault swap level.
    function testCancelDeliveryUsesProposalLevelSnapshotWhenVaultLevelChanges() public {
        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
        uint256 openId = _proposeDirectDelivery(vaultA, address(usdt), 100, recipient, emptyExtraFee);
        assertEq(uint8(vaultA.deliveryProposals(openId).level), uint8(OTCTypes.SwapAccessLevel.OpenP2P));

        vm.prank(clientA);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.DeliveryOnly);
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCClientVaultErrors.NotAuthorized.selector);
        vaultA.cancelDeliveryProposal(openId);

        uint256 deliveryOnlyId = _proposeDirectDelivery(vaultA, address(usdt), 100, recipient, emptyExtraFee);
        assertEq(uint8(vaultA.deliveryProposals(deliveryOnlyId).level), uint8(OTCTypes.SwapAccessLevel.DeliveryOnly));

        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
        vm.prank(operatorAdmin);
        vaultA.cancelDeliveryProposal(deliveryOnlyId);
        assertTrue(vaultA.deliveryProposals(deliveryOnlyId).cancelled);
    }

    /// @notice Access levels are cumulative and reject proposals above the configured maximum.
    function testSwapAccessLevelValidation() public {
        vm.prank(operatorAdmin);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.SupplierOnly);

        vm.prank(clientA);
        vm.expectRevert(IOTCClientVaultErrors.SwapLevelNotAllowed.selector);
        vaultA.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.ManagedP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: externalParty,
                tokenOut: address(usdt),
                amountOut: 1,
                tokenIn: address(weth),
                amountIn: 1,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(clientA);
        vaultA.setSwapAccessLevel(OTCTypes.SwapAccessLevel.OpenP2P);
        vm.prank(clientA);
        vaultA.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: OTCTypes.SwapAccessLevel.OpenP2P,
                feeMode: OTCTypes.FeeMode.Inclusive,
                counterparty: externalParty,
                tokenOut: address(usdt),
                amountOut: 1,
                tokenIn: address(weth),
                amountIn: 1,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    // ── Helpers ─────────────────────────────────────────────────────────────────

    function _deposit(OTCClientVault vault, MockERC20 token, address from, uint256 amount) internal {
        token.mint(from, amount);
        vm.startPrank(from);
        token.approve(address(vault), amount);
        vault.deposit(address(token), amount);
        vm.stopPrank();
    }

    function _proposeLock(OTCClientVault vault, address token, uint256 duration) internal returns (uint256) {
        vm.prank(operatorAdmin);
        return vault.proposeLock(token, block.timestamp + duration, block.timestamp + 1 days);
    }

    function _proposeDirectDelivery(
        OTCClientVault vault,
        address token,
        uint256 amount,
        address to,
        OTCTypes.ExtraFee memory extraFee
    ) internal returns (uint256) {
        return _proposeDirectDeliveryWithFeeMode(vault, token, amount, to, OTCTypes.FeeMode.Gross, extraFee);
    }

    function _proposeDirectDeliveryWithFeeMode(
        OTCClientVault vault,
        address token,
        uint256 amount,
        address to,
        OTCTypes.FeeMode feeMode,
        OTCTypes.ExtraFee memory extraFee
    ) internal returns (uint256) {
        vm.prank(operatorAdmin);
        return vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: feeMode,
                token: token,
                amount: amount,
                deliveryAddress: to,
                target: address(0),
                callData: bytes(""),
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            extraFee
        );
    }

    function _proposeAllowanceDelivery(
        OTCClientVault vault,
        address token,
        uint256 amount,
        address spender,
        address target,
        bytes memory callData,
        address expectedToken,
        uint256 expectedAmount
    ) internal returns (uint256) {
        return _proposeAllowanceDeliveryWithFeeMode(
            vault, token, amount, spender, target, callData, expectedToken, expectedAmount, OTCTypes.FeeMode.Gross
        );
    }

    function _proposeAllowanceDeliveryWithFeeMode(
        OTCClientVault vault,
        address token,
        uint256 amount,
        address spender,
        address target,
        bytes memory callData,
        address expectedToken,
        uint256 expectedAmount,
        OTCTypes.FeeMode feeMode
    ) internal returns (uint256) {
        vm.prank(operatorAdmin);
        return vault.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: true,
                feeMode: feeMode,
                token: token,
                amount: amount,
                deliveryAddress: spender,
                target: target,
                callData: callData,
                expectedReceivedToken: expectedToken,
                minExpectedReceivedAmount: expectedAmount,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }

    function _enableSwapLevel(OTCClientVault vault, OTCTypes.SwapAccessLevel level) internal {
        address client = address(vault) == address(vaultA) ? clientA : clientB;
        if (vault.swapAccessLevel() == OTCTypes.SwapAccessLevel.DeliveryOnly) {
            vm.prank(operatorAdmin);
        } else {
            vm.prank(client);
        }
        vault.setSwapAccessLevel(level);
    }

    function _createSwap(
        OTCClientVault vault,
        address proposer,
        OTCTypes.SwapAccessLevel level,
        address counterparty,
        address tokenOut,
        uint256 amountOut,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256) {
        return _createSwapWithFeeMode(
            vault, proposer, level, OTCTypes.FeeMode.Inclusive, counterparty, tokenOut, amountOut, tokenIn, amountIn
        );
    }

    function _createSwapWithFeeMode(
        OTCClientVault vault,
        address proposer,
        OTCTypes.SwapAccessLevel level,
        OTCTypes.FeeMode feeMode,
        address counterparty,
        address tokenOut,
        uint256 amountOut,
        address tokenIn,
        uint256 amountIn
    ) internal returns (uint256) {
        if (uint8(level) > uint8(vault.swapAccessLevel())) {
            _enableSwapLevel(vault, level);
        }
        vm.prank(proposer);
        return vault.createSwapProposal(
            OTCTypes.SwapProposalParams({
                level: level,
                feeMode: feeMode,
                counterparty: counterparty,
                tokenOut: tokenOut,
                amountOut: amountOut,
                tokenIn: tokenIn,
                amountIn: amountIn,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
    }
}
