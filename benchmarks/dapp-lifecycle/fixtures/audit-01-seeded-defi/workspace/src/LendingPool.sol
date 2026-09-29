// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {PriceOracle} from "./PriceOracle.sol";

/// @title LendingPool
/// @notice ETH-collateralised borrowing with a 50% maximum LTV.
contract LendingPool {
    PriceOracle public immutable oracle;

    mapping(address => uint256) public collateral;
    mapping(address => uint256) public debt;

    event Deposited(address indexed user, uint256 amount);
    event Borrowed(address indexed user, uint256 amount);
    event Liquidated(address indexed user, address indexed liquidator, uint256 seized);

    constructor(PriceOracle oracle_) {
        oracle = oracle_;
    }

    function depositCollateral() external payable {
        require(msg.value > 0, "zero deposit");
        collateral[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function borrow(uint256 amount) external {
        require(amount > 0, "zero borrow");
        uint256 collateralValue = (collateral[msg.sender] * oracle.getPrice()) / 1e18;
        require((debt[msg.sender] + amount) * 2 <= collateralValue, "insufficient collateral");
        debt[msg.sender] += amount;
        payable(msg.sender).transfer(amount);
        emit Borrowed(msg.sender, amount);
    }

    /// @notice Liquidate a position that has fallen below the 50% maintenance threshold.
    ///         The liquidator receives the position's collateral and the debt is cleared.
    function liquidate(address user) external {
        require(debt[user] > 0, "no debt");
        uint256 seized = collateral[user];
        collateral[user] = 0;
        debt[user] = 0;
        payable(msg.sender).transfer(seized);
        emit Liquidated(user, msg.sender, seized);
    }
}
