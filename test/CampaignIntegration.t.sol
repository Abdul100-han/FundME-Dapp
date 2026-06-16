// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Campaign} from "../src/Campaign.sol";
import {CampaignFactory} from "../src/CampaignFactory.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

/// @title CampaignIntegrationTest
/// @notice End-to-end integration tests for CampaignFactory deployment and milestone governance.
/// @dev Fork test: `forge test --fork-url $SEPOLIA_RPC_URL --match-test test__LiveOraclePriceFeedOnFork -vv`
contract CampaignIntegrationTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant ETH_USD_PRICE = 2000e8; // $2,000.00 (8 decimals)
    uint256 internal constant TARGET_USD = 100e8; // $100.00 goal
    uint256 internal constant MIN_CONTRIBUTION_USD = 10e8; // $10.00 minimum
    uint256 internal constant CAMPAIGN_DURATION = 1 days;
    uint256 internal constant VOTING_DURATION = 3 days;

    /// @dev Sepolia ETH/USD Chainlink AggregatorV3 feed.
    address internal constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    uint256 internal constant USER1_FUND_WEI = 2e16; // 0.02 ETH => $40.00
    uint256 internal constant USER2_FUND_WEI = 2e16; // 0.02 ETH => $40.00
    uint256 internal constant USER3_FUND_WEI = 1e16; // 0.01 ETH => $20.00
    uint256 internal constant TOTAL_FUNDED_WEI = USER1_FUND_WEI + USER2_FUND_WEI + USER3_FUND_WEI;

    uint256 internal constant MILESTONE_RELEASE_WEI = 15e15; // 0.015 ETH — partial release

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    CampaignFactory internal factory;
    MockV3Aggregator internal priceFeed;

    address internal creator = makeAddr("creator");
    address internal user1 = makeAddr("user1");
    address internal user2 = makeAddr("user2");
    address internal user3 = makeAddr("user3");

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        factory = new CampaignFactory();
        priceFeed = new MockV3Aggregator(int256(ETH_USD_PRICE));
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    function _usdValue(uint256 ethAmount) internal pure returns (uint256) {
        return (ethAmount * ETH_USD_PRICE) / 1e18;
    }

    function _fundAs(Campaign campaign, address contributor, uint256 amount) internal {
        vm.deal(contributor, amount);
        vm.prank(contributor);
        campaign.fund{value: amount}();
    }

    function _deployCampaignViaFactory() internal returns (Campaign campaign) {
        vm.prank(creator);
        factory.createCampaign(TARGET_USD, CAMPAIGN_DURATION, MIN_CONTRIBUTION_USD, address(priceFeed));

        address[] memory deployedCampaigns = factory.getDeployedCampaigns();
        assertEq(deployedCampaigns.length, 1, "factory should track one campaign");

        address campaignAddress = deployedCampaigns[0];
        assertTrue(factory.getCampaignStatus(campaignAddress), "campaign should be factory-verified");

        campaign = Campaign(payable(campaignAddress));
        assertEq(campaign.getCreator(), creator, "creator should be the factory caller");
    }

    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/

    function test__FullCampaignSuccessLifecycle() public {
        Campaign campaign = _deployCampaignViaFactory();

        _fundAs(campaign, user1, USER1_FUND_WEI);
        _fundAs(campaign, user2, USER2_FUND_WEI);
        _fundAs(campaign, user3, USER3_FUND_WEI);

        assertTrue(campaign.isGoalMet(), "campaign should meet USD funding goal");
        assertEq(campaign.getTotalEthRaised(), TOTAL_FUNDED_WEI, "total ETH raised mismatch");
        assertEq(campaign.getTotalUsdRaised(), _usdValue(TOTAL_FUNDED_WEI), "total USD raised mismatch");
        assertEq(address(campaign).balance, TOTAL_FUNDED_WEI, "campaign ETH balance mismatch");

        vm.warp(campaign.getStartTime() + campaign.getDuration() + 1);
        assertTrue(campaign.hasDeadlinePassed(), "funding deadline should have elapsed");

        vm.prank(creator);
        campaign.proposeMilestone("Deliver MVP prototype", MILESTONE_RELEASE_WEI, VOTING_DURATION);

        (
            ,
            uint256 amountRequested,
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 votingDeadline,
            bool executed
        ) = campaign.s_milestones(0);

        assertEq(amountRequested, MILESTONE_RELEASE_WEI, "milestone amount mismatch");
        assertEq(votesFor, 0, "votesFor should start at zero");
        assertEq(votesAgainst, 0, "votesAgainst should start at zero");
        assertEq(votingDeadline, block.timestamp + VOTING_DURATION, "voting deadline mismatch");
        assertFalse(executed, "milestone should not be executed yet");

        vm.prank(user1);
        campaign.voteOnMilestone(0, true);

        vm.prank(user2);
        campaign.voteOnMilestone(0, true);

        vm.prank(user3);
        campaign.voteOnMilestone(0, false);

        (,, votesFor, votesAgainst,,) = campaign.s_milestones(0);

        assertEq(votesFor, USER1_FUND_WEI + USER2_FUND_WEI, "votesFor should equal combined supporter ETH weight");
        assertEq(votesAgainst, USER3_FUND_WEI, "votesAgainst should equal opponent ETH weight");
        assertGt(votesFor, votesAgainst, "milestone should have majority support");

        assertTrue(campaign.s_milestoneVotes(0, user1), "user1 vote flag should be set");
        assertTrue(campaign.s_milestoneVotes(0, user2), "user2 vote flag should be set");
        assertTrue(campaign.s_milestoneVotes(0, user3), "user3 vote flag should be set");

        vm.warp(votingDeadline + 1);

        uint256 creatorBalanceBefore = creator.balance;
        uint256 campaignBalanceBefore = address(campaign).balance;

        vm.prank(creator);
        campaign.executeMilestone(0);

        assertEq(creator.balance, creatorBalanceBefore + MILESTONE_RELEASE_WEI, "creator payout mismatch");
        assertEq(
            address(campaign).balance,
            campaignBalanceBefore - MILESTONE_RELEASE_WEI,
            "campaign balance should decrease by milestone amount"
        );

        (,,,,, executed) = campaign.s_milestones(0);
        assertTrue(executed, "milestone should be marked executed");
    }

    function test__LiveOraclePriceFeedOnFork() public {
        // Preferred: forge test --fork-url $SEPOLIA_RPC_URL --match-test test__LiveOraclePriceFeedOnFork -vv
        // Alternative: set SEPOLIA_RPC_URL in .env and run this test in isolation.
        if (block.chainid != 11_155_111) {
            string memory rpcUrl = vm.envOr("SEPOLIA_RPC_URL", string(""));
            if (bytes(rpcUrl).length == 0) {
                vm.skip(true);
            }
            vm.createSelectFork(rpcUrl);
        }

        assertEq(block.chainid, 11_155_111, "fork must target Sepolia for live Chainlink feed");

        Campaign campaign = new Campaign(
            creator,
            TARGET_USD,
            MIN_CONTRIBUTION_USD,
            CAMPAIGN_DURATION,
            SEPOLIA_ETH_USD_FEED
        );

        uint256 livePrice = campaign.getLatestPrice();
        assertGt(livePrice, 100e8, "live ETH/USD price should exceed $100");
        assertLt(livePrice, 1_000_000e8, "live ETH/USD price should be below $1,000,000");

        uint256 oneEthUsd = campaign.getConversionRate(1 ether);
        assertEq(oneEthUsd, livePrice, "1 ETH conversion should equal the live oracle price");

        uint256 halfEthUsd = campaign.getConversionRate(0.5 ether);
        assertEq(halfEthUsd, livePrice / 2, "0.5 ETH conversion should be half the live price");

        uint256 minFundingWei = (MIN_CONTRIBUTION_USD * 1e18) / livePrice;
        if (minFundingWei > 0) {
            minFundingWei -= 1;
        }

        vm.deal(user1, minFundingWei);
        vm.prank(user1);
        vm.expectRevert(Campaign.Campaign__NotEnoughETH.selector);
        campaign.fund{value: minFundingWei}();

        uint256 validFundingWei = ((MIN_CONTRIBUTION_USD * 1e18) / livePrice) + 1 wei;
        vm.deal(user1, validFundingWei);
        vm.prank(user1);
        campaign.fund{value: validFundingWei}();

        (uint256 ethContributed, uint256 usdContributed) = campaign.getContribution(user1);
        assertEq(ethContributed, validFundingWei, "fork-funded ETH contribution mismatch");
        assertGe(usdContributed, MIN_CONTRIBUTION_USD, "fork-funded USD value should meet minimum");
    }
}
