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
    /// @notice Default protocol fee share (bps) assigned to new factories at deployment time.
    /// @dev Changing this does not affect existing factories. Min MIN_PROTOCOL_FEE_SHARE_BPS.
    uint16 public defaultProtocolFeeShareBps;

    /// @notice Whether `operatorFactory` was deployed by this registry.
    mapping(address operatorFactory => bool) public isOperatorFactory;
    /// @notice Whether `vault` is a client vault registered under this registry.
    mapping(address vault => bool) public isVault;

    /// @notice Ordered list of operator factories deployed through this registry.
    address[] public operatorFactories;

    constructor(address initialOwner, address initialProtocolFeeReceiver, uint16 initialDefaultProtocolFeeShareBps)
        Ownable(initialOwner)
    {
        require(initialProtocolFeeReceiver != address(0), InvalidAddress());
        require(
            initialDefaultProtocolFeeShareBps <= OTCConstants.MAX_FEE_BPS,
            ProtocolFeeShareTooLarge(initialDefaultProtocolFeeShareBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            initialDefaultProtocolFeeShareBps >= OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS,
            ProtocolFeeShareTooLow(initialDefaultProtocolFeeShareBps, OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS)
        );

        clientVaultImplementation = address(new OTCClientVault());
        protocolFeeReceiver = initialProtocolFeeReceiver;
        defaultProtocolFeeShareBps = initialDefaultProtocolFeeShareBps;
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
                defaultProtocolFeeShareBps
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
    function setDefaultProtocolFeeShareBps(uint16 newShareBps) external override onlyOwner {
        require(
            newShareBps <= OTCConstants.MAX_FEE_BPS, ProtocolFeeShareTooLarge(newShareBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            newShareBps >= OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS,
            ProtocolFeeShareTooLow(newShareBps, OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS)
        );
        uint16 previousShareBps = defaultProtocolFeeShareBps;
        defaultProtocolFeeShareBps = newShareBps;
        emit DefaultProtocolFeeShareUpdated(previousShareBps, newShareBps);
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
    function setFactoryProtocolFeeShareBps(address operatorFactory, uint16 newShareBps) external override onlyOwner {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        uint16 current = IOTCOperatorFactory(operatorFactory).protocolFeeShareBps();
        require(newShareBps < current, ProtocolFeeCannotIncrease(newShareBps, current));
        require(
            newShareBps >= OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS,
            ProtocolFeeShareTooLow(newShareBps, OTCConstants.MIN_PROTOCOL_FEE_SHARE_BPS)
        );
        IOTCOperatorFactory(operatorFactory).setProtocolFeeShareBps(newShareBps);
        emit FactoryProtocolFeeShareDecreased(operatorFactory, current, newShareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function getProtocolFeeShareBps(address operatorFactory) external view override returns (uint16) {
        return IOTCOperatorFactory(operatorFactory).protocolFeeShareBps();
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
}
