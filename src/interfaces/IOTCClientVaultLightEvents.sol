// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Events emitted by OTCClientVaultLight.
interface IOTCClientVaultLightEvents {
    /// @notice Emitted when tokens are deposited into the vault.
    event Deposited(address indexed from, address indexed token, uint256 amount);
    /// @notice Emitted when tokens are withdrawn from the vault.
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    /// @notice Emitted when a lock proposal is created.
    event LockProposed(uint256 indexed proposalId, address indexed token, uint256 newLockUntil);
    /// @notice Emitted when a lock proposal is accepted and the token lock is updated.
    event LockAccepted(uint256 indexed proposalId, address indexed token, uint256 lockUntil);
    /// @notice Emitted when the admin decreases an active token lock.
    event TokenLockDecreasedByAdmin(address indexed token, uint256 previousLockUntil, uint256 newLockUntil);
    /// @notice Emitted when a delivery proposal is created.
    event DeliveryProposed(
        uint256 indexed proposalId, address indexed token, uint256 amount, address indexed deliveryAddress
    );
    /// @notice Emitted when the client or admin accepts a delivery proposal.
    event DeliveryAccepted(uint256 indexed proposalId);
    /// @notice Emitted when a delivery proposal is executed.
    event DeliveryExecuted(uint256 indexed proposalId, address indexed token, address indexed deliveryAddress);
    /// @notice Emitted when any proposal is cancelled.
    event ProposalCancelled(uint256 indexed proposalId);
    /// @notice Emitted when the vault's cached delivery fee rate is synced to a lower value from the factory.
    event VaultFeeConfigSynced(uint16 deliveryFeeBps);
}
