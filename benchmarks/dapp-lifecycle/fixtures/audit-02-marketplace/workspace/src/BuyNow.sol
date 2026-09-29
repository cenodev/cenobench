// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

/// @title BuyNow
/// @notice Fixed-price sales: a seller lists an ERC-20 item with a price, a buyer pays ETH.
contract BuyNow {
    struct Listing {
        address seller;
        address item;
        uint256 price;
    }

    mapping(uint256 => Listing) public listings;

    event Listed(uint256 indexed id, address indexed seller, address item, uint256 price);
    event Bought(uint256 indexed id, address indexed buyer, uint256 price);

    function list(uint256 id, address item, uint256 price) external {
        require(price > 0, "zero price");
        listings[id] = Listing(msg.sender, item, price);
        emit Listed(id, msg.sender, item, price);
    }

    /// @notice Buy a listing at its fixed price. The buyer pays exactly the listing price;
    ///         any excess ETH must come back to the buyer.
    function buy(uint256 id) external payable {
        Listing memory listing = listings[id];
        require(listing.seller != address(0), "not listed");
        require(msg.value >= listing.price, "underpaid");

        delete listings[id];

        (bool toSeller,) = listing.seller.call{value: listing.price}("");
        require(toSeller, "seller payment failed");

        emit Bought(id, msg.sender, listing.price);
    }
}
