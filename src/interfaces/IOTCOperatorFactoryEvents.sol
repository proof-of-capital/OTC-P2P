// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Events emitted by OTCOperatorFactory.
interface IOTCOperatorFactoryEvents {
    /// @notice Emitted when a new client vault is deployed.
    event ClientVaultDeployed(address indexed client, address indexed vault);
    /// @notice Emitted when the factory owner changes.
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);
    /// @notice Emitted when the factory admin changes.
    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);
    /// @notice Emitted when the operator fee receiver changes.
    event OperatorFeeReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);
    /// @notice Emitted when the default fee configuration changes.
    event DefaultFeeConfigUpdated(uint16 takerFeeBps, uint16 deliveryFeeBps, uint16 openP2PFeeBps);
    /// @notice Emitted when the default lock duration for a token changes.
    event DefaultLockDurationUpdated(address indexed token, uint256 duration);
    /// @notice Emitted when the locally cached protocol fee share is synced from the registry.
    event ProtocolFeeShareSynced(uint16 previousShareBps, uint16 newShareBps);
    /// @notice Emitted when the delivery fee is permanently waived by the registry.
    event DeliveryFeeWaived();
}
