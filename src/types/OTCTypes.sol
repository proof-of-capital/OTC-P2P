// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCConstants} from "../constants/OTCConstants.sol";

/// @notice Shared structs for the OTC P2P protocol.
library OTCTypes {
    /// @notice Fee config contains a value that exceeds the 100 % basis-point ceiling.
    error FeeBpsTooLarge(uint256 feeBps, uint256 maxAllowed);
    /// @notice Fee config contains a value below the 0.05 % basis-point floor.
    error FeeBpsTooSmall(uint256 feeBps, uint256 minAllowed);

    /// @notice How percentage fees are applied to proposal amounts.
    enum FeeMode {
        /// @notice The proposal amount is net; percentage fees are charged on top.
        Gross,
        /// @notice The proposal amount is total budget; percentage fees are deducted from it.
        Inclusive
    }

    /// @notice Operator fee percentages expressed in basis points (10 000 = 100 %).
    struct OperatorFeeConfig {
        /// @notice Fee charged on swap operations (SupplierOnly and ManagedP2P).
        uint16 takerFeeBps;
        /// @notice Fee charged on delivery operations.
        uint16 deliveryFeeBps;
        /// @notice Fee charged on open peer-to-peer swaps.
        uint16 openP2PFeeBps;
    }

    /// @notice Default token lock configuration applied on vault deployment.
    struct DefaultLockConfig {
        /// @notice ERC-20 token address to initialize lock for.
        address token;
        /// @notice Lock duration in seconds applied from deployment timestamp.
        uint256 duration;
    }

    /// @notice Immutable snapshot of fee parameters captured at proposal creation.
    struct FeeSnapshot {
        /// @notice Swap fee rate at snapshot time (SupplierOnly and ManagedP2P).
        uint16 takerFeeBps;
        /// @notice Delivery fee rate at snapshot time.
        uint16 deliveryFeeBps;
        /// @notice Open P2P fee rate at snapshot time.
        uint16 openP2PFeeBps;
        /// @notice Protocol's share of the operator fee at snapshot time.
        uint16 protocolFeeShareBps;
        /// @notice Address that receives the operator's net fee portion.
        address operatorFeeReceiver;
        /// @notice Address that receives the protocol fee portion.
        address protocolFeeReceiver;
    }

    /// @notice Optional additional fee charged alongside the standard fee.
    struct ExtraFee {
        /// @notice ERC-20 token used for the extra fee; zero address means no extra fee.
        address token;
        /// @notice Amount of `token` to transfer as the extra fee.
        uint256 amount;
        /// @notice Recipient of the extra fee.
        address receiver;
    }

    /// @notice Proposal to lock a token in the vault until a specific timestamp.
    struct LockProposal {
        /// @notice Token subject to the lock.
        address token;
        /// @notice Absolute timestamp the lock would extend to.
        uint256 newLockUntil;
        /// @notice Timestamp after which the proposal can no longer be accepted.
        uint256 deadline;
        /// @notice Whether the client has accepted the proposal.
        bool clientApproved;
        /// @notice Whether the proposal has been executed.
        bool executed;
        /// @notice Whether the proposal has been cancelled.
        bool cancelled;
    }

    /// @notice Proposal for delivering vault tokens to an external destination.
    struct DeliveryProposal {
        /// @notice Whether the delivery uses an allowance-and-call pattern instead of a direct transfer.
        bool useAllowanceCall;
        /// @notice Whether bps fees are charged on top of or deducted from `amount`.
        FeeMode feeMode;
        /// @notice Swap access level snapshot captured when the proposal is created.
        SwapAccessLevel level;
        /// @notice Token being delivered from the vault.
        address token;
        /// @notice Delivery amount; net in Gross mode, total budget in Inclusive mode.
        uint256 amount;
        /// @notice Direct-delivery recipient or allowance-call spender, depending on mode.
        address deliveryAddress;
        /// @notice External contract called in allowance-call mode.
        address target;
        /// @notice Calldata sent to `target` in allowance-call mode.
        bytes callData;
        /// @notice Token expected to be received back after an allowance call.
        address expectedReceivedToken;
        /// @notice Minimum acceptable amount of `expectedReceivedToken` received.
        uint256 minExpectedReceivedAmount;
        /// @notice Proposal expiry timestamp.
        uint256 deadline;
        /// @notice Fee rates and receivers captured at proposal time.
        FeeSnapshot feeSnapshot;
        /// @notice Optional extra fee charged at execution.
        ExtraFee extraFee;
        /// @notice Whether the client has approved the proposal.
        bool clientApproved;
        /// @notice Whether the admin has approved the proposal.
        bool adminApproved;
        /// @notice Whether the proposal has been executed.
        bool executed;
        /// @notice Whether the proposal has been cancelled.
        bool cancelled;
    }

    /// @notice Parameters for creating a delivery proposal.
    struct DeliveryProposalParams {
        /// @notice Whether to use allowance-call delivery mode.
        bool useAllowanceCall;
        /// @notice Whether bps fees are charged on top of or deducted from `amount`.
        FeeMode feeMode;
        /// @notice Token to deliver.
        address token;
        /// @notice Delivery amount; net in Gross mode, total budget in Inclusive mode.
        uint256 amount;
        /// @notice Direct-delivery recipient or allowance-call spender, depending on mode.
        address deliveryAddress;
        /// @notice Call target (zero for direct mode).
        address target;
        /// @notice Calldata for the call (empty for direct mode).
        bytes callData;
        /// @notice Token expected back after the allowance call.
        address expectedReceivedToken;
        /// @notice Minimum amount of `expectedReceivedToken` to receive.
        uint256 minExpectedReceivedAmount;
        /// @notice Proposal expiry timestamp.
        uint256 deadline;
    }

    /// @notice Maximum swap capability enabled by the client for the vault.
    /// @dev `DeliveryOnly` disables all swap actions while keeping delivery flows available.
    enum SwapAccessLevel {
        DeliveryOnly,
        SupplierOnly,
        ManagedP2P,
        OpenP2P
    }

    /// @notice Parameters for creating any token-for-token swap proposal.
    struct SwapProposalParams {
        /// @notice Concrete swap level for this proposal.
        SwapAccessLevel level;
        /// @notice Whether bps fees are charged on top of or deducted from `amountIn`.
        FeeMode feeMode;
        /// @notice Third party that sends tokenIn and receives tokenOut.
        address counterparty;
        /// @notice Token leaving the vault.
        address tokenOut;
        /// @notice Amount of `tokenOut` transferred to the counterparty.
        uint256 amountOut;
        /// @notice Token entering the vault from the counterparty.
        address tokenIn;
        /// @notice Incoming amount; net in Gross mode, total budget in Inclusive mode.
        uint256 amountIn;
        /// @notice Proposal expiry timestamp.
        uint256 deadline;
    }

    /// @notice Unified proposal for supplier, managed P2P, and open P2P swaps.
    struct SwapProposal {
        /// @notice Concrete swap level for this proposal.
        SwapAccessLevel level;
        /// @notice Whether bps fees are charged on top of or deducted from `amountIn`.
        FeeMode feeMode;
        /// @notice Address that created the proposal.
        address proposer;
        /// @notice Third party that sends tokenIn and receives tokenOut.
        address counterparty;
        /// @notice Token leaving the vault.
        address tokenOut;
        /// @notice Amount of `tokenOut` transferred to the counterparty.
        uint256 amountOut;
        /// @notice Token entering the vault from the counterparty.
        address tokenIn;
        /// @notice Incoming amount; net in Gross mode, total budget in Inclusive mode.
        uint256 amountIn;
        /// @notice Proposal expiry timestamp.
        uint256 deadline;
        /// @notice Fee rates and receivers captured at proposal time.
        FeeSnapshot feeSnapshot;
        /// @notice Optional extra fee charged at execution.
        ExtraFee extraFee;
        /// @notice Whether the operator admin has approved the swap.
        bool adminApproved;
        /// @notice Whether the client has approved the swap.
        bool clientApproved;
        /// @notice Whether the counterparty has approved the swap.
        bool counterpartyApproved;
        /// @notice Whether the proposal has been executed.
        bool executed;
        /// @notice Whether the proposal has been cancelled.
        bool cancelled;
    }

    /// @notice Validates operator fee bounds against protocol constants.
    function _requireValidFeeConfig(OperatorFeeConfig memory config) internal pure {
        require(
            config.takerFeeBps <= OTCConstants.MAX_FEE_BPS, FeeBpsTooLarge(config.takerFeeBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            config.deliveryFeeBps <= OTCConstants.MAX_FEE_BPS,
            FeeBpsTooLarge(config.deliveryFeeBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            config.openP2PFeeBps <= OTCConstants.MAX_FEE_BPS,
            FeeBpsTooLarge(config.openP2PFeeBps, OTCConstants.MAX_FEE_BPS)
        );
        require(
            config.takerFeeBps >= OTCConstants.MIN_FEE_BPS, FeeBpsTooSmall(config.takerFeeBps, OTCConstants.MIN_FEE_BPS)
        );
        require(
            config.deliveryFeeBps >= OTCConstants.MIN_FEE_BPS,
            FeeBpsTooSmall(config.deliveryFeeBps, OTCConstants.MIN_FEE_BPS)
        );
        require(
            config.openP2PFeeBps >= OTCConstants.MIN_FEE_BPS,
            FeeBpsTooSmall(config.openP2PFeeBps, OTCConstants.MIN_FEE_BPS)
        );
    }
}
