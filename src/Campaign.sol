// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Campaign
/// @author FundMe DApp
/// @notice A gas-optimized crowdfunding campaign that validates contributions against a USD minimum via Chainlink.
/// @dev Uses immutables for deployment-time configuration, packed storage for aggregates, and custom errors throughout.
contract Campaign {
    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/

    /// @notice Per-contributor balances packed into a single storage slot.
    /// @dev uint128 supports up to ~3.4e20 wei (~340 billion ETH), far beyond practical campaign sizes.
    struct Contribution {
        uint128 ethAmount;
        uint128 usdAmount;
    }

    /// @notice Milestone proposal tracked for contributor-weighted governance.
    /// @dev Vote participation is tracked separately in `s_milestoneVotes` to avoid nested mappings in arrays.
    struct Milestone {
        string description;
        uint256 amountRequested;
        uint256 votesFor;
        uint256 votesAgainst;
        uint256 votingDeadline;
        bool executed;
    }

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error Campaign__DeadlinePassed();
    error Campaign__DeadlineNotPassed();
    error Campaign__GoalMet();
    error Campaign__NotEnoughETH();
    error Campaign__NothingToRefund();
    error Campaign__TransferFailed();
    error Campaign__InvalidPrice();
    error Campaign__StalePriceFeed();
    error Campaign__NotCreator();
    error Campaign__GoalNotMet();
    error Campaign__CampaignStillActive();
    error Campaign__InvalidMilestone();
    error Campaign__AlreadyVoted();
    error Campaign__VotingClosed();
    error Campaign__NoVotingWeight();
    error Campaign__VotingStillActive();
    error Campaign__MilestoneNotPassed();
    error Campaign__MilestoneAlreadyExecuted();
    error Campaign__InsufficientFunds();
    error Campaign__InvalidVotingDuration();
    error Campaign__InvalidMilestoneAmount();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a contributor funds the campaign.
    /// @param contributor The address that sent ETH.
    /// @param amountEth The amount of ETH contributed, in wei.
    /// @param amountUsd The USD value credited at funding time, with 8 decimals.
    event Funded(address indexed contributor, uint256 amountEth, uint256 amountUsd);

    /// @notice Emitted when the creator proposes a new milestone.
    event MilestoneProposed(uint256 indexed milestoneId, string description, uint256 amountRequested, uint256 votingDeadline);

    /// @notice Emitted when a contributor casts a weighted vote on a milestone.
    event MilestoneVoted(uint256 indexed milestoneId, address indexed voter, bool support, uint256 weight);

    /// @notice Emitted when a passed milestone releases ETH to the creator.
    event MilestoneExecuted(uint256 indexed milestoneId, address indexed creator, uint256 amountReleased);

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Maximum age of a Chainlink price update before it is considered stale.
    uint256 private constant STALE_PRICE_THRESHOLD = 3 hours;

    /// @notice Campaign creator; set once at deployment.
    address private immutable i_creator;

    /// @notice Funding goal denominated in USD with 8 decimals (Chainlink convention).
    uint256 private immutable i_targetAmountUsd;

    /// @notice Minimum contribution denominated in USD with 8 decimals.
    uint256 private immutable i_minimumContributionUsd;

    /// @notice Campaign duration in seconds, measured from deployment.
    uint256 private immutable i_duration;

    /// @notice Chainlink ETH/USD price feed.
    AggregatorV3Interface private immutable i_priceFeed;

    /// @notice Block timestamp recorded at contract deployment.
    uint256 private immutable i_startTime;

    /// @notice Aggregate USD raised, packed with aggregate ETH raised in slot 0.
    /// @dev uint128 is sufficient for realistic campaign totals while halving slot usage.
    uint128 private s_totalUsdRaised;

    /// @notice Aggregate ETH raised, packed with s_totalUsdRaised in slot 0.
    uint128 private s_totalEthRaised;

    /// @notice Tracks each contributor's ETH and USD balances in one slot per address.
    mapping(address => Contribution) private s_contributions;

    /// @notice Append-only registry of milestone proposals for post-funding governance.
    Milestone[] public s_milestones;

    /// @notice Tracks whether an address has voted on a specific milestone (milestoneId => voter => voted).
    mapping(uint256 => mapping(address => bool)) public s_milestoneVotes;

    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Restricts access to the campaign creator.
    modifier onlyCreator() {
        if (msg.sender != i_creator) {
            revert Campaign__NotCreator();
        }
        _;
    }

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new crowdfunding campaign.
    /// @param creator Address recorded as the campaign owner (factory passes the end-user caller).
    /// @param targetAmountUsd Funding goal in USD with 8 decimals (e.g. $5,000.00 => 5000e8).
    /// @param minimumContributionUsd Minimum per-transaction contribution in USD with 8 decimals.
    /// @param duration Campaign lifetime in seconds after deployment.
    /// @param priceFeed Address of the Chainlink ETH/USD AggregatorV3 feed.
    constructor(
        address creator,
        uint256 targetAmountUsd,
        uint256 minimumContributionUsd,
        uint256 duration,
        address priceFeed
    ) {
        i_creator = creator;
        i_targetAmountUsd = targetAmountUsd;
        i_minimumContributionUsd = minimumContributionUsd;
        i_duration = duration;
        i_priceFeed = AggregatorV3Interface(priceFeed);
        i_startTime = block.timestamp;
    }

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Accepts ETH from contributors after validating the USD value against the minimum.
    /// @dev Reverts if the deadline has passed or the USD value of msg.value is below the minimum.
    function fund() external payable {
        if (hasDeadlinePassed()) {
            revert Campaign__DeadlinePassed();
        }
        if (msg.value == 0) {
            revert Campaign__NotEnoughETH();
        }

        uint256 usdValue = getConversionRate(msg.value);
        if (usdValue < i_minimumContributionUsd) {
            revert Campaign__NotEnoughETH();
        }

        Contribution storage contribution = s_contributions[msg.sender];
        contribution.ethAmount += uint128(msg.value);
        contribution.usdAmount += uint128(usdValue);

        s_totalEthRaised += uint128(msg.value);
        s_totalUsdRaised += uint128(usdValue);

        emit Funded(msg.sender, msg.value, usdValue);
    }

    /// @notice Allows contributors to withdraw their ETH if the deadline passed without reaching the goal.
    /// @dev Follows Checks-Effects-Interactions: balances are zeroed before the external call.
    function refund() external {
        if (!hasDeadlinePassed()) {
            revert Campaign__DeadlineNotPassed();
        }
        if (isGoalMet()) {
            revert Campaign__GoalMet();
        }

        Contribution storage contribution = s_contributions[msg.sender];
        uint256 amountToRefund = contribution.ethAmount;
        if (amountToRefund == 0) {
            revert Campaign__NothingToRefund();
        }

        uint256 usdToRemove = contribution.usdAmount;

        // Effects — clear contributor and aggregate state before interaction
        delete s_contributions[msg.sender];
        s_totalEthRaised -= uint128(amountToRefund);
        s_totalUsdRaised -= uint128(usdToRemove);

        // Interaction
        (bool success,) = payable(msg.sender).call{value: amountToRefund}("");
        if (!success) {
            revert Campaign__TransferFailed();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        MILESTONE GOVERNANCE
    //////////////////////////////////////////////////////////////*/

    /// @notice Proposes a milestone for contributor voting after a successful campaign concludes.
    /// @param _description Human-readable summary of the milestone deliverable.
    /// @param _amountRequested ETH amount in wei requested for this milestone.
    /// @param _votingDuration Voting window in seconds, measured from proposal time.
    function proposeMilestone(
        string calldata _description,
        uint256 _amountRequested,
        uint256 _votingDuration
    ) external onlyCreator {
        if (!isGoalMet()) {
            revert Campaign__GoalNotMet();
        }
        if (!hasDeadlinePassed()) {
            revert Campaign__CampaignStillActive();
        }
        if (_amountRequested == 0) {
            revert Campaign__InvalidMilestoneAmount();
        }
        if (_votingDuration == 0) {
            revert Campaign__InvalidVotingDuration();
        }
        if (bytes(_description).length == 0) {
            revert Campaign__InvalidMilestone();
        }

        uint256 milestoneId = s_milestones.length;
        uint256 votingDeadline = block.timestamp + _votingDuration;

        s_milestones.push(
            Milestone({
                description: _description,
                amountRequested: _amountRequested,
                votesFor: 0,
                votesAgainst: 0,
                votingDeadline: votingDeadline,
                executed: false
            })
        );

        emit MilestoneProposed(milestoneId, _description, _amountRequested, votingDeadline);
    }

    /// @notice Casts a weighted vote on an active milestone using the caller's funded ETH balance.
    /// @param _milestoneId Index of the milestone in `s_milestones`.
    /// @param _support True to vote in favor; false to vote against.
    function voteOnMilestone(uint256 _milestoneId, bool _support) external {
        if (_milestoneId >= s_milestones.length) {
            revert Campaign__InvalidMilestone();
        }

        Milestone storage milestone = s_milestones[_milestoneId];

        if (block.timestamp > milestone.votingDeadline) {
            revert Campaign__VotingClosed();
        }
        if (s_milestoneVotes[_milestoneId][msg.sender]) {
            revert Campaign__AlreadyVoted();
        }

        uint256 votingWeight = s_contributions[msg.sender].ethAmount;
        if (votingWeight == 0) {
            revert Campaign__NoVotingWeight();
        }

        s_milestoneVotes[_milestoneId][msg.sender] = true;

        if (_support) {
            milestone.votesFor += votingWeight;
        } else {
            milestone.votesAgainst += votingWeight;
        }

        emit MilestoneVoted(_milestoneId, msg.sender, _support, votingWeight);
    }

    /// @notice Releases milestone funds to the creator after a successful contributor vote.
    /// @param _milestoneId Index of the milestone in `s_milestones`.
    /// @dev Follows Checks-Effects-Interactions: marks executed before the ETH transfer.
    function executeMilestone(uint256 _milestoneId) external onlyCreator {
        if (_milestoneId >= s_milestones.length) {
            revert Campaign__InvalidMilestone();
        }

        Milestone storage milestone = s_milestones[_milestoneId];

        if (milestone.executed) {
            revert Campaign__MilestoneAlreadyExecuted();
        }
        if (block.timestamp <= milestone.votingDeadline) {
            revert Campaign__VotingStillActive();
        }
        if (milestone.votesFor <= milestone.votesAgainst) {
            revert Campaign__MilestoneNotPassed();
        }

        uint256 amountToRelease = milestone.amountRequested;
        if (address(this).balance < amountToRelease) {
            revert Campaign__InsufficientFunds();
        }

        // Effects — prevent reentrancy before external transfer
        milestone.executed = true;

        // Interaction
        (bool success,) = payable(i_creator).call{value: amountToRelease}("");
        if (!success) {
            revert Campaign__TransferFailed();
        }

        emit MilestoneExecuted(_milestoneId, i_creator, amountToRelease);
    }

    /*//////////////////////////////////////////////////////////////
                           ORACLE HELPERS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns the latest ETH/USD price from Chainlink with 8 decimals.
    /// @return price The latest validated price answer.
    function getLatestPrice() public view returns (uint256 price) {
        (, int256 answer,, uint256 updatedAt,) = i_priceFeed.latestRoundData();

        if (answer <= 0) {
            revert Campaign__InvalidPrice();
        }
        if (block.timestamp - updatedAt > STALE_PRICE_THRESHOLD) {
            revert Campaign__StalePriceFeed();
        }

        return uint256(answer);
    }

    /// @notice Converts an ETH amount in wei to its USD equivalent using the Chainlink feed.
    /// @param ethAmount Amount of ETH in wei (18 decimals).
    /// @return usdAmount Equivalent USD value with 8 decimals.
    function getConversionRate(uint256 ethAmount) public view returns (uint256 usdAmount) {
        uint256 ethPrice = getLatestPrice();
        return (ethAmount * ethPrice) / 1e18;
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns whether the campaign deadline has elapsed.
    function hasDeadlinePassed() public view returns (bool) {
        return block.timestamp > i_startTime + i_duration;
    }

    /// @notice Returns whether the campaign has reached its USD funding goal.
    function isGoalMet() public view returns (bool) {
        return s_totalUsdRaised >= i_targetAmountUsd;
    }

    /// @notice Returns the campaign creator address.
    function getCreator() external view returns (address) {
        return i_creator;
    }

    /// @notice Returns the USD funding goal with 8 decimals.
    function getTargetAmountUsd() external view returns (uint256) {
        return i_targetAmountUsd;
    }

    /// @notice Returns the minimum USD contribution with 8 decimals.
    function getMinimumContributionUsd() external view returns (uint256) {
        return i_minimumContributionUsd;
    }

    /// @notice Returns the campaign duration in seconds.
    function getDuration() external view returns (uint256) {
        return i_duration;
    }

    /// @notice Returns the Chainlink price feed address.
    function getPriceFeed() external view returns (address) {
        return address(i_priceFeed);
    }

    /// @notice Returns the campaign start timestamp.
    function getStartTime() external view returns (uint256) {
        return i_startTime;
    }

    /// @notice Returns aggregate ETH raised in wei.
    function getTotalEthRaised() external view returns (uint256) {
        return s_totalEthRaised;
    }

    /// @notice Returns aggregate USD raised with 8 decimals.
    function getTotalUsdRaised() external view returns (uint256) {
        return s_totalUsdRaised;
    }

    /// @notice Returns a contributor's ETH and USD balances.
    /// @param contributor The address to query.
    /// @return ethAmount Contributed ETH in wei.
    /// @return usdAmount Credited USD with 8 decimals at funding time.
    function getContribution(address contributor) external view returns (uint256 ethAmount, uint256 usdAmount) {
        Contribution memory contribution = s_contributions[contributor];
        return (contribution.ethAmount, contribution.usdAmount);
    }
}

/// @title AggregatorV3Interface
/// @notice Minimal Chainlink price feed interface inlined to avoid external dependency setup.
interface AggregatorV3Interface {
    /// @notice Returns the number of decimals in the price answer.
    function decimals() external view returns (uint8);

    /// @notice Returns a description of the price feed.
    function description() external view returns (string memory);

    /// @notice Returns the version of the aggregator.
    function version() external view returns (uint256);

    /// @notice Returns round data for a specific round ID.
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );

    /// @notice Returns data for the latest completed round.
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}
