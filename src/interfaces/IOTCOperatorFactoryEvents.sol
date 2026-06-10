// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Events emitted by OTCOperatorFactory.
interface IOTCOperatorFactoryEvents {
    /// @notice Emitted when a new client vault is deployed.
    event ClientVaultDeployed(address indexed client, address indexed vault);
    /// @notice Emitted when the factory admin changes.
    event AdminUpdated(address indexed previousAdmin, address indexed newAdmin);
    /// @notice Emitted when the operator fee receiver changes.
    event OperatorFeeReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);
    /// @notice Emitted when the default fee configuration changes.
    event DefaultFeeConfigUpdated(uint16 takerFeeBps, uint16 deliveryFeeBps, uint16 openP2PFeeBps);
    /// @notice Emitted when the default lock duration for a token changes.
    event DefaultLockDurationUpdated(address indexed token, uint256 duration);
    /// @notice Emitted when the DeliveryOnly protocol fee share is updated by the registry.
    event DeliveryOnlyProtocolFeeShareSynced(uint16 previousShareBps, uint16 newShareBps);
    /// @notice Emitted when the non-DeliveryOnly protocol fee share is updated by the registry.
    event OtherProtocolFeeShareSynced(uint16 previousShareBps, uint16 newShareBps);
}
