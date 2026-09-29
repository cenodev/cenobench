// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {MerkleAirdrop} from "../../src/MerkleAirdrop.sol";
import {MockERC20} from "../../src/MockERC20.sol";

interface Vm {
    function expectRevert() external;
}

contract MerkleAirdropTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockERC20 token;
    MerkleAirdrop airdrop;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    bytes32 l0;
    bytes32 l1;
    bytes32 l2;
    bytes32 root;

    function setUp() public {
        token = new MockERC20("Airdrop", "AIR", 6);
        l0 = keccak256(abi.encode(uint256(0), alice, uint256(100e6)));
        l1 = keccak256(abi.encode(uint256(1), bob, uint256(200e6)));
        l2 = keccak256(abi.encode(uint256(2), carol, uint256(300e6)));
        root = _pair(_pair(l0, l1), l2);
        airdrop = new MerkleAirdrop(address(token), root);
        token.mint(address(airdrop), 600e6);
    }

    function _pair(bytes32 a, bytes32 b) internal pure returns (bytes32) {
        return a < b ? keccak256(abi.encode(a, b)) : keccak256(abi.encode(b, a));
    }

    function _proof0() internal view returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = l1;
        p[1] = l2;
    }

    function _proof1() internal view returns (bytes32[] memory p) {
        p = new bytes32[](2);
        p[0] = l0;
        p[1] = l2;
    }

    function _proof2() internal view returns (bytes32[] memory p) {
        p = new bytes32[](1);
        p[0] = _pair(l0, l1);
    }

    function test_claim_transfers_to_account_and_marks_index() public {
        airdrop.claim(0, alice, 100e6, _proof0());
        require(token.balanceOf(alice) == 100e6, "alice balance");
        require(airdrop.isClaimed(0), "not marked");
        require(airdrop.claimed(0), "claimed mapping");
    }

    function test_double_claim_reverts() public {
        airdrop.claim(0, alice, 100e6, _proof0());
        vm.expectRevert();
        airdrop.claim(0, alice, 100e6, _proof0());
    }

    function test_tampered_amount_reverts() public {
        vm.expectRevert();
        airdrop.claim(0, alice, 100e6 + 1, _proof0());
    }

    function test_wrong_account_reverts() public {
        vm.expectRevert();
        airdrop.claim(0, carol, 100e6, _proof0());
    }

    function test_bad_proofs_revert() public {
        bytes32[] memory empty = new bytes32[](0);
        vm.expectRevert();
        airdrop.claim(0, alice, 100e6, empty);

        bytes32[] memory extra = new bytes32[](3);
        extra[0] = l1;
        extra[1] = l2;
        extra[2] = l2;
        vm.expectRevert();
        airdrop.claim(0, alice, 100e6, extra);
    }

    function test_unknown_index_reverts() public {
        vm.expectRevert();
        airdrop.claim(9, alice, 100e6, _proof0());
    }

    function test_all_leaves_claimable() public {
        airdrop.claim(0, alice, 100e6, _proof0());
        airdrop.claim(1, bob, 200e6, _proof1());
        airdrop.claim(2, carol, 300e6, _proof2());
        require(token.balanceOf(alice) == 100e6, "alice");
        require(token.balanceOf(bob) == 200e6, "bob");
        require(token.balanceOf(carol) == 300e6, "carol");
        require(token.balanceOf(address(airdrop)) == 0, "airdrop leftovers");
    }

    function test_zero_amount_reverts() public {
        vm.expectRevert();
        airdrop.claim(0, alice, 0, _proof0());
    }
}
