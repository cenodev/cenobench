// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title PriceOracle
/// @notice Stores the USD price of the collateral token, scaled 1e18. The protocol admin
///         updates it from the off-chain price feed.
contract PriceOracle {
    uint256 public price;

    constructor(uint256 initialPrice) {
        price = initialPrice;
    }

    /// @notice Update the collateral price. Intended to be callable only by the admin.
    function setPrice(uint256 newPrice) external {
        price = newPrice;
    }

    function getPrice() external view returns (uint256) {
        return price;
    }
}
