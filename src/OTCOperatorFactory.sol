// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Clones} from "@openzeppelin/contracts/proxy/Clones.sol";
import {OTCTypes} from "./types/OTCTypes.sol";
import {OTCConstants} from "./constants/OTCConstants.sol";
import {IOTCOperatorFactory} from "./interfaces/IOTCOperatorFactory.sol";
import {IOTCOperatorFactoryErrors} from "./interfaces/IOTCOperatorFactoryErrors.sol";
import {IOTCOperatorFactoryEvents} from "./interfaces/IOTCOperatorFactoryEvents.sol";
import {IOTCFactoryRegistry} from "./interfaces/IOTCFactoryRegistry.sol";
import {OTCClientVault} from "./OTCClientVault.sol";

/// @title OTCOperatorFactory
/// @notice Deploys and manages client vaults for a single OTC operator; holds operator-level fee and governance settings.
contract OTCOperatorFactory is Ownable, IOTCOperatorFactory, IOTCOperatorFactoryErrors, IOTCOperatorFactoryEvents {
    /// @notice Immutable registry this factory is registered in.
    address public immutable registry;

    /// @notice Factory admin allowed to propose transactions in client vaults.
    address public admin;
    /// @notice Address that receives the operator's net fee revenue.
    address public operatorFeeReceiver;

    /// @notice Default fee configuration applied to all new client vaults.
    OTCTypes.OperatorFeeConfig public defaultFeeConfig;

    /// @notice Protocol fee share used while a vault is in DeliveryOnly mode.
    uint16 public override deliveryOnlyProtocolFeeShareBps;
    /// @notice Protocol fee share used while a vault is in any non-DeliveryOnly mode.
    uint16 public override otherProtocolFeeShareBps;
    /// @notice Whether the protocol share of the delivery fee is waived. Set by the registry.
    bool public deliveryFeeWaived;

    /// @notice Default lock duration in seconds for each token address.
    mapping(address token => uint256 duration) public defaultLockDuration;
    /// @notice Ordered list of tokens that currently have a non-zero default lock configured.
    address[] public defaultLockTokens;
    /// @notice Reverse index for `defaultLockTokens` using one-based indexing (`0` means absent).
    mapping(address token => uint256 indexPlusOne) private defaultLockTokenIndexPlusOne;
    /// @notice Whether `vault` was deployed by this factory.
    mapping(address vault => bool) public isFactoryVault;

    /// @notice Ordered list of client vaults deployed by this factory.
    address[] public vaults;

    modifier onlyRegistry() {
        require(msg.sender == registry, NotRegistry());
        _;
    }

    constructor(
        address registry_,
        address owner_,
        address admin_,
        address operatorFeeReceiver_,
        OTCTypes.OperatorFeeConfig memory defaultFeeConfig_,
        uint16 initialDeliveryOnlyProtocolFeeShareBps_,
        uint16 initialOtherProtocolFeeShareBps_
    ) Ownable(owner_) {
        require(msg.sender == registry_, NotRegistry());
        require(admin_ != address(0), InvalidAddress());
        require(operatorFeeReceiver_ != address(0), InvalidAddress());
        OTCTypes._requireValidFeeConfig(defaultFeeConfig_);

        registry = registry_;
        admin = admin_;
        operatorFeeReceiver = operatorFeeReceiver_;
        defaultFeeConfig = defaultFeeConfig_;
        // Passed by the registry at deployment time so the value is consistent with registry storage.
        deliveryOnlyProtocolFeeShareBps = initialDeliveryOnlyProtocolFeeShareBps_;
        otherProtocolFeeShareBps = initialOtherProtocolFeeShareBps_;
    }

    /// @inheritdoc IOTCOperatorFactory
    function deployClientVault(address client) external override returns (address vault) {
        require(client != address(0), InvalidAddress());

        uint256 n = defaultLockTokens.length;
        OTCTypes.DefaultLockConfig[] memory defaultLocks = new OTCTypes.DefaultLockConfig[](n);
        for (uint256 i = 0; i < n;) {
            address token = defaultLockTokens[i];
            defaultLocks[i] = OTCTypes.DefaultLockConfig({token: token, duration: defaultLockDuration[token]});
            unchecked {
                ++i;
            }
        }

        vault = Clones.clone(IOTCFactoryRegistry(registry).clientVaultImplementation());
        OTCClientVault(payable(vault)).initialize(address(this), client, defaultLocks);
        isFactoryVault[vault] = true;
        vaults.push(vault);

        IOTCFactoryRegistry(registry).registerVault(vault);
        emit ClientVaultDeployed(client, vault);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setAdmin(address newAdmin) external override onlyOwner {
        require(newAdmin != address(0), InvalidAddress());
        address previousAdmin = admin;
        admin = newAdmin;
        emit AdminUpdated(previousAdmin, newAdmin);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setOperatorFeeReceiver(address newReceiver) external override onlyOwner {
        require(newReceiver != address(0), InvalidAddress());
        address previousReceiver = operatorFeeReceiver;
        operatorFeeReceiver = newReceiver;
        emit OperatorFeeReceiverUpdated(previousReceiver, newReceiver);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setDefaultFeeConfig(OTCTypes.OperatorFeeConfig calldata newConfig) external override onlyOwner {
        OTCTypes._requireValidFeeConfig(newConfig);
        defaultFeeConfig = newConfig;
        emit DefaultFeeConfigUpdated(newConfig.takerFeeBps, newConfig.deliveryFeeBps, newConfig.openP2PFeeBps);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setDefaultLockDuration(address token, uint256 duration) external override onlyOwner {
        _setDefaultLockDuration(token, duration);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setDefaultLockDurationsBatch(address[] calldata tokens, uint256[] calldata durations)
        external
        override
        onlyOwner
    {
        uint256 n = tokens.length;
        require(n == durations.length, ArrayLengthMismatch(n, durations.length));
        for (uint256 i = 0; i < n;) {
            _setDefaultLockDuration(tokens[i], durations[i]);
            unchecked {
                ++i;
            }
        }
    }

    /// @inheritdoc IOTCOperatorFactory
    function protocolFeeReceiver() external view override returns (address) {
        return IOTCFactoryRegistry(registry).protocolFeeReceiver();
    }

    /// @inheritdoc IOTCOperatorFactory
    function isDeliveryFeeWaived() external view override returns (bool) {
        return deliveryFeeWaived;
    }

    /// @inheritdoc IOTCOperatorFactory
    function setDeliveryOnlyProtocolFeeShareBps(uint16 newShareBps) external override onlyRegistry {
        uint16 prev = deliveryOnlyProtocolFeeShareBps;
        deliveryOnlyProtocolFeeShareBps = newShareBps;
        emit DeliveryOnlyProtocolFeeShareSynced(prev, newShareBps);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setOtherProtocolFeeShareBps(uint16 newShareBps) external override onlyRegistry {
        uint16 prev = otherProtocolFeeShareBps;
        otherProtocolFeeShareBps = newShareBps;
        emit OtherProtocolFeeShareSynced(prev, newShareBps);
    }

    /// @inheritdoc IOTCOperatorFactory
    function setDeliveryFeeWaived() external override onlyRegistry {
        deliveryFeeWaived = true;
        emit DeliveryFeeWaived();
    }

    /// @inheritdoc IOTCOperatorFactory
    function getCurrentFeeSnapshot() external view override returns (OTCTypes.FeeSnapshot memory snapshot) {
        OTCTypes.OperatorFeeConfig memory config = defaultFeeConfig;
        snapshot = OTCTypes.FeeSnapshot({
            takerFeeBps: config.takerFeeBps,
            deliveryFeeBps: config.deliveryFeeBps,
            openP2PFeeBps: config.openP2PFeeBps,
            operatorFeeReceiver: operatorFeeReceiver,
            protocolFeeReceiver: IOTCFactoryRegistry(registry).protocolFeeReceiver()
        });
    }

    /// @inheritdoc IOTCOperatorFactory
    function getVaultsCount() external view override returns (uint256) {
        return vaults.length;
    }

    /// @inheritdoc IOTCOperatorFactory
    function getDefaultLockTokensCount() external view override returns (uint256) {
        return defaultLockTokens.length;
    }

    function _setDefaultLockDuration(address token, uint256 duration) internal {
        require(token != address(0), InvalidAddress());
        require(
            duration <= OTCConstants.MAX_LOCK_DURATION, LockDurationTooLarge(duration, OTCConstants.MAX_LOCK_DURATION)
        );
        if (duration == 0) {
            if (defaultLockDuration[token] != 0) {
                _removeDefaultLockToken(token);
            }
            defaultLockDuration[token] = 0;
            emit DefaultLockDurationUpdated(token, duration);
            return;
        }

        if (defaultLockDuration[token] == 0) {
            defaultLockTokens.push(token);
            defaultLockTokenIndexPlusOne[token] = defaultLockTokens.length;
        }
        defaultLockDuration[token] = duration;
        emit DefaultLockDurationUpdated(token, duration);
    }

    function _removeDefaultLockToken(address token) internal {
        uint256 indexPlusOne = defaultLockTokenIndexPlusOne[token];
        uint256 index = indexPlusOne - 1;
        uint256 lastIndex = defaultLockTokens.length - 1;
        if (index != lastIndex) {
            address lastToken = defaultLockTokens[lastIndex];
            defaultLockTokens[index] = lastToken;
            defaultLockTokenIndexPlusOne[lastToken] = indexPlusOne;
        }

        defaultLockTokens.pop();
        delete defaultLockTokenIndexPlusOne[token];
    }
}
