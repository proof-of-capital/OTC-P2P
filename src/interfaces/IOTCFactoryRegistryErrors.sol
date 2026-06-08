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
    /// @notice Fee share is below the minimum allowed value (10 %).
    error ProtocolFeeShareTooLow(uint256 shareBps, uint256 minAllowed);
    /// @notice New protocol fee share is not lower than the current value — only decreases are allowed.
    error ProtocolFeeCannotIncrease(uint256 newShareBps, uint256 currentShareBps);
    /// @notice Fee config contains a value that exceeds the 100 % basis-point ceiling.
    error FeeBpsTooLarge(uint256 feeBps, uint256 maxAllowed);
    /// @notice Fee config contains a value below the 0.05 % basis-point floor.
    error FeeBpsTooSmall(uint256 feeBps, uint256 minAllowed);
    /// @notice Vault was already registered in the registry.
    error VaultAlreadyRegistered(address vault);
    /// @notice Vault reports a different factory than expected.
    error VaultFactoryMismatch(address vault, address expectedFactory, address actualFactory);
    /// @notice Factory does not recognize the vault as its own deployment.
    error VaultNotFactoryOwned(address operatorFactory, address vault);
}
