// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Ledger} from "../../src/Ledger.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
}

contract LedgerGoldTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Ledger token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new Ledger("Ledger", "LDG", 18);
        token.mint(alice, 1000e18);
    }

    function test_mint_only_owner() public {
        vm.prank(alice);
        vm.expectRevert();
        token.mint(alice, 1);
    }

    function test_mint_updates_supply_and_balance() public {
        token.mint(bob, 100);
        require(token.totalSupply() == 1000e18 + 100, "supply");
        require(token.balanceOf(bob) == 100, "balance");
    }

    function test_mint_rejects_zero_amount_and_zero_address() public {
        vm.expectRevert();
        token.mint(bob, 0);
        vm.expectRevert();
        token.mint(address(0), 1);
    }

    function test_transfer_moves_funds_and_returns_true() public {
        vm.prank(alice);
        bool ok = token.transfer(bob, 10e18);
        require(ok, "return value");
        require(token.balanceOf(alice) == 990e18, "alice");
        require(token.balanceOf(bob) == 10e18, "bob");
    }

    function test_transfer_rejects_zero_amount_and_zero_address() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 0);
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(address(0), 1);
    }

    function test_transfer_insufficient_reverts() public {
        vm.prank(bob);
        vm.expectRevert();
        token.transfer(alice, 1);
    }

    function test_approve_and_transfer_from_spends_allowance() public {
        vm.prank(alice);
        token.approve(bob, 100);
        require(token.allowance(alice, bob) == 100, "allowance set");

        vm.prank(bob);
        bool ok = token.transferFrom(alice, bob, 30);
        require(ok, "return value");
        require(token.allowance(alice, bob) == 70, "allowance spent");
        require(token.balanceOf(bob) == 30, "bob");
        require(token.balanceOf(alice) == 1000e18 - 30, "alice");
    }

    function test_unlimited_allowance_is_not_spent() public {
        vm.prank(alice);
        token.approve(bob, type(uint256).max);

        vm.prank(bob);
        token.transferFrom(alice, bob, 30);
        require(token.allowance(alice, bob) == type(uint256).max, "unlimited spent");
    }

    function test_transfer_from_requires_allowance() public {
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, 1);

        vm.prank(alice);
        token.approve(bob, 10);
        vm.prank(bob);
        vm.expectRevert();
        token.transferFrom(alice, bob, 11);
    }

    function test_approve_zero_spender_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        token.approve(address(0), 1);
    }

    function test_burn_reduces_balance_and_supply() public {
        vm.prank(alice);
        token.burn(400e18);
        require(token.balanceOf(alice) == 600e18, "balance");
        require(token.totalSupply() == 600e18, "supply");
    }

    function test_burn_insufficient_reverts() public {
        vm.prank(bob);
        vm.expectRevert();
        token.burn(1);
    }
}
