// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Custom errors for OTCClientVault.
interface IOTCClientVaultErrors {
    /// @notice Caller is not the factory admin.
    error NotFactoryAdmin();
    /// @notice Caller is not the client, factory admin, or factory owner.
    error NotAuthorized();
    /// @notice Caller is not a swap participant that may approve this proposal.
    error NotSwapParticipant();
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
    /// @param duration The supplied duration.
    /// @param maxAllowed Maximum allowed duration.
    error LockDurationTooLarge(uint256 duration, uint256 maxAllowed);
    /// @notice Token is locked and cannot be withdrawn or used in an open P2P swap.
    /// @param token The locked token.
    /// @param unlocksAt Timestamp when the lock expires.
    error TokenLocked(address token, uint256 unlocksAt);
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
    /// @notice Supplier has not yet approved this proposal.
    error SupplierNotApproved();
    /// @notice External party has not yet approved this proposal.
    error ExternalPartyNotApproved();
    /// @notice Counterparty has not yet approved this proposal.
    error CounterpartyNotApproved();
    /// @notice The allowance-call delivery failed.
    error DeliveryCallFailed();
    /// @notice Received token amount is below the minimum.
    /// @param received Actual received amount.
    /// @param minExpected Minimum acceptable amount.
    error InsufficientReceived(uint256 received, uint256 minExpected);
    /// @notice Direct delivery fields (target, callData, expectedReceivedToken) must all be empty.
    error DirectDeliveryInvalidFields();
    /// @notice Allowance-call delivery fields (deliveryAddress, target, callData) must all be non-empty.
    error AllowanceDeliveryInvalidFields();
    /// @notice `expectedReceivedToken` is zero but `minExpectedReceivedAmount` is non-zero.
    error InvalidExpectedAmount();
    /// @notice Extra fee token is zero but amount is non-zero, or vice versa.
    error InvalidExtraFeeToken();
    /// @notice Extra fee receiver is zero but amount is non-zero.
    error InvalidExtraFeeReceiver();
    /// @notice Swap token addresses are identical or zero.
    error InvalidSwapTokens();
    /// @notice Swap amounts are zero.
    error InvalidSwapAmounts();
    /// @notice Swap level is `None`.
    error InvalidSwapLevel();
    /// @notice Proposal level is above the vault's configured maximum.
    error SwapLevelNotAllowed();
}
