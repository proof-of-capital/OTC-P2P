// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Shared constants for the OTC P2P protocol.
library OTCConstants {
    /// @notice 100 % expressed in basis points; upper bound for all fee values.
    uint256 internal constant MAX_FEE_BPS = 10_000;
    /// @notice Maximum allowed token lock duration.
    uint256 internal constant MAX_LOCK_DURATION = 365 days;
}
