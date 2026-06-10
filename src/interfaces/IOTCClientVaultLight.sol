// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice External API of OTCClientVaultLight — a delivery-only, direct-transfer vault.
interface IOTCClientVaultLight {
    /// @notice Simplified delivery proposal with no allowance-call or swap-level fields.
    struct LightDeliveryProposal {
        /// @notice Whether bps fees are charged on top of or deducted from `amount`.
        OTCTypes.FeeMode feeMode;
        /// @notice Token being delivered from the vault.
        address token;
        /// @notice Delivery amount; net in Gross mode, total budget in Inclusive mode.
        uint256 amount;
        /// @notice Recipient of the direct ERC-20 transfer.
        address deliveryAddress;
        /// @notice Proposal expiry timestamp.
        uint256 deadline;
        /// @notice Fee rates and receivers captured at proposal time.
        OTCTypes.FeeSnapshot feeSnapshot;
        /// @notice Optional extra fee charged at execution.
        OTCTypes.ExtraFee extraFee;
        /// @notice Whether the client has approved the proposal.
        bool clientApproved;
        /// @notice Whether the admin has approved the proposal.
        bool adminApproved;
        /// @notice Whether the proposal has been executed.
        bool executed;
        /// @notice Whether the proposal has been cancelled.
        bool cancelled;
    }

    /// @notice Parameters for creating a light delivery proposal.
    struct LightDeliveryProposalParams {
        /// @notice Whether bps fees are charged on top of or deducted from `amount`.
        OTCTypes.FeeMode feeMode;
        /// @notice Token to deliver.
        address token;
        /// @notice Delivery amount; net in Gross mode, total budget in Inclusive mode.
        uint256 amount;
        /// @notice Recipient of the direct ERC-20 transfer.
        address deliveryAddress;
        /// @notice Proposal expiry timestamp.
        uint256 deadline;
    }

    /// @notice Initializes a freshly deployed clone vault.
    /// @param factory_ Operator factory that manages this vault.
    /// @param client_ Vault owner.
    /// @param defaultLockConfigs_ Initial lock configuration list.
    function initialize(address factory_, address client_, OTCTypes.DefaultLockConfig[] memory defaultLockConfigs_)
        external;

    /// @notice Operator factory that created this vault.
    function factory() external view returns (address);

    /// @notice Delivery fee rate in basis points cached from the factory at vault initialization.
    function vaultFeeConfig() external view returns (uint16 deliveryFeeBps);

    /// @notice Syncs the vault's cached delivery fee rate from the factory, only if it decreases.
    function syncFeeFromFactory() external;

    /// @notice Auto-incrementing id assigned to the next proposal.
    function nextProposalId() external view returns (uint256);

    /// @notice Timestamp after which `token` may be withdrawn.
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
    function deliveryProposals(uint256 proposalId) external view returns (LightDeliveryProposal memory);

    /// @notice Optional owner-only deposit path using `transferFrom`.
    function deposit(address token, uint256 amount) external;

    /// @notice Withdraws `amount` of `token` to `to`. Token must be unlocked.
    function withdraw(address token, uint256 amount, address to) external;

    // ── Lock proposals ──────────────────────────────────────────────────────────

    /// @notice Admin proposes to lock `token` until `newLockUntil`.
    function proposeLock(address token, uint256 newLockUntil, uint256 deadline) external returns (uint256 proposalId);

    /// @notice Client accepts a lock proposal, extending the token lock if the new expiry is later.
    function acceptLockProposal(uint256 proposalId) external;

    /// @notice Cancels a lock proposal. Callable by the client, admin, or factory owner.
    function cancelLockProposal(uint256 proposalId) external;

    /// @notice Admin decreases an active token lock to `newLockUntil`.
    function adminDecreaseLock(address token, uint256 newLockUntil) external;

    // ── Delivery proposals ──────────────────────────────────────────────────────

    /// @notice Creates a direct-transfer delivery proposal.
    /// @param params Delivery parameters.
    /// @param extraFee Optional extra fee charged at execution.
    /// @return proposalId Id of the created proposal.
    function proposeDelivery(LightDeliveryProposalParams calldata params, OTCTypes.ExtraFee calldata extraFee)
        external
        returns (uint256 proposalId);

    /// @notice Approves a delivery proposal as the client or admin side.
    function acceptDeliveryProposal(uint256 proposalId) external;

    /// @notice Executes a delivery proposal once both client and admin have approved.
    function executeDelivery(uint256 proposalId) external;

    /// @notice Cancels a delivery proposal. Callable by the client, admin, or factory owner.
    function cancelDeliveryProposal(uint256 proposalId) external;
}
