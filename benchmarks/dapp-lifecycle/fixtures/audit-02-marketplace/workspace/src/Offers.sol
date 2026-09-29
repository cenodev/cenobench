// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";
import {IERC721} from "./IERC721.sol";

/// @title Offers
/// @notice Fills signed buy offers: a maker signs an offer to buy an NFT, the holder fills it.
contract Offers {
    struct Offer {
        address maker;
        address collection;
        uint256 tokenId;
        address paymentToken;
        uint256 price;
        uint256 expiry;
    }

    /// @dev Offers that have been filled, kept for the protocol's records.
    mapping(bytes32 => bool) public filled;

    event OfferFilled(bytes32 indexed offerHash, address indexed maker, address filler);

    /// @notice Fill a signed offer: the NFT goes to the maker, the payment goes to the filler.
    function fillOffer(Offer calldata offer, bytes calldata signature) external {
        require(block.timestamp <= offer.expiry, "offer expired");
        bytes32 digest = keccak256(
            abi.encode(offer.maker, offer.collection, offer.tokenId, offer.paymentToken, offer.price, offer.expiry)
        );
        require(recover(digest, signature) == offer.maker, "bad signature");

        IERC721(offer.collection).safeTransferFrom(msg.sender, offer.maker, offer.tokenId);
        require(IERC20(offer.paymentToken).transferFrom(offer.maker, msg.sender, offer.price), "payment failed");

        emit OfferFilled(digest, offer.maker, msg.sender);
    }

    function recover(bytes32 digest, bytes calldata signature) public pure returns (address) {
        require(signature.length == 65, "bad signature length");
        bytes32 r;
        bytes32 s;
        uint8 v;
        assembly {
            r := calldataload(signature.offset)
            s := calldataload(add(signature.offset, 32))
            v := byte(0, calldataload(add(signature.offset, 64)))
        }
        return ecrecover(digest, v, r, s);
    }
}
