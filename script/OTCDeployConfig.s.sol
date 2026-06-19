// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";

abstract contract OTCDeployConfig is Script {
    struct RegistryConfig {
        address protocolOwner;
        address protocolFeeReceiver;
        uint16 defaultDeliveryOnlyProtocolFeeShareBps;
        uint16 defaultOtherProtocolFeeShareBps;
        bool useLightVault;
    }

    struct FactoryConfig {
        address operatorOwner;
        address operatorAdmin;
        address operatorFeeReceiver;
        OTCTypes.OperatorFeeConfig feeConfig;
        string agentId;
    }

    struct AgentConfig {
        string agentId;
        address agentAddress;
        uint16 agentFeeBps;
    }

    struct VaultConfig {
        bool deployClientVault;
        address clientAddress;
    }

    function _privateKey() internal view returns (uint256) {
        return vm.envUint("PRIVATE_KEY");
    }

    function _deployer(uint256 privateKey) internal pure returns (address) {
        return vm.addr(privateKey);
    }

    function _registryConfig() internal view returns (RegistryConfig memory config) {
        config = RegistryConfig({
            protocolOwner: vm.envAddress("PROTOCOL_OWNER"),
            protocolFeeReceiver: vm.envAddress("PROTOCOL_FEE_RECEIVER"),
            defaultDeliveryOnlyProtocolFeeShareBps: _toUint16(
                vm.envUint("DEFAULT_DELIVERY_ONLY_PROTOCOL_FEE_SHARE_BPS"),
                "DEFAULT_DELIVERY_ONLY_PROTOCOL_FEE_SHARE_BPS"
            ),
            defaultOtherProtocolFeeShareBps: _toUint16(
                vm.envUint("DEFAULT_OTHER_PROTOCOL_FEE_SHARE_BPS"), "DEFAULT_OTHER_PROTOCOL_FEE_SHARE_BPS"
            ),
            useLightVault: vm.envOr("USE_LIGHT_VAULT", false)
        });

        _requireNonZero(config.protocolOwner, "PROTOCOL_OWNER");
        _requireNonZero(config.protocolFeeReceiver, "PROTOCOL_FEE_RECEIVER");
    }

    function _factoryConfig() internal view returns (FactoryConfig memory config) {
        config = FactoryConfig({
            operatorOwner: vm.envAddress("OPERATOR_OWNER"),
            operatorAdmin: vm.envAddress("OPERATOR_ADMIN"),
            operatorFeeReceiver: vm.envAddress("OPERATOR_FEE_RECEIVER"),
            feeConfig: OTCTypes.OperatorFeeConfig({
                takerFeeBps: _toUint16(vm.envUint("TAKER_FEE_BPS"), "TAKER_FEE_BPS"),
                deliveryFeeBps: _toUint16(vm.envUint("DELIVERY_FEE_BPS"), "DELIVERY_FEE_BPS"),
                openP2PFeeBps: _toUint16(vm.envUint("OPEN_P2P_FEE_BPS"), "OPEN_P2P_FEE_BPS")
            }),
            agentId: vm.envOr("AGENT_ID", string(""))
        });

        _requireNonZero(config.operatorOwner, "OPERATOR_OWNER");
        _requireNonZero(config.operatorAdmin, "OPERATOR_ADMIN");
        _requireNonZero(config.operatorFeeReceiver, "OPERATOR_FEE_RECEIVER");
    }

    function _agentConfig() internal view returns (AgentConfig memory config) {
        config = AgentConfig({
            agentId: vm.envOr("AGENT_ID", string("")),
            agentAddress: vm.envOr("AGENT_ADDRESS", address(0)),
            agentFeeBps: _toUint16(vm.envOr("AGENT_FEE_BPS", uint256(0)), "AGENT_FEE_BPS")
        });
    }

    function _vaultConfig() internal view returns (VaultConfig memory config) {
        config.deployClientVault = vm.envOr("DEPLOY_CLIENT_VAULT", false);
        config.clientAddress = vm.envOr("CLIENT_ADDRESS", address(0));

        if (config.deployClientVault) {
            _requireNonZero(config.clientAddress, "CLIENT_ADDRESS");
        }
    }

    function _existingRegistryAddress() internal view returns (address registry) {
        registry = vm.envAddress("REGISTRY_ADDRESS");
        _requireNonZero(registry, "REGISTRY_ADDRESS");
    }

    function _existingFactoryAddress() internal view returns (address factory) {
        factory = vm.envAddress("FACTORY_ADDRESS");
        _requireNonZero(factory, "FACTORY_ADDRESS");
    }

    function _requireOperatorOwner(address deployer, address operatorOwner) internal pure {
        require(deployer == operatorOwner, "OPERATOR_OWNER must match PRIVATE_KEY signer");
    }

    function _requireProtocolOwner(address deployer, address protocolOwner, string memory action) internal pure {
        require(deployer == protocolOwner, string.concat("PROTOCOL_OWNER must match PRIVATE_KEY signer for ", action));
    }

    function _requireNonZero(address value, string memory name) internal pure {
        require(value != address(0), string.concat(name, " must not be zero"));
    }

    function _toUint16(uint256 value, string memory name) internal pure returns (uint16) {
        require(value <= type(uint16).max, string.concat(name, " must fit uint16"));
        // forge-lint: disable-next-line(unsafe-typecast)
        return uint16(value);
    }

    function _isNonEmptyString(string memory value) internal pure returns (bool) {
        return bytes(value).length > 0;
    }
}
