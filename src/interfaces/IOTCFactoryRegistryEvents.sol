// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

/// @notice Events emitted by OTCFactoryRegistry.
interface IOTCFactoryRegistryEvents {
    /// @notice Emitted when a new operator factory is deployed.
    event OperatorFactoryDeployed(
        address indexed operatorFactory, address indexed operatorOwner, address indexed operatorAdmin
    );
    /// @notice Emitted when a client vault is registered by an operator factory.
    event VaultRegistered(address indexed operatorFactory, address indexed vault, address indexed client);
    /// @notice Emitted when the protocol fee receiver address changes.
    event ProtocolFeeReceiverUpdated(address indexed previousReceiver, address indexed newReceiver);
    /// @notice Emitted when the default protocol fee share changes.
    event DefaultProtocolFeeShareUpdated(uint16 previousShareBps, uint16 newShareBps);
    /// @notice Emitted when the delivery protocol fee is permanently waived for an operator factory.
    event OperatorDeliveryFeeWaived(address indexed operatorFactory);
    /// @notice Emitted when registry decreases a factory's protocol fee share.
    event FactoryProtocolFeeShareDecreased(
        address indexed operatorFactory, uint16 previousShareBps, uint16 newShareBps
    );
    /// @notice Emitted when the client vault implementation address is updated.
    event ClientVaultImplementationUpdated(address indexed previousImpl, address indexed newImpl);
}
