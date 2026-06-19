// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {console2} from "forge-std/console2.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {OTCClientVaultLight} from "../src/OTCClientVaultLight.sol";
import {OTCDeployConfig} from "./OTCDeployConfig.s.sol";

contract DeployOTCProtocolScript is OTCDeployConfig {
    function run() external returns (OTCFactoryRegistry registry, address operatorFactory, address clientVault) {
        uint256 privateKey = _privateKey();
        address deployer = _deployer(privateKey);
        RegistryConfig memory registryConfig = _registryConfig();
        FactoryConfig memory factoryConfig = _factoryConfig();
        AgentConfig memory agentConfig = _agentConfig();
        VaultConfig memory vaultConfig = _vaultConfig();

        _requireOperatorOwner(deployer, factoryConfig.operatorOwner);

        bool shouldRegisterAgent = _isNonEmptyString(agentConfig.agentId);
        if (registryConfig.useLightVault) {
            _requireProtocolOwner(deployer, registryConfig.protocolOwner, "USE_LIGHT_VAULT");
        }
        if (shouldRegisterAgent) {
            _requireProtocolOwner(deployer, registryConfig.protocolOwner, "AGENT_ID");
            _requireNonZero(agentConfig.agentAddress, "AGENT_ADDRESS");
        }

        vm.startBroadcast(privateKey);

        registry = new OTCFactoryRegistry(
            registryConfig.protocolOwner,
            registryConfig.protocolFeeReceiver,
            registryConfig.defaultDeliveryOnlyProtocolFeeShareBps,
            registryConfig.defaultOtherProtocolFeeShareBps
        );

        if (registryConfig.useLightVault) {
            OTCClientVaultLight lightImplementation = new OTCClientVaultLight();
            registry.setClientVaultImplementation(address(lightImplementation));
            console2.log("OTCClientVaultLight implementation", address(lightImplementation));
        }

        if (shouldRegisterAgent) {
            registry.registerAgent(agentConfig.agentId, agentConfig.agentAddress, agentConfig.agentFeeBps);
            console2.log("agentId", agentConfig.agentId);
            console2.log("agentAddress", agentConfig.agentAddress);
            console2.log("agentFeeBps", agentConfig.agentFeeBps);
        }

        operatorFactory = registry.deployOperatorFactory(
            factoryConfig.operatorOwner,
            factoryConfig.operatorAdmin,
            factoryConfig.operatorFeeReceiver,
            factoryConfig.feeConfig,
            factoryConfig.agentId
        );

        if (vaultConfig.deployClientVault) {
            clientVault = OTCOperatorFactory(operatorFactory).deployClientVault(vaultConfig.clientAddress);
        }

        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("OTCFactoryRegistry", address(registry));
        console2.log("clientVaultImplementation", registry.clientVaultImplementation());
        console2.log("OTCOperatorFactory", operatorFactory);
        if (vaultConfig.deployClientVault) {
            console2.log("OTCClientVault", clientVault);
            console2.log("client", vaultConfig.clientAddress);
        }
    }
}
