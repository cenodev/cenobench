// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {IERC20} from "./IERC20.sol";

contract MerkleAirdrop {
    IERC20 public immutable token;
    bytes32 public immutable merkleRoot;
    mapping(uint256 => bool) public claimed;

    event Claimed(uint256 indexed index, address indexed account, uint256 amount);

    constructor(address token_, bytes32 merkleRoot_) {
        require(token_ != address(0), "zero token");
        token = IERC20(token_);
        merkleRoot = merkleRoot_;
    }

    function isClaimed(uint256 index) external view returns (bool) {
        return claimed[index];
    }

    function claim(uint256 index, address account, uint256 amount, bytes32[] calldata proof) external {
        require(!claimed[index], "already claimed");
        require(account != address(0), "zero account");
        require(amount > 0, "zero amount");
        bytes32 leaf = keccak256(abi.encode(index, account, amount));
        require(_verify(leaf, proof, merkleRoot), "invalid proof");
        claimed[index] = true;
        require(token.transfer(msg.sender, amount), "transfer failed");
        emit Claimed(index, account, amount);
    }

    function _verify(bytes32 leaf, bytes32[] calldata proof, bytes32 root) internal pure returns (bool) {
        bytes32 computed = leaf;
        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 sibling = proof[i];
            computed = computed <= sibling ? keccak256(abi.encode(computed, sibling)) : keccak256(abi.encode(sibling, computed));
        }
        return computed == root;
    }
}
