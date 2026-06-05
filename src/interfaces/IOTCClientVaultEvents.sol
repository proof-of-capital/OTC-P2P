// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice Events emitted by OTCClientVault.
interface IOTCClientVaultEvents {
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
    event DeliveryProposed(uint256 indexed proposalId, address indexed token, uint256 amount, address indexed target);
    /// @notice Emitted when the client accepts a delivery proposal.
    event DeliveryAccepted(uint256 indexed proposalId);
    /// @notice Emitted when a delivery proposal is executed.
    event DeliveryExecuted(
        uint256 indexed proposalId,
        address indexed token,
        address indexed target,
        address expectedReceivedToken,
        uint256 minExpectedReceivedAmount
    );
    /// @notice Emitted when the client updates the maximum swap access level.
    event SwapAccessLevelUpdated(OTCTypes.SwapAccessLevel oldLevel, OTCTypes.SwapAccessLevel newLevel);
    /// @notice Emitted when a unified swap proposal is created.
    event SwapProposed(
        uint256 indexed proposalId,
        OTCTypes.SwapAccessLevel level,
        address indexed proposer,
        address indexed counterparty,
        address tokenOut,
        address tokenIn,
        uint256 amountOut,
        uint256 amountIn
    );
    /// @notice Emitted when any required swap participant approves.
    event SwapApproved(uint256 indexed proposalId, address indexed approver);
    /// @notice Emitted when a unified swap executes.
    event SwapExecuted(uint256 indexed proposalId);
    /// @notice Emitted when any proposal type is cancelled.
    event ProposalCancelled(uint256 indexed proposalId);
}
