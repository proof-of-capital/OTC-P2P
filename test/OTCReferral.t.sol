// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {OTCClientVaultLight} from "../src/OTCClientVaultLight.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
import {IOTCClientVaultLight} from "../src/interfaces/IOTCClientVaultLight.sol";
import {IOTCFactoryRegistryErrors} from "../src/interfaces/IOTCFactoryRegistryErrors.sol";

contract MockERC20R is ERC20 {
    constructor(string memory name_, string memory symbol_) ERC20(name_, symbol_) {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract OTCReferralTest is Test {
    address protocolOwner = address(0x1001);
    address protocolReceiver = address(0x1002);
    address operatorOwner = address(0x2001);
    address operatorAdmin = address(0x2002);
    address operatorReceiver = address(0x2003);
    address clientA = address(0x3001);
    address recipient = address(0x5001);

    OTCFactoryRegistry registry;
    OTCOperatorFactory factory;
    OTCClientVault vaultA;
    MockERC20R usdt;

    OTCTypes.ExtraFee emptyExtraFee = OTCTypes.ExtraFee({token: address(0), amount: 0, receiver: address(0)});

    function setUp() public {
        usdt = new MockERC20R("USD Tether", "USDT");
        registry = new OTCFactoryRegistry(protocolOwner, protocolReceiver, 1_000, 2_000);

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        vm.prank(operatorOwner);
        factory =
            OTCOperatorFactory(registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, config));

        vm.prank(operatorAdmin);
        vaultA = OTCClientVault(payable(factory.deployClientVault(clientA)));

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), true);
    }

    function testProtocolFeeForwardsImmediatelyToReceiver() public {
        uint256 protocolFee = _executeDeliveryWithProtocolFee(protocolReceiver);

        assertEq(usdt.balanceOf(protocolReceiver), protocolFee);
        assertEq(usdt.balanceOf(address(registry)), 0);
        assertEq(usdt.balanceOf(operatorReceiver), 9e18);
    }

    function testProtocolFeeUsesUpdatedReceiver() public {
        address newReceiver = address(0x7777);
        vm.prank(protocolOwner);
        registry.setProtocolFeeReceiver(newReceiver);

        uint256 protocolFee = _executeDeliveryWithProtocolFee(newReceiver);

        assertEq(usdt.balanceOf(protocolReceiver), 0);
        assertEq(usdt.balanceOf(newReceiver), protocolFee);
        assertEq(usdt.balanceOf(address(registry)), 0);
    }

    function testLightVaultProtocolFeeForwardsImmediatelyToReceiver() public {
        address lightClient = address(0x8888);
        OTCClientVaultLight lightVault = _deployLightVault(lightClient);

        usdt.mint(address(lightVault), 10_000e18);

        vm.prank(operatorAdmin);
        uint256 proposalId = lightVault.proposeDelivery(
            IOTCClientVaultLight.LightDeliveryProposalParams({
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 1_000e18,
                deliveryAddress: recipient,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
        vm.prank(lightClient);
        lightVault.acceptDeliveryProposal(proposalId);
        vm.prank(operatorAdmin);
        lightVault.executeDelivery(proposalId);

        assertEq(usdt.balanceOf(recipient), 1_000e18);
        assertEq(usdt.balanceOf(protocolReceiver), 1e18);
        assertEq(usdt.balanceOf(address(registry)), 0);
        assertEq(usdt.balanceOf(operatorReceiver), 9e18);
    }

    function testLightVaultAllowlist_BlocksTokenWorkflows() public {
        address lightClient = address(0x8888);
        OTCClientVaultLight lightVault = _deployLightVault(lightClient);
        MockERC20R unlisted = new MockERC20R("Unlisted", "NOPE");

        unlisted.mint(lightClient, 1_000);
        vm.startPrank(lightClient);
        unlisted.approve(address(lightVault), 1_000);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(unlisted)));
        lightVault.deposit(address(unlisted), 1_000);
        vm.stopPrank();

        vm.prank(operatorAdmin);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(unlisted)));
        lightVault.proposeLock(address(unlisted), block.timestamp + 1 days, block.timestamp + 1 days);

        vm.prank(operatorAdmin);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(unlisted)));
        lightVault.proposeDelivery(
            IOTCClientVaultLight.LightDeliveryProposalParams({
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(unlisted),
                amount: 100,
                deliveryAddress: recipient,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        OTCTypes.ExtraFee memory badExtraFee =
            OTCTypes.ExtraFee({token: address(unlisted), amount: 1, receiver: recipient});
        vm.prank(operatorAdmin);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(unlisted)));
        lightVault.proposeDelivery(
            IOTCClientVaultLight.LightDeliveryProposalParams({
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                deadline: block.timestamp + 1 days
            }),
            badExtraFee
        );
    }

    function testLightVaultAllowlist_RechecksApprovalAndExecutionAfterDelist() public {
        address lightClient = address(0x8888);
        OTCClientVaultLight lightVault = _deployLightVault(lightClient);
        usdt.mint(address(lightVault), 1_000);

        vm.prank(operatorAdmin);
        uint256 lockId = lightVault.proposeLock(address(usdt), block.timestamp + 10 days, block.timestamp + 1 days);
        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), false);

        vm.prank(lightClient);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(usdt)));
        lightVault.acceptLockProposal(lockId);

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), true);
        vm.prank(lightClient);
        lightVault.acceptLockProposal(lockId);

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), false);
        vm.prank(operatorAdmin);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(usdt)));
        lightVault.adminDecreaseLock(address(usdt), block.timestamp + 1 days);

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), true);
        vm.prank(operatorAdmin);
        uint256 deliveryId = lightVault.proposeDelivery(
            IOTCClientVaultLight.LightDeliveryProposalParams({
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), false);
        vm.prank(lightClient);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(usdt)));
        lightVault.acceptDeliveryProposal(deliveryId);

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), true);
        vm.prank(lightClient);
        lightVault.acceptDeliveryProposal(deliveryId);

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), false);
        vm.prank(operatorAdmin);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.TokenNotAllowed.selector, address(usdt)));
        lightVault.executeDelivery(deliveryId);
    }

    function testLightVaultAllowlist_AllowsWithdrawAndCancelAfterDelist() public {
        address lightClient = address(0x8888);
        OTCClientVaultLight lightVault = _deployLightVault(lightClient);
        usdt.mint(address(lightVault), 1_000);

        vm.prank(operatorAdmin);
        uint256 deliveryId = lightVault.proposeDelivery(
            IOTCClientVaultLight.LightDeliveryProposalParams({
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 100,
                deliveryAddress: recipient,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );

        vm.prank(protocolOwner);
        registry.setAllowedToken(address(usdt), false);

        vm.prank(lightClient);
        lightVault.withdraw(address(usdt), 100, recipient);
        assertEq(usdt.balanceOf(recipient), 100);

        vm.prank(operatorAdmin);
        lightVault.cancelDeliveryProposal(deliveryId);
        assertTrue(lightVault.deliveryProposals(deliveryId).cancelled);
    }

    function _executeDeliveryWithProtocolFee(address expectedReceiver) internal returns (uint256 protocolFee) {
        usdt.mint(address(vaultA), 10_000e18);

        vm.prank(operatorAdmin);
        uint256 proposalId = vaultA.proposeDelivery(
            OTCTypes.DeliveryProposalParams({
                useAllowanceCall: false,
                feeMode: OTCTypes.FeeMode.Gross,
                token: address(usdt),
                amount: 1_000e18,
                deliveryAddress: recipient,
                target: address(0),
                callData: "",
                expectedReceivedToken: address(0),
                minExpectedReceivedAmount: 0,
                deadline: block.timestamp + 1 days
            }),
            emptyExtraFee
        );
        vm.prank(clientA);
        vaultA.acceptDeliveryProposal(proposalId);
        vm.prank(operatorAdmin);
        vaultA.executeDelivery(proposalId);

        protocolFee = 1e18;
        assertEq(usdt.balanceOf(expectedReceiver), protocolFee);
    }

    function _deployLightVault(address lightClient) internal returns (OTCClientVaultLight lightVault) {
        OTCClientVaultLight lightImplementation = new OTCClientVaultLight();
        vm.prank(protocolOwner);
        registry.setClientVaultImplementation(address(lightImplementation));
        vm.prank(operatorAdmin);
        lightVault = OTCClientVaultLight(payable(factory.deployClientVault(lightClient)));
    }
}
