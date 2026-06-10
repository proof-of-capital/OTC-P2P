// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OTCTypes} from "./types/OTCTypes.sol";
import {OTCConstants} from "./constants/OTCConstants.sol";
import {IOTCFactoryRegistry} from "./interfaces/IOTCFactoryRegistry.sol";
import {IOTCFactoryRegistryErrors} from "./interfaces/IOTCFactoryRegistryErrors.sol";
import {IOTCFactoryRegistryEvents} from "./interfaces/IOTCFactoryRegistryEvents.sol";
import {OTCOperatorFactory} from "./OTCOperatorFactory.sol";
import {IOTCOperatorFactory} from "./interfaces/IOTCOperatorFactory.sol";
import {OTCClientVault} from "./OTCClientVault.sol";

/// @title OTCFactoryRegistry
/// @notice Central registry that deploys operator factories and manages protocol-level fee settings.
contract OTCFactoryRegistry is Ownable, IOTCFactoryRegistry, IOTCFactoryRegistryErrors, IOTCFactoryRegistryEvents {
    /// @notice Address of OTCClientVault implementation used for clone deployments.
    address public clientVaultImplementation;

    /// @notice Address that receives the protocol portion of operator fees.
    address public protocolFeeReceiver;
    /// @notice Default DeliveryOnly protocol fee share assigned to new factories.
    uint16 public defaultDeliveryOnlyProtocolFeeShareBps;
    /// @notice Default non-DeliveryOnly protocol fee share assigned to new factories.
    uint16 public defaultOtherProtocolFeeShareBps;

    /// @notice Whether `operatorFactory` was deployed by this registry.
    mapping(address operatorFactory => bool) public isOperatorFactory;
    /// @notice Whether `vault` is a client vault registered under this registry.
    mapping(address vault => bool) public isVault;

    /// @notice Ordered list of operator factories deployed through this registry.
    address[] public operatorFactories;

    constructor(
        address initialOwner,
        address initialProtocolFeeReceiver,
        uint16 initialDefaultDeliveryOnlyProtocolFeeShareBps,
        uint16 initialDefaultOtherProtocolFeeShareBps
    ) Ownable(initialOwner) {
        require(initialProtocolFeeReceiver != address(0), InvalidAddress());
        _requireValidProtocolFeeShare(initialDefaultDeliveryOnlyProtocolFeeShareBps);
        _requireValidProtocolFeeShare(initialDefaultOtherProtocolFeeShareBps);

        clientVaultImplementation = address(new OTCClientVault());
        protocolFeeReceiver = initialProtocolFeeReceiver;
        defaultDeliveryOnlyProtocolFeeShareBps = initialDefaultDeliveryOnlyProtocolFeeShareBps;
        defaultOtherProtocolFeeShareBps = initialDefaultOtherProtocolFeeShareBps;
    }

    /// @inheritdoc IOTCFactoryRegistry
    function deployOperatorFactory(
        address operatorOwner,
        address operatorAdmin,
        address operatorFeeReceiver,
        OTCTypes.OperatorFeeConfig calldata defaultFeeConfig
    ) external override returns (address operatorFactory) {
        require(msg.sender == operatorOwner, NotOperatorOwner());
        require(operatorAdmin != address(0), InvalidAddress());
        require(operatorFeeReceiver != address(0), InvalidAddress());
        OTCTypes._requireValidFeeConfig(defaultFeeConfig);

        operatorFactory = address(
            new OTCOperatorFactory(
                address(this),
                operatorOwner,
                operatorAdmin,
                operatorFeeReceiver,
                defaultFeeConfig,
                defaultDeliveryOnlyProtocolFeeShareBps,
                defaultOtherProtocolFeeShareBps
            )
        );
        isOperatorFactory[operatorFactory] = true;
        operatorFactories.push(operatorFactory);

        emit OperatorFactoryDeployed(operatorFactory, operatorOwner, operatorAdmin);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function registerVault(address vault) external override {
        address operatorFactory = msg.sender;
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        require(vault != address(0), InvalidAddress());
        require(!isVault[vault], VaultAlreadyRegistered(vault));

        OTCClientVault vaultContract = OTCClientVault(payable(vault));
        address vaultFactory = vaultContract.factory();
        require(vaultFactory == operatorFactory, VaultFactoryMismatch(vault, operatorFactory, vaultFactory));

        address vaultClient = vaultContract.owner();

        require(OTCOperatorFactory(operatorFactory).isFactoryVault(vault), VaultNotFactoryOwned(operatorFactory, vault));

        isVault[vault] = true;
        emit VaultRegistered(operatorFactory, vault, vaultClient);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setProtocolFeeReceiver(address newReceiver) external override onlyOwner {
        require(newReceiver != address(0), InvalidAddress());
        address previousReceiver = protocolFeeReceiver;
        protocolFeeReceiver = newReceiver;
        emit ProtocolFeeReceiverUpdated(previousReceiver, newReceiver);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setDefaultDeliveryOnlyProtocolFeeShareBps(uint16 newShareBps) external override onlyOwner {
        _requireValidProtocolFeeShare(newShareBps);
        uint16 previousShareBps = defaultDeliveryOnlyProtocolFeeShareBps;
        defaultDeliveryOnlyProtocolFeeShareBps = newShareBps;
        emit DefaultDeliveryOnlyProtocolFeeShareUpdated(previousShareBps, newShareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setDefaultOtherProtocolFeeShareBps(uint16 newShareBps) external override onlyOwner {
        _requireValidProtocolFeeShare(newShareBps);
        uint16 previousShareBps = defaultOtherProtocolFeeShareBps;
        defaultOtherProtocolFeeShareBps = newShareBps;
        emit DefaultOtherProtocolFeeShareUpdated(previousShareBps, newShareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function isDeliveryFeeWaived(address operatorFactory) external view override returns (bool) {
        return IOTCOperatorFactory(operatorFactory).isDeliveryFeeWaived();
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setOperatorDeliveryFeeWaived(address operatorFactory) external override onlyOwner {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        IOTCOperatorFactory(operatorFactory).setDeliveryFeeWaived();
        emit OperatorDeliveryFeeWaived(operatorFactory);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setFactoryDeliveryOnlyProtocolFeeShareBps(address operatorFactory, uint16 newShareBps)
        external
        override
        onlyOwner
    {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        IOTCOperatorFactory factory = IOTCOperatorFactory(operatorFactory);
        uint16 current = factory.deliveryOnlyProtocolFeeShareBps();
        _requireProtocolFeeShareDecrease(current, newShareBps);
        factory.setDeliveryOnlyProtocolFeeShareBps(newShareBps);
        emit FactoryDeliveryOnlyProtocolFeeShareDecreased(operatorFactory, current, newShareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setFactoryOtherProtocolFeeShareBps(address operatorFactory, uint16 newShareBps)
        external
        override
        onlyOwner
    {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        IOTCOperatorFactory factory = IOTCOperatorFactory(operatorFactory);
        uint16 current = factory.otherProtocolFeeShareBps();
        _requireProtocolFeeShareDecrease(current, newShareBps);
        factory.setOtherProtocolFeeShareBps(newShareBps);
        emit FactoryOtherProtocolFeeShareDecreased(operatorFactory, current, newShareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function getDeliveryOnlyProtocolFeeShareBps(address operatorFactory) external view override returns (uint16) {
        return IOTCOperatorFactory(operatorFactory).deliveryOnlyProtocolFeeShareBps();
    }

    /// @inheritdoc IOTCFactoryRegistry
    function getOtherProtocolFeeShareBps(address operatorFactory) external view override returns (uint16) {
        return IOTCOperatorFactory(operatorFactory).otherProtocolFeeShareBps();
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setClientVaultImplementation(address newImpl) external override onlyOwner {
        require(newImpl != address(0), InvalidAddress());
        address previousImpl = clientVaultImplementation;
        clientVaultImplementation = newImpl;
        emit ClientVaultImplementationUpdated(previousImpl, newImpl);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function getOperatorFactoriesCount() external view override returns (uint256) {
        return operatorFactories.length;
    }

    function _requireValidProtocolFeeShare(uint16 shareBps) internal pure {
        require(shareBps <= OTCConstants.MAX_FEE_BPS, ProtocolFeeShareTooLarge(shareBps, OTCConstants.MAX_FEE_BPS));
        require(
            shareBps >= OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS,
            ProtocolFeeShareTooLow(shareBps, OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS)
        );
    }

    function _requireProtocolFeeShareDecrease(uint16 currentShareBps, uint16 newShareBps) internal pure {
        require(newShareBps < currentShareBps, ProtocolFeeCannotIncrease(newShareBps, currentShareBps));
        require(
            newShareBps >= OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS,
            ProtocolFeeShareTooLow(newShareBps, OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS)
        );
    }
}
