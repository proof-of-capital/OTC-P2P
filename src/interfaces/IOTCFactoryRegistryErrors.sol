// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Custom errors for OTCFactoryRegistry.
interface IOTCFactoryRegistryErrors {
    /// @notice Caller is not a registered operator factory.
    error NotOperatorFactory();
    /// @notice Caller must be the operator owner registering their own factory.
    error NotOperatorOwner();
    /// @notice Address argument is zero.
    error InvalidAddress();
    /// @notice Fee share exceeds the 100 % basis-point ceiling.
    error ProtocolFeeShareTooLarge(uint256 shareBps, uint256 maxAllowed);
    /// @notice Fee config contains a value that exceeds the 100 % basis-point ceiling.
    error FeeBpsTooLarge(uint256 feeBps, uint256 maxAllowed);
}
