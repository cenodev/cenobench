// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

contract LinearVesting {
    IERC20 public immutable token;
    address public immutable owner;
    address public immutable beneficiary;
    uint256 public immutable start;
    uint256 public immutable cliff;
    uint256 public immutable duration;
    uint256 public immutable totalAmount;

    uint256 public released;
    uint256 public revokedAt;

    constructor(
        address token_,
        address beneficiary_,
        uint256 start_,
        uint256 cliff_,
        uint256 duration_,
        uint256 totalAmount_
    ) {
        require(token_ != address(0), "zero token");
        require(beneficiary_ != address(0), "zero beneficiary");
        require(duration_ > 0, "zero duration");
        require(cliff_ <= duration_, "cliff after duration");
        require(totalAmount_ > 0, "zero total");
        token = IERC20(token_);
        beneficiary = beneficiary_;
        start = start_;
        cliff = cliff_;
        duration = duration_;
        totalAmount = totalAmount_;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function vestedAmount(uint256 timestamp) public view returns (uint256) {
        if (revokedAt != 0 && timestamp > revokedAt) {
            timestamp = revokedAt;
        }
        if (timestamp < start + cliff) return 0;
        if (timestamp >= start + duration) return totalAmount;
        return (totalAmount * (timestamp - start)) / duration;
    }

    function releasable() external view returns (uint256) {
        return vestedAmount(block.timestamp) - released;
    }

    function release() external {
        uint256 amount = vestedAmount(block.timestamp) - released;
        require(amount > 0, "nothing to release");
        released += amount;
        require(token.transfer(beneficiary, amount), "transfer failed");
    }

    function revoke() external onlyOwner {
        require(revokedAt == 0, "already revoked");
        revokedAt = block.timestamp;
        uint256 unvested = totalAmount;
        require(token.transfer(owner, unvested), "transfer failed");
    }
}
