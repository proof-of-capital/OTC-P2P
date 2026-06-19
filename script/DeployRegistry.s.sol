// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {console2} from "forge-std/console2.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCClientVaultLight} from "../src/OTCClientVaultLight.sol";
import {OTCDeployConfig} from "./OTCDeployConfig.s.sol";

contract DeployRegistryScript is OTCDeployConfig {
    function run() external returns (OTCFactoryRegistry registry) {
        uint256 privateKey = _privateKey();
        address deployer = _deployer(privateKey);
        RegistryConfig memory config = _registryConfig();

        vm.startBroadcast(privateKey);
        registry = new OTCFactoryRegistry(
            config.protocolOwner,
            config.protocolFeeReceiver,
            config.defaultDeliveryOnlyProtocolFeeShareBps,
            config.defaultOtherProtocolFeeShareBps
        );

        if (config.useLightVault) {
            _requireProtocolOwner(deployer, config.protocolOwner, "USE_LIGHT_VAULT");
            OTCClientVaultLight lightImplementation = new OTCClientVaultLight();
            registry.setClientVaultImplementation(address(lightImplementation));
            console2.log("OTCClientVaultLight implementation", address(lightImplementation));
        }

        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("OTCFactoryRegistry", address(registry));
        console2.log("clientVaultImplementation", registry.clientVaultImplementation());
    }
}
