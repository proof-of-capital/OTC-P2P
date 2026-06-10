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
    /// @notice Emitted when the default DeliveryOnly protocol fee share changes.
    event DefaultDeliveryOnlyProtocolFeeShareUpdated(uint16 previousShareBps, uint16 newShareBps);
    /// @notice Emitted when the default non-DeliveryOnly protocol fee share changes.
    event DefaultOtherProtocolFeeShareUpdated(uint16 previousShareBps, uint16 newShareBps);
    /// @notice Emitted when registry decreases a factory's DeliveryOnly protocol fee share.
    event FactoryDeliveryOnlyProtocolFeeShareDecreased(
        address indexed operatorFactory, uint16 previousShareBps, uint16 newShareBps
    );
    /// @notice Emitted when registry decreases a factory's non-DeliveryOnly protocol fee share.
    event FactoryOtherProtocolFeeShareDecreased(
        address indexed operatorFactory, uint16 previousShareBps, uint16 newShareBps
    );
    /// @notice Emitted when the client vault implementation address is updated.
    event ClientVaultImplementationUpdated(address indexed previousImpl, address indexed newImpl);
    /// @notice Emitted when a new agent (referral) is registered.
    event AgentRegistered(string agentId, address agentAddress, uint16 feeBps);
    /// @notice Emitted when an agent's fee share is increased.
    event AgentFeeIncreased(string agentId, uint16 previousFeeBps, uint16 newFeeBps);
    /// @notice Emitted when a factory is assigned an agent at deployment.
    event FactoryAgentAssigned(address indexed operatorFactory, string agentId);
    /// @notice Emitted when an agent updates their receiving address.
    event AgentAddressUpdated(string agentId, address indexed oldAddress, address indexed newAddress);
    /// @notice Emitted when an agent claims their accumulated fees.
    event AgentFeesClaimed(string agentId, address indexed agentAddress, address indexed token, uint256 amount);
    /// @notice Emitted when the owner withdraws accumulated protocol fees.
    event ProtocolFeesWithdrawn(address indexed to, address indexed token, uint256 amount);
}
