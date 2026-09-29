// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

contract RewardFaucet {
    IERC20 public immutable token;
    address public immutable owner;
    address public minter;

    event MinterSet(address indexed minter);
    event Minted(address indexed to, uint256 amount);
    event Swept(address indexed to, uint256 amount);

    constructor(address token_) {
        require(token_ != address(0), "zero token");
        token = IERC20(token_);
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function setMinter(address minter_) external onlyOwner {
        minter = minter_;
        emit MinterSet(minter_);
    }

    function mint(address to, uint256 amount) external {
        require(msg.sender == minter, "not minter");
        require(to != address(0), "zero to");
        require(amount > 0, "zero amount");
        require(token.transfer(to, amount), "transfer failed");
        emit Minted(to, amount);
    }

    /// @notice Sends the faucet's remaining balance to `to`. Intended for the owner during
    ///         migration or shutdown.
    function sweep(address to) external onlyOwner {
        require(to != address(0), "zero to");
        uint256 balance = token.balanceOf(address(this));
        require(token.transfer(to, balance), "transfer failed");
        emit Swept(to, balance);
    }
}
