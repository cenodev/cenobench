// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @title Marketplace
/// @notice Configures the protocol fee taken from fixed-price sales.
contract Marketplace {
    uint256 public protocolFeeBps;
    address public treasury;

    event FeeUpdated(uint256 bps);

    constructor(address treasury_) {
        require(treasury_ != address(0), "zero treasury");
        treasury = treasury_;
        protocolFeeBps = 250;
    }

    /// @notice Update the protocol fee in basis points. Meant for the admin.
    function setProtocolFeeBps(uint256 feeBps) external {
        require(feeBps <= 10_000, "fee too high");
        protocolFeeBps = feeBps;
        emit FeeUpdated(feeBps);
    }

    function feeFor(uint256 price) external view returns (uint256) {
        return (price * protocolFeeBps) / 10_000;
    }
}
