// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {AggregatorV3Interface} from "../../src/Campaign.sol";

/// @notice Isolated Chainlink ETH/USD mock for unit tests — no fork required.
contract MockV3Aggregator is AggregatorV3Interface {
    int256 private s_answer;
    uint256 private s_updatedAt;

    uint8 private constant DECIMALS = 8;

    constructor(int256 initialAnswer) {
        s_answer = initialAnswer;
        s_updatedAt = block.timestamp;
    }

    /// @notice Updates the mocked price and refreshes the timestamp to avoid staleness reverts.
    function updateAnswer(int256 newAnswer) external {
        s_answer = newAnswer;
        s_updatedAt = block.timestamp;
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function description() external pure returns (string memory) {
        return "Mock ETH/USD";
    }

    function version() external pure returns (uint256) {
        return 1;
    }

    function getRoundData(uint80)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, s_answer, block.timestamp, s_updatedAt, 0);
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, s_answer, block.timestamp, s_updatedAt, 0);
    }
}
