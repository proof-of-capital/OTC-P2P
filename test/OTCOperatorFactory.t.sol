// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCConstants} from "../src/constants/OTCConstants.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IOTCOperatorFactoryErrors} from "../src/interfaces/IOTCOperatorFactoryErrors.sol";
import {IOTCOperatorFactoryEvents} from "../src/interfaces/IOTCOperatorFactoryEvents.sol";

contract OTCOperatorFactoryTest is Test {
    address protocolOwner = address(0x1001);
    address protocolReceiver = address(0x1002);
    address operatorOwner = address(0x2001);
    address operatorAdmin = address(0x2002);
    address operatorReceiver = address(0x2003);
    address client = address(0x3001);
    address stranger = address(0x9999);

    OTCFactoryRegistry registry;
    OTCOperatorFactory factory;

    OTCTypes.OperatorFeeConfig internal defaultConfig =
        OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});

    function setUp() public {
        registry = new OTCFactoryRegistry(protocolOwner, protocolReceiver, 1_000);
        vm.prank(operatorOwner);
        factory = OTCOperatorFactory(
            registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, defaultConfig)
        );
    }

    // ── Constructor ──────────────────────────────────────────────────────────────

    function testConstructor_SetsState() public view {
        assertEq(factory.registry(), address(registry));
        assertEq(factory.owner(), operatorOwner);
        assertEq(factory.admin(), operatorAdmin);
        assertEq(factory.operatorFeeReceiver(), operatorReceiver);

        (uint16 takerBps, uint16 deliveryBps, uint16 openP2PBps) = factory.defaultFeeConfig();
        assertEq(takerBps, 100);
        assertEq(deliveryBps, 100);
        assertEq(openP2PBps, 50);
    }

    function testConstructor_RevertsZeroRegistry() public {
        vm.expectRevert(IOTCOperatorFactoryErrors.NotRegistry.selector);
        new OTCOperatorFactory(address(0), operatorOwner, operatorAdmin, operatorReceiver, defaultConfig, 1_000);
    }

    function testConstructor_RevertsIfNotDeployedByRegistry() public {
        vm.expectRevert(IOTCOperatorFactoryErrors.NotRegistry.selector);
        new OTCOperatorFactory(address(registry), operatorOwner, operatorAdmin, operatorReceiver, defaultConfig, 1_000);
    }

    function testConstructor_RevertsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        vm.prank(address(registry));
        new OTCOperatorFactory(address(registry), address(0), operatorAdmin, operatorReceiver, defaultConfig, 1_000);
    }

    function testConstructor_RevertsZeroAdmin() public {
        vm.expectRevert(IOTCOperatorFactoryErrors.InvalidAddress.selector);
        vm.prank(address(registry));
        new OTCOperatorFactory(address(registry), operatorOwner, address(0), operatorReceiver, defaultConfig, 1_000);
    }

    function testConstructor_RevertsZeroFeeReceiver() public {
        vm.expectRevert(IOTCOperatorFactoryErrors.InvalidAddress.selector);
        vm.prank(address(registry));
        new OTCOperatorFactory(address(registry), operatorOwner, operatorAdmin, address(0), defaultConfig, 1_000);
    }

    function testConstructor_RevertsInvalidTakerFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 10_001, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        vm.prank(address(registry));
        new OTCOperatorFactory(address(registry), operatorOwner, operatorAdmin, operatorReceiver, bad, 1_000);
    }

    function testConstructor_RevertsInvalidDeliveryFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 10_001, openP2PFeeBps: 50});
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        vm.prank(address(registry));
        new OTCOperatorFactory(address(registry), operatorOwner, operatorAdmin, operatorReceiver, bad, 1_000);
    }

    function testConstructor_RevertsInvalidOpenP2PFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 10_001});
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        vm.prank(address(registry));
        new OTCOperatorFactory(address(registry), operatorOwner, operatorAdmin, operatorReceiver, bad, 1_000);
    }

    // ── deployClientVault ────────────────────────────────────────────────────────

    function testDeployClientVault_ByOwner() public {
        vm.prank(operatorOwner);
        address vault = factory.deployClientVault(client);
        assertTrue(vault != address(0));
    }

    function testDeployClientVault_ByAdmin() public {
        vm.prank(operatorAdmin);
        address vault = factory.deployClientVault(client);
        assertTrue(vault != address(0));
    }

    function testDeployClientVault_ByAnyone() public {
        vm.prank(stranger);
        address vault = factory.deployClientVault(client);
        OTCClientVault deployedVault = OTCClientVault(payable(vault));

        assertTrue(vault != address(0));
        assertTrue(factory.isFactoryVault(vault));
        assertTrue(registry.isVault(vault));
        assertEq(deployedVault.owner(), client);
        assertEq(deployedVault.factory(), address(factory));
        assertEq(deployedVault.nextProposalId(), 1);
        assertEq(uint8(deployedVault.swapAccessLevel()), uint8(OTCTypes.SwapAccessLevel.DeliveryOnly));
    }

    function testDeployClientVault_RevertsZeroClient() public {
        vm.prank(operatorAdmin);
        vm.expectRevert(IOTCOperatorFactoryErrors.InvalidAddress.selector);
        factory.deployClientVault(address(0));
    }

    function testDeployClientVault_Tracks() public {
        assertEq(factory.getVaultsCount(), 0);

        vm.prank(operatorAdmin);
        vm.expectEmit(true, false, false, false);
        emit IOTCOperatorFactoryEvents.ClientVaultDeployed(client, address(0));
        address vault = factory.deployClientVault(client);

        assertTrue(factory.isFactoryVault(vault));
        assertEq(factory.getVaultsCount(), 1);
        assertEq(factory.vaults(0), vault);
        assertTrue(registry.isVault(vault));
    }

    function testDeployClientVault_UsesMinimalProxyBytecode() public {
        vm.prank(operatorAdmin);
        address vault = factory.deployClientVault(client);
        assertEq(vault.code.length, 45);
    }

    function testDeployClientVault_RevertsOnSecondInitialize() public {
        vm.prank(operatorAdmin);
        address vault = factory.deployClientVault(client);
        OTCTypes.DefaultLockConfig[] memory defaultLocks = new OTCTypes.DefaultLockConfig[](0);

        vm.expectRevert(Initializable.InvalidInitialization.selector);
        OTCClientVault(payable(vault)).initialize(address(factory), client, defaultLocks);
    }

    function testDeployClientVault_UsesUpdatedImpl() public {
        address newImpl = address(new OTCClientVault());
        address oldImpl = registry.clientVaultImplementation();
        assertTrue(newImpl != oldImpl);

        vm.prank(protocolOwner);
        registry.setClientVaultImplementation(newImpl);

        address vault = factory.deployClientVault(client);

        // ERC1167 runtime: 363d3d373d3d3d363d73<20-byte-addr>5af4...
        // Implementation address starts at byte offset 10.
        bytes memory code = vault.code;
        address embeddedImpl;
        assembly {
            embeddedImpl := shr(96, mload(add(add(code, 0x20), 10)))
        }
        assertEq(embeddedImpl, newImpl);

        OTCClientVault deployedVault = OTCClientVault(payable(vault));
        assertEq(deployedVault.owner(), client);
        assertEq(deployedVault.factory(), address(factory));
    }

    // ── transferOwnership ──────────────────────────────────────────────────────

    function testTransferOwnership_Updates() public {
        address newOwner = address(0x8888);
        vm.prank(operatorOwner);
        vm.expectEmit(true, true, false, false);
        emit Ownable.OwnershipTransferred(operatorOwner, newOwner);
        factory.transferOwnership(newOwner);
        assertEq(factory.owner(), newOwner);
    }

    function testTransferOwnership_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        factory.transferOwnership(address(0x8888));
    }

    function testTransferOwnership_RevertsZero() public {
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        factory.transferOwnership(address(0));
    }

    // ── setAdmin ─────────────────────────────────────────────────────────────────

    function testSetAdmin_Updates() public {
        address newAdmin = address(0x7777);
        vm.prank(operatorOwner);
        vm.expectEmit(true, true, false, false);
        emit IOTCOperatorFactoryEvents.AdminUpdated(operatorAdmin, newAdmin);
        factory.setAdmin(newAdmin);
        assertEq(factory.admin(), newAdmin);
    }

    function testSetAdmin_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        factory.setAdmin(address(0x7777));
    }

    function testSetAdmin_RevertsZero() public {
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCOperatorFactoryErrors.InvalidAddress.selector);
        factory.setAdmin(address(0));
    }

    // ── setOperatorFeeReceiver ───────────────────────────────────────────────────

    function testSetOperatorFeeReceiver_Updates() public {
        address newReceiver = address(0x6666);
        vm.prank(operatorOwner);
        vm.expectEmit(true, true, false, false);
        emit IOTCOperatorFactoryEvents.OperatorFeeReceiverUpdated(operatorReceiver, newReceiver);
        factory.setOperatorFeeReceiver(newReceiver);
        assertEq(factory.operatorFeeReceiver(), newReceiver);
    }

    function testSetOperatorFeeReceiver_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        factory.setOperatorFeeReceiver(address(0x6666));
    }

    function testSetOperatorFeeReceiver_RevertsZero() public {
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCOperatorFactoryErrors.InvalidAddress.selector);
        factory.setOperatorFeeReceiver(address(0));
    }

    // ── setDefaultFeeConfig ──────────────────────────────────────────────────────

    function testSetDefaultFeeConfig_Updates() public {
        OTCTypes.OperatorFeeConfig memory newConfig =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 300, deliveryFeeBps: 150, openP2PFeeBps: 75});
        vm.prank(operatorOwner);
        vm.expectEmit(false, false, false, true);
        emit IOTCOperatorFactoryEvents.DefaultFeeConfigUpdated(300, 150, 75);
        factory.setDefaultFeeConfig(newConfig);

        (uint16 takerBps, uint16 deliveryBps, uint16 openP2PBps) = factory.defaultFeeConfig();
        assertEq(takerBps, 300);
        assertEq(deliveryBps, 150);
        assertEq(openP2PBps, 75);
    }

    function testSetDefaultFeeConfig_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        factory.setDefaultFeeConfig(defaultConfig);
    }

    function testSetDefaultFeeConfig_RevertsInvalidTakerFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 10_001, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        factory.setDefaultFeeConfig(bad);
    }

    function testSetDefaultFeeConfig_RevertsInvalidDeliveryFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 10_001, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        factory.setDefaultFeeConfig(bad);
    }

    function testSetDefaultFeeConfig_RevertsInvalidOpenP2PFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 10_001});
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        factory.setDefaultFeeConfig(bad);
    }

    // ── setDefaultLockDuration ───────────────────────────────────────────────────

    function testSetDefaultLockDuration_Updates() public {
        address token = address(0xABCD);
        vm.prank(operatorOwner);
        vm.expectEmit(true, false, false, true);
        emit IOTCOperatorFactoryEvents.DefaultLockDurationUpdated(token, 30 days);
        factory.setDefaultLockDuration(token, 30 days);
        assertEq(factory.defaultLockDuration(token), 30 days);
    }

    function testSetDefaultLockDuration_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        factory.setDefaultLockDuration(address(0xABCD), 30 days);
    }

    function testSetDefaultLockDuration_RevertsZeroToken() public {
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCOperatorFactoryErrors.InvalidAddress.selector);
        factory.setDefaultLockDuration(address(0), 30 days);
    }

    function testSetDefaultLockDuration_RevertsTooLarge() public {
        uint256 tooLong = OTCConstants.MAX_LOCK_DURATION + 1;
        vm.prank(operatorOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCOperatorFactoryErrors.LockDurationTooLarge.selector, tooLong, OTCConstants.MAX_LOCK_DURATION
            )
        );
        factory.setDefaultLockDuration(address(0xABCD), tooLong);
    }

    // ── setDefaultLockDurationsBatch ─────────────────────────────────────────────

    function testSetDefaultLockDurationsBatch_Updates() public {
        address tokenA = address(0xAAAA);
        address tokenB = address(0xBBBB);
        address[] memory tokens = new address[](2);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        uint256[] memory durations = new uint256[](2);
        durations[0] = 7 days;
        durations[1] = 14 days;

        vm.prank(operatorOwner);
        factory.setDefaultLockDurationsBatch(tokens, durations);

        assertEq(factory.defaultLockDuration(tokenA), 7 days);
        assertEq(factory.defaultLockDuration(tokenB), 14 days);
    }

    function testSetDefaultLockDurationsBatch_RevertsNonOwner() public {
        address[] memory tokens = new address[](1);
        tokens[0] = address(0xAAAA);
        uint256[] memory durations = new uint256[](1);
        durations[0] = 7 days;

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        factory.setDefaultLockDurationsBatch(tokens, durations);
    }

    function testSetDefaultLockDurationsBatch_RevertsLengthMismatch() public {
        address[] memory tokens = new address[](2);
        tokens[0] = address(0xAAAA);
        tokens[1] = address(0xBBBB);
        uint256[] memory durations = new uint256[](1);
        durations[0] = 7 days;

        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCOperatorFactoryErrors.ArrayLengthMismatch.selector, 2, 1));
        factory.setDefaultLockDurationsBatch(tokens, durations);
    }

    function testSetDefaultLockDuration_TracksTokenListWithoutDuplicates() public {
        address token = address(0xABCD);
        vm.startPrank(operatorOwner);
        factory.setDefaultLockDuration(token, 7 days);
        factory.setDefaultLockDuration(token, 14 days);
        vm.stopPrank();

        assertEq(factory.getDefaultLockTokensCount(), 1);
        assertEq(factory.defaultLockTokens(0), token);
        assertEq(factory.defaultLockDuration(token), 14 days);
    }

    function testSetDefaultLockDuration_ZeroDurationRemovesTokenAndCanBeAddedAgain() public {
        address token = address(0xABCD);
        vm.startPrank(operatorOwner);
        factory.setDefaultLockDuration(token, 7 days);
        factory.setDefaultLockDuration(token, 0);
        vm.stopPrank();

        assertEq(factory.defaultLockDuration(token), 0);
        assertEq(factory.getDefaultLockTokensCount(), 0);

        vm.prank(operatorOwner);
        factory.setDefaultLockDuration(token, 30 days);

        assertEq(factory.getDefaultLockTokensCount(), 1);
        assertEq(factory.defaultLockTokens(0), token);
        assertEq(factory.defaultLockDuration(token), 30 days);
    }

    function testSetDefaultLockDurationsBatch_ZeroDurationRemovesAndSkipsTracking() public {
        address tokenA = address(0xAAAA);
        address tokenB = address(0xBBBB);
        address tokenC = address(0xCCCC);

        vm.startPrank(operatorOwner);
        factory.setDefaultLockDuration(tokenA, 7 days);
        factory.setDefaultLockDuration(tokenB, 14 days);

        address[] memory tokens = new address[](2);
        tokens[0] = tokenB;
        tokens[1] = tokenC;
        uint256[] memory durations = new uint256[](2);
        durations[0] = 0;
        durations[1] = 0;
        factory.setDefaultLockDurationsBatch(tokens, durations);
        vm.stopPrank();

        assertEq(factory.defaultLockDuration(tokenA), 7 days);
        assertEq(factory.defaultLockDuration(tokenB), 0);
        assertEq(factory.defaultLockDuration(tokenC), 0);
        assertEq(factory.getDefaultLockTokensCount(), 1);
        assertEq(factory.defaultLockTokens(0), tokenA);
    }

    function testDeployClientVault_AppliesDefaultLockDurations() public {
        address tokenA = address(0xAAAA);
        address tokenB = address(0xBBBB);
        address tokenZero = address(0xCCCC);
        address[] memory tokens = new address[](3);
        tokens[0] = tokenA;
        tokens[1] = tokenB;
        tokens[2] = tokenZero;
        uint256[] memory durations = new uint256[](3);
        durations[0] = 7 days;
        durations[1] = 14 days;
        durations[2] = 0;

        vm.prank(operatorOwner);
        factory.setDefaultLockDurationsBatch(tokens, durations);

        vm.prank(operatorAdmin);
        address vault = factory.deployClientVault(client);
        OTCClientVault deployedVault = OTCClientVault(payable(vault));

        assertEq(factory.getDefaultLockTokensCount(), 2);
        assertEq(factory.defaultLockTokens(0), tokenA);
        assertEq(factory.defaultLockTokens(1), tokenB);
        assertEq(deployedVault.tokenLockUntil(tokenA), block.timestamp + 7 days);
        assertEq(deployedVault.tokenLockUntil(tokenB), block.timestamp + 14 days);
        assertEq(deployedVault.tokenLockUntil(tokenZero), 0);
    }

    function testDeployClientVault_UsesSnapshotOfDefaultLockDurations() public {
        address token = address(0xAAAA);
        vm.prank(operatorOwner);
        factory.setDefaultLockDuration(token, 7 days);

        vm.prank(operatorAdmin);
        address vaultAAddress = factory.deployClientVault(address(0x3001));
        OTCClientVault vaultA = OTCClientVault(payable(vaultAAddress));
        uint256 firstLockUntil = vaultA.tokenLockUntil(token);

        vm.prank(operatorOwner);
        factory.setDefaultLockDuration(token, 30 days);

        vm.prank(operatorAdmin);
        address vaultBAddress = factory.deployClientVault(address(0x3002));
        OTCClientVault vaultB = OTCClientVault(payable(vaultBAddress));

        assertEq(firstLockUntil, block.timestamp + 7 days);
        assertEq(vaultA.tokenLockUntil(token), firstLockUntil);
        assertEq(vaultB.tokenLockUntil(token), block.timestamp + 30 days);
    }

    // ── protocolFeeShareBps & protocolFeeReceiver ────────────────────────────────

    function testConstructor_CachesProtocolFeeShareFromRegistry() public view {
        assertEq(factory.protocolFeeShareBps(), 1_000);
    }

    function testProtocolFeeReceiver_ReadsDynamicallyFromRegistry() public {
        address newReceiver = address(0x9876);
        vm.prank(protocolOwner);
        registry.setProtocolFeeReceiver(newReceiver);
        assertEq(factory.protocolFeeReceiver(), newReceiver);
    }

    // ── setProtocolFeeShareBps (registry push) ──────────────────────────────────

    function _deployHighShareFactory() internal returns (OTCFactoryRegistry r2, OTCOperatorFactory f2) {
        r2 = new OTCFactoryRegistry(protocolOwner, protocolReceiver, 2_500);
        vm.prank(operatorOwner);
        f2 = OTCOperatorFactory(r2.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, defaultConfig));
    }

    function testSetProtocolFeeShareBps_RegistryPushesDirectly() public {
        (OTCFactoryRegistry r2, OTCOperatorFactory f2) = _deployHighShareFactory();
        assertEq(f2.protocolFeeShareBps(), 2_500);

        vm.prank(protocolOwner);
        r2.setFactoryProtocolFeeShareBps(address(f2), 1_000);

        // Factory value updated immediately — no sync call needed
        assertEq(f2.protocolFeeShareBps(), 1_000);
    }

    function testSetProtocolFeeShareBps_EmitsEventOnFactory() public {
        (OTCFactoryRegistry r2, OTCOperatorFactory f2) = _deployHighShareFactory();

        vm.prank(protocolOwner);
        vm.expectEmit(false, false, false, true);
        emit IOTCOperatorFactoryEvents.ProtocolFeeShareSynced(2_500, 1_000);
        r2.setFactoryProtocolFeeShareBps(address(f2), 1_000);
    }

    function testSetProtocolFeeShareBps_RevertsIfNotRegistry() public {
        vm.prank(stranger);
        vm.expectRevert(IOTCOperatorFactoryErrors.NotRegistry.selector);
        factory.setProtocolFeeShareBps(500);
    }

    function testIsDeliveryFeeWaived_IrreversibleOnceSet() public {
        assertFalse(factory.isDeliveryFeeWaived());

        vm.prank(protocolOwner);
        registry.setOperatorDeliveryFeeWaived(address(factory));
        assertTrue(factory.isDeliveryFeeWaived());

        // Calling again is a no-op — cannot un-waive
        vm.prank(protocolOwner);
        registry.setOperatorDeliveryFeeWaived(address(factory));
        assertTrue(factory.isDeliveryFeeWaived());
    }

    function testGetCurrentFeeSnapshot_ReflectsRegistryPushImmediately() public {
        (OTCFactoryRegistry r2, OTCOperatorFactory f2) = _deployHighShareFactory();
        OTCTypes.FeeSnapshot memory snapshot = f2.getCurrentFeeSnapshot();
        assertEq(snapshot.protocolFeeShareBps, 2_500);

        vm.prank(protocolOwner);
        r2.setFactoryProtocolFeeShareBps(address(f2), 1_000);

        snapshot = f2.getCurrentFeeSnapshot();
        assertEq(snapshot.protocolFeeShareBps, 1_000);
    }

    // ── getCurrentFeeSnapshot ────────────────────────────────────────────────────

    function testGetCurrentFeeSnapshot_Values() public view {
        OTCTypes.FeeSnapshot memory snapshot = factory.getCurrentFeeSnapshot();
        assertEq(snapshot.takerFeeBps, 100);
        assertEq(snapshot.deliveryFeeBps, 100);
        assertEq(snapshot.openP2PFeeBps, 50);
        assertEq(snapshot.protocolFeeShareBps, 1_000);
        assertEq(snapshot.operatorFeeReceiver, operatorReceiver);
        assertEq(snapshot.protocolFeeReceiver, protocolReceiver);
    }

    // ── getVaultsCount ───────────────────────────────────────────────────────────

    function testGetVaultsCount_IncreasesOnDeploy() public {
        assertEq(factory.getVaultsCount(), 0);

        vm.prank(operatorAdmin);
        factory.deployClientVault(address(0x3001));
        assertEq(factory.getVaultsCount(), 1);

        vm.prank(operatorAdmin);
        factory.deployClientVault(address(0x3002));
        assertEq(factory.getVaultsCount(), 2);
    }
}
