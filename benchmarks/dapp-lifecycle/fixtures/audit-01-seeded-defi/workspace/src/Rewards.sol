// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

/// @title Rewards
/// @notice A fixed rewards program: every staked token earns REWARD_PER_TOKEN over the program.
contract Rewards {
    uint256 public constant REWARD_PER_TOKEN = 3e17; // 0.3 tokens per staked token, 1e18 scale

    IERC20 public immutable token;
    mapping(address => uint256) public staked;
    mapping(address => uint256) public claimed;

    constructor(IERC20 token_) {
        token = token_;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "zero stake");
        staked[msg.sender] += amount;
        require(token.transferFrom(msg.sender, address(this), amount), "transferFrom failed");
    }

    function unstake(uint256 amount) external {
        require(amount > 0 && amount <= staked[msg.sender], "bad amount");
        staked[msg.sender] -= amount;
        require(token.transfer(msg.sender, amount), "transfer failed");
    }

    /// @notice Total rewards earned by `user` for their current stake.
    function earned(address user) public view returns (uint256) {
        return staked[user] / 1e18 * REWARD_PER_TOKEN;
    }

    function claim() external {
        uint256 owed = earned(msg.sender) - claimed[msg.sender];
        require(owed > 0, "nothing to claim");
        claimed[msg.sender] += owed;
        require(token.transfer(msg.sender, owed), "transfer failed");
    }
}
