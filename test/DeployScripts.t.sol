// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {OTCDeployConfig} from "../script/OTCDeployConfig.s.sol";

contract OTCDeployConfigHarness is OTCDeployConfig {
    function requireNonZero(address value, string memory name) external pure {
        _requireNonZero(value, name);
    }

    function toUint16(uint256 value, string memory name) external pure returns (uint16) {
        return _toUint16(value, name);
    }
}

contract DeployScriptsTest is Test {
    OTCDeployConfigHarness private harness;

    function setUp() public {
        harness = new OTCDeployConfigHarness();
    }

    function testRequireNonZeroRevertsForZeroAddress() public {
        vm.expectRevert(bytes("TEST_ADDRESS must not be zero"));
        harness.requireNonZero(address(0), "TEST_ADDRESS");
    }

    function testToUint16RejectsValuesAboveUint16Max() public {
        vm.expectRevert(bytes("TEST_BPS must fit uint16"));
        harness.toUint16(uint256(type(uint16).max) + 1, "TEST_BPS");
    }

    function testToUint16ReturnsValidValue() public view {
        assertEq(harness.toUint16(2_500, "TEST_BPS"), 2_500);
    }
}
