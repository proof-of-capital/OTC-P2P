// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice External API of OTCClientVault.
interface IOTCClientVault {
    /// @notice Initializes a freshly deployed clone vault.
    /// @param factory_ Operator factory that manages this vault.
    /// @param client_ Vault owner.
    /// @param defaultLockConfigs_ Initial lock configuration list.
    function initialize(address factory_, address client_, OTCTypes.DefaultLockConfig[] memory defaultLockConfigs_)
        external;

    /// @notice Accepts native ETH sent to the vault.
    receive() external payable;

    /// @notice Operator factory that created this vault.
    function factory() external view returns (address);
    /// @notice Maximum swap level currently enabled by the client (`DeliveryOnly` disables swap actions).
    function swapAccessLevel() external view returns (OTCTypes.SwapAccessLevel);
    /// @notice Auto-incrementing id assigned to the next proposal.
    function nextProposalId() external view returns (uint256);
    /// @notice Timestamp after which `token` may be withdrawn or used in open P2P swaps.
    function tokenLockUntil(address token) external view returns (uint256);
    /// @notice Lock proposal stored under `proposalId`.
    function lockProposals(uint256 proposalId)
        external
        view
        returns (
            address token,
            uint256 newLockUntil,
            uint256 deadline,
            bool clientApproved,
            bool executed,
            bool cancelled
        );

    /// @notice Delivery proposal stored under `proposalId`.
    function deliveryProposals(uint256 proposalId)
        external
        view
        returns (
            bool useAllowanceCall,
            OTCTypes.FeeMode feeMode,
            address token,
            uint256 amount,
            address deliveryAddress,
            address target,
            bytes memory callData,
            address expectedReceivedToken,
            uint256 minExpectedReceivedAmount,
            uint256 deadline,
            OTCTypes.FeeSnapshot memory feeSnapshot,
            OTCTypes.ExtraFee memory extraFee,
            bool clientApproved,
            bool adminApproved,
            bool executed,
            bool cancelled
        );

    /// @notice Swap proposal stored under `proposalId`.
    function swapProposals(uint256 proposalId)
        external
        view
        returns (
            OTCTypes.SwapAccessLevel level,
            OTCTypes.FeeMode feeMode,
            address proposer,
            address counterparty,
            address tokenOut,
            uint256 amountOut,
            address tokenIn,
            uint256 amountIn,
            uint256 deadline,
            OTCTypes.FeeSnapshot memory feeSnapshot,
            OTCTypes.ExtraFee memory extraFee,
            bool adminApproved,
            bool clientApproved,
            bool counterpartyApproved,
            bool executed,
            bool cancelled
        );

    /// @notice Transfers `amount` of `token` from the caller into the vault.
    /// @param token ERC-20 token to deposit.
    /// @param amount Amount to deposit; must be greater than zero.
    function deposit(address token, uint256 amount) external;

    /// @notice Withdraws `amount` of `token` to `to`. Token must be unlocked.
    /// @param token ERC-20 token to withdraw.
    /// @param amount Amount to withdraw; must be greater than zero.
    /// @param to Recipient address; must be non-zero.
    function withdraw(address token, uint256 amount, address to) external;

    /// @notice Withdraws the entire vault balance of `token` to `to`. Token must be unlocked.
    /// @param token ERC-20 token to withdraw.
    /// @param to Recipient address; must be non-zero.
    function withdrawAll(address token, address to) external;

    // ── Lock proposals ──────────────────────────────────────────────────────────

    /// @notice Admin proposes to lock `token` until `newLockUntil`.
    /// @param token Token to lock.
    /// @param newLockUntil Absolute timestamp the lock should extend to.
    /// @param deadline Proposal expiry; must be after the current block.
    /// @return proposalId Id of the created proposal.
    function proposeLock(address token, uint256 newLockUntil, uint256 deadline) external returns (uint256 proposalId);

    /// @notice Client accepts a lock proposal, extending the token lock if the new expiry is later.
    /// @param proposalId Proposal to accept.
    function acceptLockProposal(uint256 proposalId) external;

    /// @notice Cancels a lock proposal. Callable by the client, admin, or factory owner.
    /// @param proposalId Proposal to cancel.
    function cancelLockProposal(uint256 proposalId) external;

    /// @notice Admin immediately sets the token lock to the current block timestamp (effectively unlocking).
    /// @param token Token to unlock.
    function adminUnlock(address token) external;

    // ── Delivery proposals ──────────────────────────────────────────────────────

    /// @notice Admin creates a delivery proposal.
    /// @param params Delivery parameters.
    /// @param extraFee Optional extra fee charged at execution.
    /// @return proposalId Id of the created proposal.
    function proposeDelivery(OTCTypes.DeliveryProposalParams calldata params, OTCTypes.ExtraFee calldata extraFee)
        external
        returns (uint256 proposalId);

    /// @notice Client approves a delivery proposal.
    /// @param proposalId Proposal to approve.
    function acceptDeliveryProposal(uint256 proposalId) external;

    /// @notice Anyone executes a delivery proposal once both approvals are in place.
    /// @param proposalId Proposal to execute.
    function executeDelivery(uint256 proposalId) external;

    /// @notice Cancels a delivery proposal. Callable by the client, admin, or factory owner.
    /// @param proposalId Proposal to cancel.
    function cancelDeliveryProposal(uint256 proposalId) external;

    // ── Swap proposals ──────────────────────────────────────────────────────────

    /// @notice Client updates the maximum swap level enabled for this vault.
    function setSwapAccessLevel(OTCTypes.SwapAccessLevel newLevel) external;

    /// @notice Creates a unified swap proposal and auto-approves the caller's role when applicable.
    function createSwapProposal(OTCTypes.SwapProposalParams calldata params, OTCTypes.ExtraFee calldata extraFee)
        external
        returns (uint256 proposalId);

    /// @notice Approves a unified swap proposal as admin, client, or proposal counterparty.
    function approveSwap(uint256 proposalId) external;

    /// @notice Executes a unified swap after required approvals; caller approval is auto-counted when applicable.
    function executeSwap(uint256 proposalId) external;

    /// @notice Cancels a unified swap proposal. Callable by client, admin, factory owner, or counterparty.
    function cancelSwapProposal(uint256 proposalId) external;
}
