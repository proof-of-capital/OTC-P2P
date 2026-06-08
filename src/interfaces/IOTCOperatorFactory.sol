// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice External API of OTCOperatorFactory.
interface IOTCOperatorFactory {
    /// @notice Immutable registry this factory is registered in.
    function registry() external view returns (address);
    /// @notice Factory admin allowed to propose transactions in client vaults.
    function admin() external view returns (address);
    /// @notice Address that receives the operator's net fee revenue.
    function operatorFeeReceiver() external view returns (address);
    /// @notice Whether `vault` was deployed by this factory.
    function isFactoryVault(address vault) external view returns (bool);
    /// @notice Vault deployed at index `index`.
    function vaults(uint256 index) external view returns (address);
    /// @notice Token configured at index `index` in the default lock token list.
    function defaultLockTokens(uint256 index) external view returns (address);

    /// @notice Default fee configuration applied to all new client vaults.
    /// @return takerFeeBps Swap fee rate in basis points (SupplierOnly and ManagedP2P).
    /// @return deliveryFeeBps Delivery fee rate in basis points.
    /// @return openP2PFeeBps Open P2P fee rate in basis points.
    function defaultFeeConfig() external view returns (uint16 takerFeeBps, uint16 deliveryFeeBps, uint16 openP2PFeeBps);

    /// @notice Protocol fee share (in bps) cached locally from the registry.
    /// @dev Set at factory deployment from registry default; can only decrease via syncProtocolFeeShare().
    function protocolFeeShareBps() external view returns (uint16);

    /// @notice Protocol fee receiver — read dynamically from the registry.
    function protocolFeeReceiver() external view returns (address);

    /// @notice Whether the protocol share of the delivery fee is waived for this factory — read from registry.
    function isDeliveryFeeWaived() external view returns (bool);

    /// @notice Default lock duration in seconds for `token`.
    function defaultLockDuration(address token) external view returns (uint256);

    /// @notice Permissionlessly deploys and initializes a new `OTCClientVault` clone for `client`, then registers it.
    /// @dev Callable by any address; `client` becomes the vault owner regardless of `msg.sender`.
    /// @param client Owner of the new vault.
    /// @return vault Address of the newly deployed vault.
    function deployClientVault(address client) external returns (address vault);

    /// @notice Transfers factory ownership to `newOwner`.
    /// @param newOwner New owner address; must be non-zero.
    function setOwner(address newOwner) external;

    /// @notice Updates the factory admin.
    /// @param newAdmin New admin address; must be non-zero.
    function setAdmin(address newAdmin) external;

    /// @notice Updates the address that receives operator fee revenue.
    /// @param newReceiver New receiver address; must be non-zero.
    function setOperatorFeeReceiver(address newReceiver) external;

    /// @notice Replaces the default fee configuration.
    /// @param newConfig New fee configuration; all fields must be ≤ 10 000 bps.
    function setDefaultFeeConfig(OTCTypes.OperatorFeeConfig calldata newConfig) external;

    /// @notice Sets the default lock duration for a single token.
    /// @param token ERC-20 token address; must be non-zero.
    /// @param duration Lock duration in seconds; must be ≤ `OTCConstants.MAX_LOCK_DURATION`.
    function setDefaultLockDuration(address token, uint256 duration) external;

    /// @notice Batch-updates default lock durations for multiple tokens.
    /// @param tokens ERC-20 token addresses.
    /// @param durations Lock durations in seconds, one per token.
    function setDefaultLockDurationsBatch(address[] calldata tokens, uint256[] calldata durations) external;

    /// @notice Returns a complete fee snapshot for use by client vaults at proposal creation time.
    /// @return snapshot Current fee rates, receivers, and protocol share.
    function getCurrentFeeSnapshot() external view returns (OTCTypes.FeeSnapshot memory snapshot);

    /// @notice Sets the protocol fee share. Only callable by the registry.
    /// @dev Registry enforces the decrease-only constraint and minimum floor.
    /// @param newShareBps New protocol fee share in basis points.
    function setProtocolFeeShareBps(uint16 newShareBps) external;

    /// @notice Permanently waives the protocol share of delivery fees. Only callable by the registry.
    /// @dev Irreversible — once waived, cannot be undone.
    function setDeliveryFeeWaived() external;

    /// @notice Returns the total number of client vaults deployed by this factory.
    function getVaultsCount() external view returns (uint256);

    /// @notice Returns the total number of tracked default-lock tokens.
    function getDefaultLockTokensCount() external view returns (uint256);
}
