// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {OTCTypes} from "../types/OTCTypes.sol";

/// @notice External API of OTCFactoryRegistry.
interface IOTCFactoryRegistry {
    /// @notice Address of OTCClientVault implementation used for clone deployments.
    function clientVaultImplementation() external view returns (address);

    /// @notice Address that receives the protocol portion of operator fees.
    function protocolFeeReceiver() external view returns (address);
    /// @notice Default DeliveryOnly protocol fee share assigned to new factories.
    function defaultDeliveryOnlyProtocolFeeShareBps() external view returns (uint16);
    /// @notice Default non-DeliveryOnly protocol fee share assigned to new factories.
    function defaultOtherProtocolFeeShareBps() external view returns (uint16);
    /// @notice Whether `operatorFactory` is a factory deployed by this registry.
    function isOperatorFactory(address operatorFactory) external view returns (bool);
    /// @notice Whether `vault` is a client vault registered under this registry.
    function isVault(address vault) external view returns (bool);
    /// @notice Operator factory deployed at index `index`.
    function operatorFactories(uint256 index) external view returns (address);
    /// @notice Returns the agent address and fee share for `agentId`; agentAddress is zero if not registered.
    function agents(string calldata agentId) external view returns (address agentAddress, uint16 feeBps);
    /// @notice String ID of the agent assigned to `operatorFactory`; empty string means no agent.
    function factoryAgentId(address operatorFactory) external view returns (string memory);
    /// @notice Pending fee balance for agent `agentId` in `token`.
    function agentPendingFees(string calldata agentId, address token) external view returns (uint256);
    /// @notice Pending protocol fee balance for `token`.
    function protocolPendingFees(address token) external view returns (uint256);

    /// @notice Deploys a new `OTCOperatorFactory` and registers it in the registry.
    /// @dev Callable by anyone; `msg.sender` must equal `operatorOwner` (self-service onboarding).
    /// @param operatorOwner Owner of the new operator factory; must be `msg.sender`.
    /// @param operatorAdmin Admin of the new operator factory.
    /// @param operatorFeeReceiver Address that receives the operator's fee revenue.
    /// @param defaultFeeConfig Initial fee configuration for the operator.
    /// @param agentId Registered agent string ID; empty string means no referral.
    /// @return operatorFactory Address of the newly deployed factory.
    function deployOperatorFactory(
        address operatorOwner,
        address operatorAdmin,
        address operatorFeeReceiver,
        OTCTypes.OperatorFeeConfig calldata defaultFeeConfig,
        string calldata agentId
    ) external returns (address operatorFactory);

    /// @notice Called by operator factories to register a freshly deployed client vault.
    /// @param vault Address of the vault being registered.
    function registerVault(address vault) external;

    /// @notice Updates the address that receives the protocol fee.
    /// @param newReceiver New protocol fee receiver; must be non-zero.
    function setProtocolFeeReceiver(address newReceiver) external;

    /// @notice Updates the default DeliveryOnly protocol fee share used for new factory deployments.
    /// @param newShareBps New share in basis points.
    function setDefaultDeliveryOnlyProtocolFeeShareBps(uint16 newShareBps) external;

    /// @notice Updates the default non-DeliveryOnly protocol fee share used for new factory deployments.
    /// @param newShareBps New share in basis points.
    function setDefaultOtherProtocolFeeShareBps(uint16 newShareBps) external;

    /// @notice Decreases the DeliveryOnly protocol fee share for a specific operator factory.
    /// @param operatorFactory Target operator factory.
    /// @param newShareBps New share in basis points.
    function setFactoryDeliveryOnlyProtocolFeeShareBps(address operatorFactory, uint16 newShareBps) external;

    /// @notice Decreases the non-DeliveryOnly protocol fee share for a specific operator factory.
    /// @param operatorFactory Target operator factory.
    /// @param newShareBps New share in basis points.
    function setFactoryOtherProtocolFeeShareBps(address operatorFactory, uint16 newShareBps) external;

    /// @notice Returns the DeliveryOnly protocol fee share for `operatorFactory`.
    function getDeliveryOnlyProtocolFeeShareBps(address operatorFactory) external view returns (uint16);

    /// @notice Returns the non-DeliveryOnly protocol fee share for `operatorFactory`.
    function getOtherProtocolFeeShareBps(address operatorFactory) external view returns (uint16);

    /// @notice Updates the vault implementation address used for all future clone deployments.
    /// @param newImpl New implementation address; must be non-zero.
    function setClientVaultImplementation(address newImpl) external;

    /// @notice Returns the total number of operator factories deployed through this registry.
    function getOperatorFactoriesCount() external view returns (uint256);

    /// @notice Registers a new agent (referral) identified by a string ID.
    /// @param agentId Unique non-empty string identifier for the agent.
    /// @param agentAddress Wallet address of the agent; must be non-zero.
    /// @param feeBps Fee share in bps; must be in [MIN_AGENT_FEE_BPS, MAX_AGENT_FEE_BPS].
    function registerAgent(string calldata agentId, address agentAddress, uint16 feeBps) external;

    /// @notice Increases an existing agent's fee share. Only increases are allowed.
    /// @param agentId Registered agent string ID.
    /// @param newFeeBps New fee share; must be strictly greater than current and ≤ MAX_AGENT_FEE_BPS.
    function increaseAgentFee(string calldata agentId, uint16 newFeeBps) external;

    /// @notice Allows the current agent address to update itself to a new address.
    /// @param agentId Agent string ID to update.
    /// @param newAddress New receiving address; must be non-zero.
    function setAgentAddress(string calldata agentId, address newAddress) external;

    /// @notice Called by a registered vault after transferring the protocol fee to the registry.
    /// @dev Splits the fee between the factory's agent and the protocol balance.
    /// @param token ERC-20 token that was transferred.
    /// @param amount Amount transferred.
    function receiveProtocolFee(address token, uint256 amount) external;

    /// @notice Allows an agent to claim all their pending fee balance for `token`.
    /// @param agentId Agent string ID; msg.sender must be the agent's current address.
    /// @param token ERC-20 token to claim.
    function claimAgentFees(string calldata agentId, address token) external;

    /// @notice Withdraws accumulated protocol fees to `to`.
    /// @param token ERC-20 token to withdraw.
    /// @param amount Amount to withdraw; use type(uint256).max for full balance.
    /// @param to Recipient address; must be non-zero.
    function withdrawProtocolFees(address token, uint256 amount, address to) external;
}
