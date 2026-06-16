// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Campaign} from "../src/Campaign.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

/// @title CampaignTest
/// @notice Comprehensive unit tests for Campaign.sol using an isolated mock price feed.
contract CampaignTest is Test {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant ETH_USD_PRICE = 2000e8; // $2,000.00 (8 decimals)
    uint256 internal constant TARGET_USD = 100e8; // $100.00 goal
    uint256 internal constant MIN_CONTRIBUTION_USD = 10e8; // $10.00 minimum
    uint256 internal constant CAMPAIGN_DURATION = 1 days;

    /// @dev Minimum ETH to satisfy the $10 USD floor at $2,000/ETH.
    uint256 internal constant MIN_FUNDING_WEI = 5e15; // 0.005 ETH => $10.00

    /// @dev A valid contribution above the minimum used across happy-path tests.
    uint256 internal constant VALID_FUNDING_WEI = 1e16; // 0.01 ETH => $20.00

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    Campaign internal campaign;
    MockV3Aggregator internal priceFeed;

    address internal funder = makeAddr("funder");
    address internal secondFunder = makeAddr("secondFunder");

    /*//////////////////////////////////////////////////////////////
                                 SETUP
    //////////////////////////////////////////////////////////////*/

    function setUp() public {
        priceFeed = new MockV3Aggregator(int256(ETH_USD_PRICE));

        campaign = new Campaign(
            address(this),
            TARGET_USD,
            MIN_CONTRIBUTION_USD,
            CAMPAIGN_DURATION,
            address(priceFeed)
        );
    }

    /*//////////////////////////////////////////////////////////////
                              HELPERS
    //////////////////////////////////////////////////////////////*/

    function _usdValue(uint256 ethAmount) internal pure returns (uint256) {
        return (ethAmount * ETH_USD_PRICE) / 1e18;
    }

    function _fundAs(address contributor, uint256 amount) internal {
        vm.deal(contributor, amount);
        vm.prank(contributor);
        campaign.fund{value: amount}();
    }

    function _warpPastDeadline() internal {
        vm.warp(campaign.getStartTime() + campaign.getDuration() + 1);
    }

    /*//////////////////////////////////////////////////////////////
                           REQUIRED TESTS
    //////////////////////////////////////////////////////////////*/

    function test__FundRevertsIfMinContributionNotMet() public {
        vm.expectRevert(Campaign.Campaign__NotEnoughETH.selector);
        campaign.fund{value: 0}();

        vm.deal(funder, 1 wei);
        vm.prank(funder);
        vm.expectRevert(Campaign.Campaign__NotEnoughETH.selector);
        campaign.fund{value: 1 wei}();

        uint256 belowMinimumWei = MIN_FUNDING_WEI - 1;
        vm.deal(funder, belowMinimumWei);
        vm.prank(funder);
        vm.expectRevert(Campaign.Campaign__NotEnoughETH.selector);
        campaign.fund{value: belowMinimumWei}();
    }

    function test__FundUpdatesStateCorrectly() public {
        uint256 expectedUsd = _usdValue(VALID_FUNDING_WEI);

        vm.expectEmit(true, false, false, true, address(campaign));
        emit Campaign.Funded(funder, VALID_FUNDING_WEI, expectedUsd);

        _fundAs(funder, VALID_FUNDING_WEI);

        (uint256 ethContributed, uint256 usdContributed) = campaign.getContribution(funder);
        assertEq(ethContributed, VALID_FUNDING_WEI, "contributor ETH balance mismatch");
        assertEq(usdContributed, expectedUsd, "contributor USD balance mismatch");
        assertEq(campaign.getTotalEthRaised(), VALID_FUNDING_WEI, "total ETH raised mismatch");
        assertEq(campaign.getTotalUsdRaised(), expectedUsd, "total USD raised mismatch");
        assertEq(address(campaign).balance, VALID_FUNDING_WEI, "contract ETH balance mismatch");
    }

    function test__FundRevertsAfterDeadline() public {
        _fundAs(funder, VALID_FUNDING_WEI);
        _warpPastDeadline();

        vm.deal(secondFunder, VALID_FUNDING_WEI);
        vm.prank(secondFunder);
        vm.expectRevert(Campaign.Campaign__DeadlinePassed.selector);
        campaign.fund{value: VALID_FUNDING_WEI}();
    }

    function test__RefundRevertsBeforeDeadline() public {
        _fundAs(funder, VALID_FUNDING_WEI);

        vm.prank(funder);
        vm.expectRevert(Campaign.Campaign__DeadlineNotPassed.selector);
        campaign.refund();
    }

    function test__RefundWorksOnFailure() public {
        _fundAs(funder, VALID_FUNDING_WEI);

        assertFalse(campaign.isGoalMet(), "goal should not be met before deadline");
        _warpPastDeadline();
        assertTrue(campaign.hasDeadlinePassed(), "deadline should have passed");
        assertFalse(campaign.isGoalMet(), "goal should remain unmet after failed campaign");

        uint256 balanceBefore = funder.balance;

        vm.prank(funder);
        campaign.refund();

        assertEq(funder.balance, balanceBefore + VALID_FUNDING_WEI, "funder did not receive exact ETH refund");
        assertEq(address(campaign).balance, 0, "campaign should hold no ETH after full refund");

        (uint256 ethContributed, uint256 usdContributed) = campaign.getContribution(funder);
        assertEq(ethContributed, 0, "contributor ETH tracking should be zeroed");
        assertEq(usdContributed, 0, "contributor USD tracking should be zeroed");
        assertEq(campaign.getTotalEthRaised(), 0, "aggregate ETH should be zeroed");
        assertEq(campaign.getTotalUsdRaised(), 0, "aggregate USD should be zeroed");

        vm.prank(funder);
        vm.expectRevert(Campaign.Campaign__NothingToRefund.selector);
        campaign.refund();
    }

    /*//////////////////////////////////////////////////////////////
                        SUPPLEMENTARY COVERAGE
    //////////////////////////////////////////////////////////////*/

    function test__ConstructorSetsImmutableConfig() public view {
        assertEq(campaign.getTargetAmountUsd(), TARGET_USD);
        assertEq(campaign.getMinimumContributionUsd(), MIN_CONTRIBUTION_USD);
        assertEq(campaign.getDuration(), CAMPAIGN_DURATION);
        assertEq(campaign.getPriceFeed(), address(priceFeed));
        assertEq(campaign.getStartTime(), block.timestamp);
        assertEq(campaign.getCreator(), address(this));
    }

    function test__GetLatestPriceReturnsMockValue() public view {
        assertEq(campaign.getLatestPrice(), ETH_USD_PRICE);
    }

    function test__GetConversionRateMatchesManualCalculation() public view {
        assertEq(campaign.getConversionRate(VALID_FUNDING_WEI), _usdValue(VALID_FUNDING_WEI));
    }

    function test__FundRevertsOnStalePriceFeed() public {
        vm.warp(block.timestamp + 3 hours + 1);

        vm.deal(funder, VALID_FUNDING_WEI);
        vm.prank(funder);
        vm.expectRevert(Campaign.Campaign__StalePriceFeed.selector);
        campaign.fund{value: VALID_FUNDING_WEI}();
    }

    function test__RefundRevertsWhenGoalMet() public {
        uint256 goalFundingWei = (TARGET_USD * 1e18) / ETH_USD_PRICE;

        _fundAs(funder, goalFundingWei);
        assertTrue(campaign.isGoalMet());

        _warpPastDeadline();

        vm.prank(funder);
        vm.expectRevert(Campaign.Campaign__GoalMet.selector);
        campaign.refund();
    }

    function test__MultipleFundersAccumulateState() public {
        _fundAs(funder, VALID_FUNDING_WEI);
        _fundAs(secondFunder, VALID_FUNDING_WEI);

        uint256 expectedTotalEth = VALID_FUNDING_WEI * 2;
        uint256 expectedTotalUsd = _usdValue(VALID_FUNDING_WEI) * 2;

        assertEq(campaign.getTotalEthRaised(), expectedTotalEth);
        assertEq(campaign.getTotalUsdRaised(), expectedTotalUsd);
        assertEq(address(campaign).balance, expectedTotalEth);
    }
}
