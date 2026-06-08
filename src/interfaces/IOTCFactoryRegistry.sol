// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice External API of OTCFactoryRegistry.
interface IOTCFactoryRegistry {
    /// @notice Address of OTCClientVault implementation used for clone deployments.
    function clientVaultImplementation() external view returns (address);

    /// @notice Address that receives the protocol portion of operator fees.
    function protocolFeeReceiver() external view returns (address);
    /// @notice Default protocol fee share (bps) assigned to new factories at deployment time.
    /// @dev Existing factories are not affected by changes to this value.
    function defaultProtocolFeeShareBps() external view returns (uint16);
    /// @notice Whether `operatorFactory` is a factory deployed by this registry.
    function isOperatorFactory(address operatorFactory) external view returns (bool);
    /// @notice Whether `vault` is a client vault registered under this registry.
    function isVault(address vault) external view returns (bool);
    /// @notice Whether the protocol share of the delivery fee is waived for `operatorFactory`.
    /// @dev Reads directly from the factory's own storage.
    function isDeliveryFeeWaived(address operatorFactory) external view returns (bool);
    /// @notice Operator factory deployed at index `index`.
    function operatorFactories(uint256 index) external view returns (address);

    /// @notice Deploys a new `OTCOperatorFactory` and registers it in the registry.
    /// @dev Callable by anyone; `msg.sender` must equal `operatorOwner` (self-service onboarding).
    /// @param operatorOwner Owner of the new operator factory; must be `msg.sender`.
    /// @param operatorAdmin Admin of the new operator factory.
    /// @param operatorFeeReceiver Address that receives the operator's fee revenue.
    /// @param defaultFeeConfig Initial fee configuration for the operator.
    /// @return operatorFactory Address of the newly deployed factory.
    function deployOperatorFactory(
        address operatorOwner,
        address operatorAdmin,
        address operatorFeeReceiver,
        OTCTypes.OperatorFeeConfig calldata defaultFeeConfig
    ) external returns (address operatorFactory);

    /// @notice Called by operator factories to register a freshly deployed client vault.
    /// @param vault Address of the vault being registered.
    /// @param client Client who owns the vault.
    function registerVault(address vault, address client) external;

    /// @notice Updates the address that receives the protocol fee.
    /// @param newReceiver New protocol fee receiver; must be non-zero.
    function setProtocolFeeReceiver(address newReceiver) external;

    /// @notice Updates the default protocol fee share used for new factory deployments.
    /// @dev Does not affect existing factories. Must be ≥ MIN_PROTOCOL_FEE_SHARE_BPS (10 %).
    /// @param newShareBps New share in basis points.
    function setDefaultProtocolFeeShareBps(uint16 newShareBps) external;

    /// @notice Permanently waives the protocol share of delivery fees for an operator factory.
    /// @dev Irreversible — once waived, cannot be undone. Taker/openP2P fees are unaffected.
    /// @param operatorFactory Target operator factory.
    function setOperatorDeliveryFeeWaived(address operatorFactory) external;

    /// @notice Decreases the protocol fee share for a specific operator factory.
    /// @dev Cannot increase — only decreases down to MIN_PROTOCOL_FEE_SHARE_BPS (10 %) are allowed.
    /// @param operatorFactory Target operator factory.
    /// @param newShareBps New share in basis points; must be < current value and ≥ 1 000.
    function setFactoryProtocolFeeShareBps(address operatorFactory, uint16 newShareBps) external;

    /// @notice Returns the effective protocol fee share for `operatorFactory`.
    /// @param operatorFactory Target operator factory.
    /// @return Effective protocol fee share in basis points.
    function getProtocolFeeShareBps(address operatorFactory) external view returns (uint16);

    /// @notice Updates the vault implementation address used for all future clone deployments.
    /// @param newImpl New implementation address; must be non-zero.
    function setClientVaultImplementation(address newImpl) external;

    /// @notice Returns the total number of operator factories deployed through this registry.
    function getOperatorFactoriesCount() external view returns (uint256);
}
