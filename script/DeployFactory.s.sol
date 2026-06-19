// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {console2} from "forge-std/console2.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCDeployConfig} from "./OTCDeployConfig.s.sol";

contract DeployFactoryScript is OTCDeployConfig {
    function run() external returns (address operatorFactory) {
        uint256 privateKey = _privateKey();
        address deployer = _deployer(privateKey);
        OTCFactoryRegistry registry = OTCFactoryRegistry(_existingRegistryAddress());
        FactoryConfig memory config = _factoryConfig();

        vm.startBroadcast(privateKey);
        operatorFactory = registry.deployOperatorFactory(
            config.operatorOwner, config.operatorAdmin, config.operatorFeeReceiver, config.feeConfig
        );
        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("OTCFactoryRegistry", address(registry));
        console2.log("OTCOperatorFactory", operatorFactory);
    }
}
