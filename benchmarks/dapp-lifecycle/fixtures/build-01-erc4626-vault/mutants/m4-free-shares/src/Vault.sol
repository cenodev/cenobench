// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

contract Vault {
    IERC20 public immutable asset;
    address public immutable owner;
    uint8 public immutable assetDecimals;

    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    uint256 private _totalAssets;

    event Deposit(address indexed caller, uint256 assets, uint256 shares);
    event Withdraw(address indexed caller, uint256 assets, uint256 shares);

    constructor(address asset_) {
        asset = IERC20(asset_);
        owner = msg.sender;
        assetDecimals = IERC20(asset_).decimals();
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "not owner");
        _;
    }

    function decimals() external view returns (uint8) {
        return assetDecimals;
    }

    function totalAssets() public view returns (uint256) {
        return _totalAssets;
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? assets : (assets * supply) / _totalAssets;
    }

    function convertToAssets(uint256 shares) public view returns (uint256) {
        uint256 supply = totalSupply;
        return supply == 0 ? shares : (shares * _totalAssets) / supply;
    }

    function harvest(uint256 assets) external onlyOwner {
        require(assets > 0, "zero assets");
        require(asset.transferFrom(msg.sender, address(this), assets), "transferFrom failed");
        _totalAssets += assets;
    }

    function deposit(uint256 assets) external returns (uint256 shares) {
        require(assets > 0, "zero assets");
        shares = convertToShares(assets);
        require(shares > 0, "zero shares");
        _totalAssets += assets;
        totalSupply += shares;
        balanceOf[msg.sender] += shares;
        emit Deposit(msg.sender, assets, shares);
    }

    function withdraw(uint256 assets) external returns (uint256 shares) {
        require(assets > 0, "zero assets");
        uint256 supply = totalSupply;
        require(assets <= _totalAssets, "insufficient assets");
        shares = (assets * supply + _totalAssets - 1) / _totalAssets;
        require(balanceOf[msg.sender] >= shares, "insufficient shares");
        balanceOf[msg.sender] -= shares;
        totalSupply = supply - shares;
        _totalAssets -= assets;
        require(asset.transfer(msg.sender, assets), "transfer failed");
        emit Withdraw(msg.sender, assets, shares);
    }
}
