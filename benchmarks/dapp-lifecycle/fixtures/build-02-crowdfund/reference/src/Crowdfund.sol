// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract Crowdfund {
    address public immutable owner;
    uint256 public immutable goal;
    uint256 public immutable deadline;
    uint256 public totalRaised;
    mapping(address => uint256) public contributions;

    event Contributed(address indexed contributor, uint256 amount, uint256 totalRaised);
    event FundsWithdrawn(address indexed owner, uint256 amount);
    event Refunded(address indexed contributor, uint256 amount);

    constructor(uint256 goal_, uint256 deadline_) {
        require(goal_ > 0, "zero goal");
        require(deadline_ > block.timestamp, "deadline not future");
        owner = msg.sender;
        goal = goal_;
        deadline = deadline_;
    }

    function contribute() external payable {
        require(block.timestamp < deadline, "campaign ended");
        require(msg.value > 0, "zero contribution");
        require(totalRaised + msg.value <= goal, "goal exceeded");
        contributions[msg.sender] += msg.value;
        totalRaised += msg.value;
        emit Contributed(msg.sender, msg.value, totalRaised);
    }

    function withdrawFunds() external {
        require(msg.sender == owner, "not owner");
        require(block.timestamp >= deadline, "campaign not ended");
        require(totalRaised >= goal, "goal not met");
        uint256 amount = address(this).balance;
        totalRaised = 0;
        (bool ok,) = owner.call{value: amount}("");
        require(ok, "send failed");
        emit FundsWithdrawn(owner, amount);
    }

    function refund() external {
        require(block.timestamp >= deadline, "campaign not ended");
        require(totalRaised < goal, "goal met");
        uint256 amount = contributions[msg.sender];
        require(amount > 0, "nothing to refund");
        contributions[msg.sender] = 0;
        totalRaised -= amount;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send failed");
        emit Refunded(msg.sender, amount);
    }
}
