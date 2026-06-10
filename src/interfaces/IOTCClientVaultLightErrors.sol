// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Custom errors for OTCClientVaultLight.
interface IOTCClientVaultLightErrors {
    /// @notice Caller is not the factory admin.
    error NotFactoryAdmin();
    /// @notice Caller is not the client, factory admin, or factory owner.
    error NotAuthorized();
    /// @notice Address argument is zero.
    error InvalidAddress();
    /// @notice Amount argument is zero.
    error InvalidAmount();
    /// @notice Deadline is in the past or equal to the current block timestamp.
    error InvalidDeadline();
    /// @notice Lock-until timestamp is in the past or equal to the current block timestamp.
    error InvalidLockUntil();
    /// @notice Proposal does not exist (deadline is zero).
    error InvalidProposal();
    /// @notice Token lock duration exceeds the protocol maximum.
    error LockDurationTooLarge(uint256 duration, uint256 maxAllowed);
    /// @notice Token is locked and cannot be withdrawn.
    error TokenLocked(address token, uint256 unlocksAt);
    /// @notice Token does not have an active lock.
    error TokenNotLocked();
    /// @notice Supplied lock timestamp does not reduce the current lock.
    error LockNotDecreased();
    /// @notice Proposal has already been executed.
    error ProposalAlreadyExecuted();
    /// @notice Proposal has already been cancelled.
    error ProposalAlreadyCancelled();
    /// @notice Proposal deadline has passed.
    error ProposalExpired(uint256 deadline, uint256 currentTime);
    /// @notice Client has not yet approved this proposal.
    error ClientNotApproved();
    /// @notice Admin has not yet approved this proposal.
    error AdminNotApproved();
    /// @notice Extra fee token is zero but amount is non-zero, or vice versa.
    error InvalidExtraFeeToken();
    /// @notice Extra fee receiver is zero but amount is non-zero.
    error InvalidExtraFeeReceiver();
    /// @notice Fee sync rejected: new rate is not better for the user.
    error FeeNotImproved();
}
