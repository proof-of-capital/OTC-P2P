// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {console2} from "forge-std/console2.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {OTCDeployConfig} from "./OTCDeployConfig.s.sol";

contract DeployClientVaultScript is OTCDeployConfig {
    function run() external returns (address clientVault) {
        uint256 privateKey = _privateKey();
        address deployer = _deployer(privateKey);
        address factoryAddress = _existingFactoryAddress();
        address clientAddress = vm.envAddress("CLIENT_ADDRESS");
        _requireNonZero(clientAddress, "CLIENT_ADDRESS");

        vm.startBroadcast(privateKey);
        clientVault = OTCOperatorFactory(factoryAddress).deployClientVault(clientAddress);
        vm.stopBroadcast();

        console2.log("deployer", deployer);
        console2.log("OTCOperatorFactory", factoryAddress);
        console2.log("OTCClientVault", clientVault);
        console2.log("client", clientAddress);
    }
}
