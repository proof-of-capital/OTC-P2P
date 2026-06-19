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
        VaultConfig memory vaultConfig = _vaultConfig();

        _requireOperatorOwner(deployer, factoryConfig.operatorOwner);

        if (registryConfig.useLightVault) {
            _requireProtocolOwner(deployer, registryConfig.protocolOwner, "USE_LIGHT_VAULT");
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

        operatorFactory = registry.deployOperatorFactory(
            factoryConfig.operatorOwner,
            factoryConfig.operatorAdmin,
            factoryConfig.operatorFeeReceiver,
            factoryConfig.feeConfig
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
