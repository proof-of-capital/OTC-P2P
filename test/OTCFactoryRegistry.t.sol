// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {Initializable} from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import {IOTCFactoryRegistryErrors} from "../src/interfaces/IOTCFactoryRegistryErrors.sol";
import {IOTCFactoryRegistryEvents} from "../src/interfaces/IOTCFactoryRegistryEvents.sol";

contract MockRegistryVault {
    address public factory;
    address private _owner;

    constructor(address factory_, address owner_) {
        factory = factory_;
        _owner = owner_;
    }

    function owner() external view returns (address) {
        return _owner;
    }
}

contract MockRegistryOperatorFactory {
    mapping(address vault => bool) public ownedVaults;

    function setOwnedVault(address vault, bool owned) external {
        ownedVaults[vault] = owned;
    }

    function isFactoryVault(address vault) external view returns (bool) {
        return ownedVaults[vault];
    }
}

contract OTCFactoryRegistryTest is Test {
    address protocolOwner = address(0x1001);
    address protocolReceiver = address(0x1002);
    address operatorOwner = address(0x2001);
    address operatorAdmin = address(0x2002);
    address operatorReceiver = address(0x2003);
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
        assertEq(registry.owner(), protocolOwner);
        assertEq(registry.protocolFeeReceiver(), protocolReceiver);
        assertEq(registry.defaultProtocolFeeShareBps(), 1_000);
        assertTrue(registry.clientVaultImplementation() != address(0));
    }

    function testConstructor_DeploysClientVaultImplementation() public view {
        address implementation = registry.clientVaultImplementation();
        assertGt(implementation.code.length, 0);
    }

    function testConstructor_RevertsZeroOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableInvalidOwner.selector, address(0)));
        new OTCFactoryRegistry(address(0), protocolReceiver, 1_000);
    }

    function testConstructor_RevertsZeroReceiver() public {
        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        new OTCFactoryRegistry(protocolOwner, address(0), 1_000);
    }

    function testConstructor_RevertsFeeTooLarge() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.ProtocolFeeShareTooLarge.selector, 10_001, 10_000)
        );
        new OTCFactoryRegistry(protocolOwner, protocolReceiver, 10_001);
    }

    // ── deployOperatorFactory ────────────────────────────────────────────────────

    function testDeployOperatorFactory_TracksFactory() public {
        assertTrue(registry.isOperatorFactory(address(factory)));
        assertEq(registry.getOperatorFactoriesCount(), 1);
        assertEq(registry.operatorFactories(0), address(factory));
    }

    function testDeployOperatorFactory_EmitsEvent() public {
        address newOperatorOwner = address(0x7777);
        vm.prank(newOperatorOwner);
        vm.recordLogs();
        address newFactory =
            registry.deployOperatorFactory(newOperatorOwner, operatorAdmin, operatorReceiver, defaultConfig);
        assertTrue(registry.isOperatorFactory(newFactory));
        assertEq(registry.getOperatorFactoriesCount(), 2);
    }

    function testDeployOperatorFactory_RevertsWhenCallerIsNotOperatorOwner() public {
        vm.expectRevert(IOTCFactoryRegistryErrors.NotOperatorOwner.selector);
        vm.prank(stranger);
        registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, defaultConfig);
    }

    function testDeployOperatorFactory_SelfServiceByStranger() public {
        address newOperatorOwner = address(0x7777);
        vm.prank(newOperatorOwner);
        address newFactory =
            registry.deployOperatorFactory(newOperatorOwner, newOperatorOwner, newOperatorOwner, defaultConfig);
        assertTrue(registry.isOperatorFactory(newFactory));
        assertEq(OTCOperatorFactory(newFactory).owner(), newOperatorOwner);
    }

    function testDeployOperatorFactory_RevertsZeroOperatorOwner() public {
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        registry.deployOperatorFactory(address(0), operatorAdmin, operatorReceiver, defaultConfig);
    }

    function testDeployOperatorFactory_RevertsZeroOperatorAdmin() public {
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        registry.deployOperatorFactory(operatorOwner, address(0), operatorReceiver, defaultConfig);
    }

    function testDeployOperatorFactory_RevertsZeroFeeReceiver() public {
        vm.prank(operatorOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        registry.deployOperatorFactory(operatorOwner, operatorAdmin, address(0), defaultConfig);
    }

    function testDeployOperatorFactory_RevertsInvalidTakerFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 10_001, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, bad);
    }

    function testDeployOperatorFactory_RevertsInvalidDeliveryFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 10_001, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, bad);
    }

    function testDeployOperatorFactory_RevertsInvalidOpenP2PFee() public {
        OTCTypes.OperatorFeeConfig memory bad =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 10_001});
        vm.prank(operatorOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.FeeBpsTooLarge.selector, 10_001, 10_000));
        registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, bad);
    }

    // ── registerVault ────────────────────────────────────────────────────────────

    function testRegisterVault_RevertsForNonFactory() public {
        vm.expectRevert(IOTCFactoryRegistryErrors.NotOperatorFactory.selector);
        vm.prank(stranger);
        registry.registerVault(address(0x1234), address(0x5678));
    }

    function testRegisterVault_TracksVault() public {
        vm.prank(operatorAdmin);
        address vault = factory.deployClientVault(address(0x3001));
        assertTrue(registry.isVault(vault));
    }

    function testRegisterVault_RevertsVaultAlreadyRegistered() public {
        MockRegistryOperatorFactory mockFactory = new MockRegistryOperatorFactory();
        _markAsOperatorFactory(address(mockFactory));

        address client = address(0x3001);
        MockRegistryVault mockVault = new MockRegistryVault(address(mockFactory), client);
        mockFactory.setOwnedVault(address(mockVault), true);

        vm.prank(address(mockFactory));
        registry.registerVault(address(mockVault), client);

        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.VaultAlreadyRegistered.selector, address(mockVault))
        );
        vm.prank(address(mockFactory));
        registry.registerVault(address(mockVault), client);
    }

    function testRegisterVault_RevertsVaultFactoryMismatch() public {
        MockRegistryOperatorFactory mockFactory = new MockRegistryOperatorFactory();
        _markAsOperatorFactory(address(mockFactory));

        MockRegistryVault mockVault = new MockRegistryVault(stranger, address(0x3001));
        mockFactory.setOwnedVault(address(mockVault), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCFactoryRegistryErrors.VaultFactoryMismatch.selector,
                address(mockVault),
                address(mockFactory),
                stranger
            )
        );
        vm.prank(address(mockFactory));
        registry.registerVault(address(mockVault), address(0x3001));
    }

    function testRegisterVault_RevertsVaultClientMismatch() public {
        MockRegistryOperatorFactory mockFactory = new MockRegistryOperatorFactory();
        _markAsOperatorFactory(address(mockFactory));

        address expectedClient = address(0x3001);
        address actualClient = address(0x3002);
        MockRegistryVault mockVault = new MockRegistryVault(address(mockFactory), actualClient);
        mockFactory.setOwnedVault(address(mockVault), true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCFactoryRegistryErrors.VaultClientMismatch.selector, address(mockVault), expectedClient, actualClient
            )
        );
        vm.prank(address(mockFactory));
        registry.registerVault(address(mockVault), expectedClient);
    }

    function testRegisterVault_RevertsVaultNotFactoryOwned() public {
        MockRegistryOperatorFactory mockFactory = new MockRegistryOperatorFactory();
        _markAsOperatorFactory(address(mockFactory));

        address client = address(0x3001);
        MockRegistryVault mockVault = new MockRegistryVault(address(mockFactory), client);
        mockFactory.setOwnedVault(address(mockVault), false);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOTCFactoryRegistryErrors.VaultNotFactoryOwned.selector, address(mockFactory), address(mockVault)
            )
        );
        vm.prank(address(mockFactory));
        registry.registerVault(address(mockVault), client);
    }

    function testClientVaultImplementation_RevertsInitializeCall() public {
        OTCTypes.DefaultLockConfig[] memory defaultLocks = new OTCTypes.DefaultLockConfig[](0);
        address implementation = registry.clientVaultImplementation();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        OTCClientVault(payable(implementation)).initialize(address(factory), address(0x3001), defaultLocks);
    }

    // ── setProtocolFeeReceiver ───────────────────────────────────────────────────

    function testSetProtocolFeeReceiver_Updates() public {
        address newReceiver = address(0x8888);
        vm.prank(protocolOwner);
        vm.expectEmit(true, true, false, false);
        emit IOTCFactoryRegistryEvents.ProtocolFeeReceiverUpdated(protocolReceiver, newReceiver);
        registry.setProtocolFeeReceiver(newReceiver);
        assertEq(registry.protocolFeeReceiver(), newReceiver);
    }

    function testSetProtocolFeeReceiver_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        registry.setProtocolFeeReceiver(address(0x8888));
    }

    function testSetProtocolFeeReceiver_RevertsZero() public {
        vm.prank(protocolOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        registry.setProtocolFeeReceiver(address(0));
    }

    // ── setDefaultProtocolFeeShareBps ────────────────────────────────────────────

    function testSetDefaultProtocolFeeShareBps_Updates() public {
        vm.prank(protocolOwner);
        vm.expectEmit(false, false, false, true);
        emit IOTCFactoryRegistryEvents.DefaultProtocolFeeShareUpdated(1_000, 2_000);
        registry.setDefaultProtocolFeeShareBps(2_000);
        assertEq(registry.defaultProtocolFeeShareBps(), 2_000);
    }

    function testSetDefaultProtocolFeeShareBps_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        registry.setDefaultProtocolFeeShareBps(2_000);
    }

    function testSetDefaultProtocolFeeShareBps_RevertsTooLarge() public {
        vm.prank(protocolOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.ProtocolFeeShareTooLarge.selector, 10_001, 10_000)
        );
        registry.setDefaultProtocolFeeShareBps(10_001);
    }

    // ── setOperatorProtocolFeeWaived ─────────────────────────────────────────────

    function testSetOperatorProtocolFeeWaived_Sets() public {
        vm.prank(protocolOwner);
        registry.setOperatorProtocolFeeWaived(address(factory), true);
        assertTrue(registry.isProtocolFeeWaived(address(factory)));

        vm.prank(protocolOwner);
        registry.setOperatorProtocolFeeWaived(address(factory), false);
        assertFalse(registry.isProtocolFeeWaived(address(factory)));
    }

    function testSetOperatorProtocolFeeWaived_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        registry.setOperatorProtocolFeeWaived(address(factory), true);
    }

    function testSetOperatorProtocolFeeWaived_RevertsNotFactory() public {
        vm.prank(protocolOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.NotOperatorFactory.selector);
        registry.setOperatorProtocolFeeWaived(address(0x1234), true);
    }

    // ── setCustomProtocolFeeShareBps ─────────────────────────────────────────────

    function testSetCustomProtocolFeeShareBps_Updates() public {
        vm.prank(protocolOwner);
        vm.expectEmit(true, false, false, true);
        emit IOTCFactoryRegistryEvents.CustomProtocolFeeShareUpdated(address(factory), 2_500);
        registry.setCustomProtocolFeeShareBps(address(factory), 2_500);

        assertEq(registry.customProtocolFeeShareBps(address(factory)), 2_500);
        assertTrue(registry.hasCustomProtocolFeeShare(address(factory)));
    }

    function testSetCustomProtocolFeeShareBps_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        registry.setCustomProtocolFeeShareBps(address(factory), 2_500);
    }

    function testSetCustomProtocolFeeShareBps_RevertsNotFactory() public {
        vm.prank(protocolOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.NotOperatorFactory.selector);
        registry.setCustomProtocolFeeShareBps(address(0x1234), 2_500);
    }

    function testSetCustomProtocolFeeShareBps_RevertsTooLarge() public {
        vm.prank(protocolOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.ProtocolFeeShareTooLarge.selector, 10_001, 10_000)
        );
        registry.setCustomProtocolFeeShareBps(address(factory), 10_001);
    }

    // ── clearCustomProtocolFeeShareBps ───────────────────────────────────────────

    function testClearCustomProtocolFeeShareBps_Clears() public {
        vm.startPrank(protocolOwner);
        registry.setCustomProtocolFeeShareBps(address(factory), 2_500);

        vm.expectEmit(true, false, false, false);
        emit IOTCFactoryRegistryEvents.CustomProtocolFeeShareCleared(address(factory));
        registry.clearCustomProtocolFeeShareBps(address(factory));
        vm.stopPrank();

        assertFalse(registry.hasCustomProtocolFeeShare(address(factory)));
        assertEq(registry.customProtocolFeeShareBps(address(factory)), 0);
    }

    function testClearCustomProtocolFeeShareBps_RevertsNonOwner() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        registry.clearCustomProtocolFeeShareBps(address(factory));
    }

    function testClearCustomProtocolFeeShareBps_RevertsNotFactory() public {
        vm.prank(protocolOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.NotOperatorFactory.selector);
        registry.clearCustomProtocolFeeShareBps(address(0x1234));
    }

    // ── getProtocolFeeShareBps priority ──────────────────────────────────────────

    function testGetProtocolFeeShareBps_PriorityOrder() public {
        // default
        assertEq(registry.getProtocolFeeShareBps(address(factory)), 1_000);

        // custom overrides default
        vm.prank(protocolOwner);
        registry.setCustomProtocolFeeShareBps(address(factory), 2_500);
        assertEq(registry.getProtocolFeeShareBps(address(factory)), 2_500);

        // waived beats custom
        vm.prank(protocolOwner);
        registry.setOperatorProtocolFeeWaived(address(factory), true);
        assertEq(registry.getProtocolFeeShareBps(address(factory)), 0);

        // un-waiving falls back to custom
        vm.prank(protocolOwner);
        registry.setOperatorProtocolFeeWaived(address(factory), false);
        assertEq(registry.getProtocolFeeShareBps(address(factory)), 2_500);

        // clearing custom falls back to default
        vm.prank(protocolOwner);
        registry.clearCustomProtocolFeeShareBps(address(factory));
        assertEq(registry.getProtocolFeeShareBps(address(factory)), 1_000);
    }

    // ── setClientVaultImplementation ─────────────────────────────────────────────

    function testSetClientVaultImplementation_Updates() public {
        address newImpl = address(new OTCClientVault());
        address previousImpl = registry.clientVaultImplementation();
        vm.prank(protocolOwner);
        vm.expectEmit(true, true, false, false);
        emit IOTCFactoryRegistryEvents.ClientVaultImplementationUpdated(previousImpl, newImpl);
        registry.setClientVaultImplementation(newImpl);
        assertEq(registry.clientVaultImplementation(), newImpl);
    }

    function testSetClientVaultImplementation_RevertsNonOwner() public {
        address newImpl = address(new OTCClientVault());
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        vm.prank(stranger);
        registry.setClientVaultImplementation(newImpl);
    }

    function testSetClientVaultImplementation_RevertsZeroAddress() public {
        vm.prank(protocolOwner);
        vm.expectRevert(IOTCFactoryRegistryErrors.InvalidAddress.selector);
        registry.setClientVaultImplementation(address(0));
    }

    function _markAsOperatorFactory(address operatorFactory) internal {
        vm.store(address(registry), keccak256(abi.encode(operatorFactory, uint256(3))), bytes32(uint256(1)));
    }
}
