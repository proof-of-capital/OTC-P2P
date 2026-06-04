// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Custom errors for OTCOperatorFactory.
interface IOTCOperatorFactoryErrors {
    /// @notice Address argument is zero.
    error InvalidAddress();
    /// @notice Fee config contains a value that exceeds the 100 % basis-point ceiling.
    /// @param feeBps The supplied fee value.
    /// @param maxAllowed Maximum allowed value.
    error FeeBpsTooLarge(uint256 feeBps, uint256 maxAllowed);
    /// @notice Lock duration exceeds the protocol maximum.
    /// @param duration The supplied duration.
    /// @param maxAllowed Maximum allowed duration.
    error LockDurationTooLarge(uint256 duration, uint256 maxAllowed);
    /// @notice Input arrays have different lengths.
    error ArrayLengthMismatch(uint256 a, uint256 b);
}
