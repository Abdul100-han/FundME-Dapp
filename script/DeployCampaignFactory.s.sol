// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Script, console2} from "forge-std/Script.sol";
import {CampaignFactory} from "../src/CampaignFactory.sol";
import {MockV3Aggregator} from "../test/mocks/MockV3Aggregator.sol";

/// @title DeployCampaignFactory
/// @notice Network-aware deployment script for the CampaignFactory registry contract.
/// @dev Resolves the correct ETH/USD price feed per chain before broadcasting factory deployment.
contract DeployCampaignFactory is Script {
    /*//////////////////////////////////////////////////////////////
                               CONSTANTS
    //////////////////////////////////////////////////////////////*/

    uint256 internal constant SEPOLIA_CHAIN_ID = 11_155_111;
    uint256 internal constant ANVIL_CHAIN_ID = 31_337;

    /// @dev Sepolia ETH/USD Chainlink AggregatorV3 feed.
    address internal constant SEPOLIA_ETH_USD_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;

    /// @dev Mock oracle price used for local Anvil deployments ($2,000.00 with 8 decimals).
    int256 internal constant MOCK_ETH_USD_PRICE = 2000e8;

    /*//////////////////////////////////////////////////////////////
                            CUSTOM ERRORS
    //////////////////////////////////////////////////////////////*/

    error DeployCampaignFactory__UnsupportedChain(uint256 chainId);

    /*//////////////////////////////////////////////////////////////
                              ENTRYPOINT
    //////////////////////////////////////////////////////////////*/

    /// @notice Deploys CampaignFactory and resolves the chain-appropriate price feed address.
    /// @return factoryAddress The address of the newly deployed CampaignFactory instance.
    function run() external returns (address factoryAddress) {
        if (block.chainid != SEPOLIA_CHAIN_ID && block.chainid != ANVIL_CHAIN_ID) {
            revert DeployCampaignFactory__UnsupportedChain(block.chainid);
        }

        address priceFeed;

        vm.startBroadcast();

        if (block.chainid == ANVIL_CHAIN_ID) {
            priceFeed = address(new MockV3Aggregator(MOCK_ETH_USD_PRICE));
        } else {
            priceFeed = SEPOLIA_ETH_USD_FEED;
        }

        CampaignFactory factory = new CampaignFactory();
        factoryAddress = address(factory);

        vm.stopBroadcast();

        console2.log("========================================");
        console2.log(" CampaignFactory Deployment Summary");
        console2.log("========================================");
        console2.log("Chain ID:        ", block.chainid);
        console2.log("CampaignFactory: ", factoryAddress);
        console2.log("Price Feed:      ", priceFeed);
        if (block.chainid == ANVIL_CHAIN_ID) {
            console2.log("Network:          Anvil (mock oracle deployed)");
        } else {
            console2.log("Network:          Sepolia (live Chainlink feed)");
        }
        console2.log("========================================");

        return factoryAddress;
    }
}
