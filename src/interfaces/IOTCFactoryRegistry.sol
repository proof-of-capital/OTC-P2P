// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice External API of OTCFactoryRegistry.
interface IOTCFactoryRegistry {
    /// @notice Address of OTCClientVault implementation used for clone deployments.
    function clientVaultImplementation() external view returns (address);

    /// @notice Address that receives the protocol portion of operator fees.
    function protocolFeeReceiver() external view returns (address);
    /// @notice Default protocol fee share in basis points applied to all operator factories without an override.
    function defaultProtocolFeeShareBps() external view returns (uint16);
    /// @notice Whether `operatorFactory` is a factory deployed by this registry.
    function isOperatorFactory(address operatorFactory) external view returns (bool);
    /// @notice Whether `vault` is a client vault registered under this registry.
    function isVault(address vault) external view returns (bool);
    /// @notice Whether the protocol fee is waived for `operatorFactory`.
    function isProtocolFeeWaived(address operatorFactory) external view returns (bool);
    /// @notice Custom protocol fee share override for `operatorFactory` in basis points.
    function customProtocolFeeShareBps(address operatorFactory) external view returns (uint16);
    /// @notice Whether `operatorFactory` has a custom protocol fee share set.
    function hasCustomProtocolFeeShare(address operatorFactory) external view returns (bool);
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

    /// @notice Updates the default protocol fee share applied when no override exists.
    /// @param newShareBps New share in basis points; must be ≤ 10 000.
    function setDefaultProtocolFeeShareBps(uint16 newShareBps) external;

    /// @notice Waives or restores the protocol fee for a specific operator factory.
    /// @param operatorFactory Target operator factory.
    /// @param waived `true` to waive, `false` to restore.
    function setOperatorProtocolFeeWaived(address operatorFactory, bool waived) external;

    /// @notice Sets a custom protocol fee share for a specific operator factory.
    /// @param operatorFactory Target operator factory.
    /// @param shareBps Custom share in basis points; must be ≤ 10 000.
    function setCustomProtocolFeeShareBps(address operatorFactory, uint16 shareBps) external;

    /// @notice Removes the custom protocol fee share override, reverting to the default.
    /// @param operatorFactory Target operator factory.
    function clearCustomProtocolFeeShareBps(address operatorFactory) external;

    /// @notice Returns the effective protocol fee share for `operatorFactory`.
    /// @param operatorFactory Target operator factory.
    /// @return Effective protocol fee share in basis points.
    function getProtocolFeeShareBps(address operatorFactory) external view returns (uint16);

    /// @notice Returns the total number of operator factories deployed through this registry.
    function getOperatorFactoriesCount() external view returns (uint256);
}
