// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {OTCTypes} from "./types/OTCTypes.sol";
import {OTCConstants} from "./constants/OTCConstants.sol";
import {IOTCFactoryRegistry} from "./interfaces/IOTCFactoryRegistry.sol";
import {IOTCFactoryRegistryErrors} from "./interfaces/IOTCFactoryRegistryErrors.sol";
import {IOTCFactoryRegistryEvents} from "./interfaces/IOTCFactoryRegistryEvents.sol";
import {OTCOperatorFactory} from "./OTCOperatorFactory.sol";
import {OTCClientVault} from "./OTCClientVault.sol";

/// @title OTCFactoryRegistry
/// @notice Central registry that deploys operator factories and manages protocol-level fee settings.
contract OTCFactoryRegistry is Ownable, IOTCFactoryRegistry, IOTCFactoryRegistryErrors, IOTCFactoryRegistryEvents {
    /// @notice Address of OTCClientVault implementation used for clone deployments.
    address public immutable clientVaultImplementation;

    /// @notice Address that receives the protocol portion of operator fees.
    address public protocolFeeReceiver;
    /// @notice Default protocol fee share in basis points applied when no per-operator override exists.
    uint16 public defaultProtocolFeeShareBps;

    /// @notice Whether `operatorFactory` was deployed by this registry.
    mapping(address operatorFactory => bool) public isOperatorFactory;
    /// @notice Whether `vault` is a client vault registered under this registry.
    mapping(address vault => bool) public isVault;
    /// @notice Whether the protocol fee is waived for `operatorFactory`.
    mapping(address operatorFactory => bool) public isProtocolFeeWaived;
    /// @notice Custom protocol fee share override for `operatorFactory` in basis points.
    mapping(address operatorFactory => uint16) public customProtocolFeeShareBps;
    /// @notice Whether `operatorFactory` has a custom protocol fee share set.
    mapping(address operatorFactory => bool) public hasCustomProtocolFeeShare;

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
        require(operatorOwner != address(0), InvalidAddress());
        require(msg.sender == operatorOwner, NotOperatorOwner());
        require(operatorAdmin != address(0), InvalidAddress());
        require(operatorFeeReceiver != address(0), InvalidAddress());
        _requireValidFeeConfig(defaultFeeConfig);

        operatorFactory = address(
            new OTCOperatorFactory(address(this), operatorOwner, operatorAdmin, operatorFeeReceiver, defaultFeeConfig)
        );
        isOperatorFactory[operatorFactory] = true;
        operatorFactories.push(operatorFactory);

        emit OperatorFactoryDeployed(operatorFactory, operatorOwner, operatorAdmin);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function registerVault(address vault, address client) external override {
        address operatorFactory = msg.sender;
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        require(vault != address(0), InvalidAddress());
        require(client != address(0), InvalidAddress());
        require(!isVault[vault], VaultAlreadyRegistered(vault));

        OTCClientVault vaultContract = OTCClientVault(payable(vault));
        address vaultFactory = vaultContract.factory();
        require(vaultFactory == operatorFactory, VaultFactoryMismatch(vault, operatorFactory, vaultFactory));

        address vaultClient = vaultContract.owner();
        require(vaultClient == client, VaultClientMismatch(vault, client, vaultClient));

        require(OTCOperatorFactory(operatorFactory).isFactoryVault(vault), VaultNotFactoryOwned(operatorFactory, vault));

        isVault[vault] = true;
        emit VaultRegistered(operatorFactory, vault, client);
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
        uint16 previousShareBps = defaultProtocolFeeShareBps;
        defaultProtocolFeeShareBps = newShareBps;
        emit DefaultProtocolFeeShareUpdated(previousShareBps, newShareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setOperatorProtocolFeeWaived(address operatorFactory, bool waived) external override onlyOwner {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        isProtocolFeeWaived[operatorFactory] = waived;
        emit OperatorProtocolFeeWaived(operatorFactory, waived);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function setCustomProtocolFeeShareBps(address operatorFactory, uint16 shareBps) external override onlyOwner {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        require(shareBps <= OTCConstants.MAX_FEE_BPS, ProtocolFeeShareTooLarge(shareBps, OTCConstants.MAX_FEE_BPS));

        customProtocolFeeShareBps[operatorFactory] = shareBps;
        hasCustomProtocolFeeShare[operatorFactory] = true;
        emit CustomProtocolFeeShareUpdated(operatorFactory, shareBps);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function clearCustomProtocolFeeShareBps(address operatorFactory) external override onlyOwner {
        require(isOperatorFactory[operatorFactory], NotOperatorFactory());
        delete customProtocolFeeShareBps[operatorFactory];
        delete hasCustomProtocolFeeShare[operatorFactory];
        emit CustomProtocolFeeShareCleared(operatorFactory);
    }

    /// @inheritdoc IOTCFactoryRegistry
    function getProtocolFeeShareBps(address operatorFactory) external view override returns (uint16) {
        if (isProtocolFeeWaived[operatorFactory]) return 0;
        if (hasCustomProtocolFeeShare[operatorFactory]) return customProtocolFeeShareBps[operatorFactory];
        return defaultProtocolFeeShareBps;
    }

    /// @inheritdoc IOTCFactoryRegistry
    function getOperatorFactoriesCount() external view override returns (uint256) {
        return operatorFactories.length;
    }

    function _requireValidFeeConfig(OTCTypes.OperatorFeeConfig calldata config) internal pure {
        require(
            config.takerFeeBps <= OTCConstants.MAX_FEE_BPS, FeeBpsTooLarge(config.takerFeeBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            config.deliveryFeeBps <= OTCConstants.MAX_FEE_BPS,
            FeeBpsTooLarge(config.deliveryFeeBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            config.openP2PFeeBps <= OTCConstants.MAX_FEE_BPS,
            FeeBpsTooLarge(config.openP2PFeeBps, OTCConstants.MAX_FEE_BPS)
        );
    }
}
