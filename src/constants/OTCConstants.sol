// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Shared constants for the OTC P2P protocol.
library OTCConstants {
    /// @notice 100 % expressed in basis points; upper bound for all fee values.
    uint256 internal constant MAX_FEE_BPS = 10_000;
    /// @notice 0.05 % expressed in basis points; lower bound for all operator fee values.
    uint16 internal constant MIN_FEE_BPS = 5;
    /// @notice Maximum allowed token lock duration.
    uint256 internal constant MAX_LOCK_DURATION = 365 days;
    /// @notice Minimum protocol fee share in basis points (10 %). Registry can never set it below this.
    uint16 internal constant MIN_PROTOCOL_FEE_SHARE_BPS = 1_000;
    /// @notice Initial protocol fee share assigned to every new operator factory (25 %).
    uint16 internal constant DEFAULT_PROTOCOL_FEE_SHARE_BPS = 2_500;
}
