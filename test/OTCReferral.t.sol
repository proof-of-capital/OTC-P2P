// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {OTCTypes} from "../src/types/OTCTypes.sol";
import {OTCClientVault} from "../src/OTCClientVault.sol";
import {OTCFactoryRegistry} from "../src/OTCFactoryRegistry.sol";
import {OTCOperatorFactory} from "../src/OTCOperatorFactory.sol";
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
    address agentAddr = address(0x6001);

    string constant AGENT_ID = "partner1";

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
        factory = OTCOperatorFactory(
            registry.deployOperatorFactory(operatorOwner, operatorAdmin, operatorReceiver, config, "")
        );

        vm.prank(operatorAdmin);
        vaultA = OTCClientVault(payable(factory.deployClientVault(clientA)));
    }

    // ── registerAgent ─────────────────────────────────────────────────────────────

    function testRegisterAgent() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);
        (address addr, uint16 bps) = registry.agents(AGENT_ID);
        assertEq(addr, agentAddr);
        assertEq(bps, 500);
    }

    function testRegisterAgent_RevertsOnEmptyId() public {
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.EmptyAgentId.selector));
        registry.registerAgent("", agentAddr, 500);
    }

    function testRegisterAgent_RevertsOnZeroAddress() public {
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.InvalidAddress.selector));
        registry.registerAgent(AGENT_ID, address(0), 500);
    }

    function testRegisterAgent_RevertsOnDuplicate() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentAlreadyRegistered.selector, AGENT_ID));
        registry.registerAgent(AGENT_ID, agentAddr, 600);
    }

    function testRegisterAgent_RevertsBelowMin() public {
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentFeeOutOfRange.selector, 50, 100, 8_000));
        registry.registerAgent(AGENT_ID, agentAddr, 50);
    }

    function testRegisterAgent_RevertsAboveMax() public {
        vm.prank(protocolOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentFeeOutOfRange.selector, 9_000, 100, 8_000)
        );
        registry.registerAgent(AGENT_ID, agentAddr, 9_000);
    }

    // ── increaseAgentFee ──────────────────────────────────────────────────────────

    function testIncreaseAgentFee() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);
        vm.prank(protocolOwner);
        registry.increaseAgentFee(AGENT_ID, 1_000);
        (, uint16 bps) = registry.agents(AGENT_ID);
        assertEq(bps, 1_000);
    }

    function testIncreaseAgentFee_RevertsOnDecrease() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 1_000);
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentFeeNotHigher.selector, 500, 1_000));
        registry.increaseAgentFee(AGENT_ID, 500);
    }

    function testIncreaseAgentFee_RevertsOnSameValue() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 1_000);
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentFeeNotHigher.selector, 1_000, 1_000));
        registry.increaseAgentFee(AGENT_ID, 1_000);
    }

    function testIncreaseAgentFee_RevertsOnUnregistered() public {
        vm.prank(protocolOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentNotRegistered.selector, AGENT_ID));
        registry.increaseAgentFee(AGENT_ID, 1_000);
    }

    function testIncreaseAgentFee_RevertsAboveMax() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 1_000);
        vm.prank(protocolOwner);
        vm.expectRevert(
            abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentFeeOutOfRange.selector, 9_000, 100, 8_000)
        );
        registry.increaseAgentFee(AGENT_ID, 9_000);
    }

    // ── setAgentAddress ───────────────────────────────────────────────────────────

    function testSetAgentAddress() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);

        address newAddr = address(0x7777);
        vm.prank(agentAddr);
        registry.setAgentAddress(AGENT_ID, newAddr);

        (address addr,) = registry.agents(AGENT_ID);
        assertEq(addr, newAddr);
    }

    function testSetAgentAddress_RevertsIfNotCurrentAddress() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);

        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.NotAgentOwner.selector));
        registry.setAgentAddress(AGENT_ID, address(0x7777));
    }

    function testSetAgentAddress_RevertsOnZeroNewAddress() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);

        vm.prank(agentAddr);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.InvalidAddress.selector));
        registry.setAgentAddress(AGENT_ID, address(0));
    }

    // ── deployOperatorFactory with agent ─────────────────────────────────────────

    function testDeployFactoryWithAgent() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 1_000);

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        address newOwner = address(0x7001);
        vm.prank(newOwner);
        address newFactory =
            registry.deployOperatorFactory(newOwner, address(0x7002), address(0x7003), config, AGENT_ID);

        assertEq(registry.factoryAgentId(newFactory), AGENT_ID);
    }

    function testDeployFactory_NoAgent_EmptyMapping() public {
        assertEq(registry.factoryAgentId(address(factory)), "");
    }

    function testDeployFactory_RevertsOnUnregisteredAgent() public {
        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        address newOwner = address(0x7001);
        vm.prank(newOwner);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.AgentNotRegistered.selector, AGENT_ID));
        registry.deployOperatorFactory(newOwner, address(0x7002), address(0x7003), config, AGENT_ID);
    }

    // ── fee accumulation & distribution ──────────────────────────────────────────

    function testProtocolFeeAccumulatesInRegistry_NoAgent() public {
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

        // deliveryFeeBps=100 → operatorFee=10e18
        // protocolShareBps=1_000 (DeliveryOnly) → protocolFee=1e18
        assertEq(registry.protocolPendingFees(address(usdt)), 1e18);
    }

    function testAgentClaimsReferralFee() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 2_000); // 20% of protocol fee goes to agent

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        address agentFactoryOwner = address(0x8001);
        vm.prank(agentFactoryOwner);
        OTCOperatorFactory agentFactory = OTCOperatorFactory(
            registry.deployOperatorFactory(agentFactoryOwner, address(0x8002), address(0x8003), config, AGENT_ID)
        );

        vm.prank(address(0x8002));
        OTCClientVault agentVault = OTCClientVault(payable(agentFactory.deployClientVault(address(0x8004))));

        usdt.mint(address(agentVault), 10_000e18);

        vm.prank(address(0x8002));
        uint256 proposalId = agentVault.proposeDelivery(
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
        vm.prank(address(0x8004));
        agentVault.acceptDeliveryProposal(proposalId);
        vm.prank(address(0x8002));
        agentVault.executeDelivery(proposalId);

        // deliveryFeeBps=100 → operatorFee=10e18
        // protocolShareBps=1_000 → protocolFee=1e18
        // agentFeeBps=2_000 (20%) → agentShare=0.2e18, protocolShare=0.8e18
        uint256 expectedAgentShare = 0.2e18;
        uint256 expectedProtocolShare = 0.8e18;

        assertEq(registry.agentPendingFees(AGENT_ID, address(usdt)), expectedAgentShare);
        assertEq(registry.protocolPendingFees(address(usdt)), expectedProtocolShare);

        vm.prank(agentAddr);
        registry.claimAgentFees(AGENT_ID, address(usdt));
        assertEq(usdt.balanceOf(agentAddr), expectedAgentShare);
        assertEq(registry.agentPendingFees(AGENT_ID, address(usdt)), 0);
    }

    function testAgentClaimsAfterAddressUpdate() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 2_000);

        OTCTypes.OperatorFeeConfig memory config =
            OTCTypes.OperatorFeeConfig({takerFeeBps: 100, deliveryFeeBps: 100, openP2PFeeBps: 50});
        address agentFactoryOwner = address(0x8001);
        vm.prank(agentFactoryOwner);
        OTCOperatorFactory agentFactory = OTCOperatorFactory(
            registry.deployOperatorFactory(agentFactoryOwner, address(0x8002), address(0x8003), config, AGENT_ID)
        );
        vm.prank(address(0x8002));
        OTCClientVault agentVault = OTCClientVault(payable(agentFactory.deployClientVault(address(0x8004))));
        usdt.mint(address(agentVault), 10_000e18);

        // Execute a delivery to accumulate fees
        vm.prank(address(0x8002));
        uint256 proposalId = agentVault.proposeDelivery(
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
        vm.prank(address(0x8004));
        agentVault.acceptDeliveryProposal(proposalId);
        vm.prank(address(0x8002));
        agentVault.executeDelivery(proposalId);

        // Agent updates their address
        address newAgentAddr = address(0x9999);
        vm.prank(agentAddr);
        registry.setAgentAddress(AGENT_ID, newAgentAddr);

        // Old address can no longer claim
        vm.prank(agentAddr);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.NotAgentOwner.selector));
        registry.claimAgentFees(AGENT_ID, address(usdt));

        // New address claims successfully
        vm.prank(newAgentAddr);
        registry.claimAgentFees(AGENT_ID, address(usdt));
        assertEq(usdt.balanceOf(newAgentAddr), 0.2e18);
    }

    function testProtocolWithdrawsNetFee() public {
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

        uint256 protocolBalance = registry.protocolPendingFees(address(usdt));
        assertTrue(protocolBalance > 0);

        vm.prank(protocolOwner);
        registry.withdrawProtocolFees(address(usdt), type(uint256).max, protocolReceiver);
        assertEq(usdt.balanceOf(protocolReceiver), protocolBalance);
        assertEq(registry.protocolPendingFees(address(usdt)), 0);
    }

    function testClaimAgentFees_RevertsOnNoPending() public {
        vm.prank(protocolOwner);
        registry.registerAgent(AGENT_ID, agentAddr, 500);
        vm.prank(agentAddr);
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.NoPendingFees.selector));
        registry.claimAgentFees(AGENT_ID, address(usdt));
    }

    function testReceiveProtocolFee_RevertsFromNonVault() public {
        vm.expectRevert(abi.encodeWithSelector(IOTCFactoryRegistryErrors.NotVault.selector));
        registry.receiveProtocolFee(address(usdt), 1e18);
    }
}
