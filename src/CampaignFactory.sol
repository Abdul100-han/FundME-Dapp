// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Campaign} from "./Campaign.sol";

/// @title CampaignFactory
/// @author FundMe DApp
/// @notice Deploys and indexes authentic Campaign instances for frontend discovery and on-chain verification.
/// @dev Maintains an append-only registry and O(1) authenticity mapping for each deployed campaign.
contract CampaignFactory {
    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error CampaignFactory__ZeroAddress();
    error CampaignFactory__InvalidDuration();
    error CampaignFactory__InvalidTargetGoal();
    error CampaignFactory__InvalidMinContribution();

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when a new campaign is deployed through the factory.
    /// @param campaignAddress The address of the newly deployed Campaign contract.
    /// @param creator The address that initiated campaign creation.
    /// @param targetGoalUsd Funding goal in USD with 8 decimals.
    /// @param deadline Unix timestamp when the campaign funding window closes.
    event CampaignDeployed(
        address indexed campaignAddress,
        address indexed creator,
        uint256 targetGoalUsd,
        uint256 deadline
    );

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/

    /// @notice Append-only registry of every campaign deployed by this factory.
    address[] private s_deployedCampaigns;

    /// @notice O(1) authenticity check — true only for campaigns created via this factory.
    mapping(address => bool) private s_isVerifiedCampaign;

    /*//////////////////////////////////////////////////////////////
                            CORE FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys a new Campaign and registers it in the factory index.
    /// @param _targetGoalUsd Funding goal in USD with 8 decimals.
    /// @param _duration Campaign lifetime in seconds, measured from deployment.
    /// @param _minContributionUsd Minimum per-transaction contribution in USD with 8 decimals.
    /// @param _priceFeed Chainlink ETH/USD AggregatorV3 feed address.
    /// @return campaignAddress The address of the newly deployed Campaign instance.
    function createCampaign(
        uint256 _targetGoalUsd,
        uint256 _duration,
        uint256 _minContributionUsd,
        address _priceFeed
    ) external returns (address campaignAddress) {
        if (_priceFeed == address(0)) {
            revert CampaignFactory__ZeroAddress();
        }
        if (_duration == 0) {
            revert CampaignFactory__InvalidDuration();
        }
        if (_targetGoalUsd == 0) {
            revert CampaignFactory__InvalidTargetGoal();
        }
        if (_minContributionUsd == 0) {
            revert CampaignFactory__InvalidMinContribution();
        }

        uint256 deadline = block.timestamp + _duration;

        Campaign campaign = new Campaign(
            msg.sender,
            _targetGoalUsd,
            _minContributionUsd,
            _duration,
            _priceFeed
        );

        campaignAddress = address(campaign);

        s_deployedCampaigns.push(campaignAddress);
        s_isVerifiedCampaign[campaignAddress] = true;

        emit CampaignDeployed(campaignAddress, msg.sender, _targetGoalUsd, deadline);
    }

    /*//////////////////////////////////////////////////////////////
                            VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /// @notice Returns every campaign address deployed by this factory.
    /// @return campaigns The full registry array for frontend indexing and subgraph ingestion.
    function getDeployedCampaigns() external view returns (address[] memory campaigns) {
        return s_deployedCampaigns;
    }

    /// @notice Returns whether an address is a genuine campaign deployed by this factory.
    /// @param _campaignAddress The campaign contract address to verify.
    /// @return isVerified True if the address was created via `createCampaign`.
    function getCampaignStatus(address _campaignAddress) external view returns (bool isVerified) {
        return s_isVerifiedCampaign[_campaignAddress];
    }

    /// @notice Returns the total number of campaigns deployed by this factory.
    /// @return count The length of the deployed campaigns registry.
    function getDeployedCampaignCount() external view returns (uint256 count) {
        return s_deployedCampaigns.length;
    }
}
