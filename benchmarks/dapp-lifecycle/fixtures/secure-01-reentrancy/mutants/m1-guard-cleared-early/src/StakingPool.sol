// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

contract StakingPool {
    mapping(address => uint256) public stakeOf;
    bool private _locked;

    event Staked(address indexed user, uint256 amount);
    event Withdrawn(address indexed user, uint256 amount);

    modifier nonReentrant() {
        require(!_locked, "reentrant");
        _locked = true;
        _;
        _locked = false;
    }

    function stake() external payable {
        require(msg.value > 0, "zero stake");
        stakeOf[msg.sender] += msg.value;
        emit Staked(msg.sender, msg.value);
    }

    function withdrawAll() external nonReentrant {
        uint256 amount = stakeOf[msg.sender];
        require(amount > 0, "nothing staked");
        _locked = false;
        (bool ok,) = msg.sender.call{value: amount}("");
        require(ok, "send failed");
        stakeOf[msg.sender] = 0;
        emit Withdrawn(msg.sender, amount);
    }
}
