// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Vault} from "../../src/Vault.sol";
import {MockERC20} from "../../src/MockERC20.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
}

contract VaultHiddenTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockERC20 usdc;
    Vault vault;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);

    function setUp() public {
        usdc = new MockERC20("USD Coin", "USDC", 6);
        vault = new Vault(address(usdc));
        usdc.mint(alice, 1_000_000e6);
        usdc.mint(bob, 1_000_000e6);
        usdc.mint(carol, 10e6);
    }

    function _deposit(address who, uint256 assets) internal returns (uint256 shares) {
        vm.prank(who);
        usdc.approve(address(vault), assets);
        vm.prank(who);
        shares = vault.deposit(assets);
    }

    function _harvest(uint256 assets) internal {
        usdc.mint(address(this), assets);
        usdc.approve(address(vault), assets);
        vault.harvest(assets);
    }

    function test_first_deposit_is_one_to_one() public {
        uint256 shares = _deposit(alice, 100e6);
        require(shares == 100e6, "shares != assets");
        require(vault.totalSupply() == 100e6, "supply");
        require(vault.balanceOf(alice) == 100e6, "balance");
        require(vault.totalAssets() == 100e6, "tracked assets");
        require(usdc.balanceOf(address(vault)) == 100e6, "vault did not pull assets");
        require(vault.convertToShares(50e6) == 50e6, "convertToShares");
        require(vault.convertToAssets(50e6) == 50e6, "convertToAssets");
    }

    function test_deposit_without_approval_reverts() public {
        vm.prank(carol);
        vm.expectRevert();
        vault.deposit(10e6);
    }

    function test_zero_amounts_revert() public {
        _deposit(alice, 100e6);
        vm.prank(alice);
        vm.expectRevert();
        vault.deposit(0);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(0);
    }

    function test_donations_do_not_move_share_price() public {
        _deposit(alice, 100e6);
        usdc.mint(address(vault), 50e6);
        require(vault.totalAssets() == 100e6, "donation counted as assets");
        uint256 bShares = _deposit(bob, 100e6);
        require(bShares == 100e6, "donation moved the share price");
    }

    function test_deposit_rounds_down() public {
        _deposit(alice, 100e6);
        _harvest(50e6);
        require(vault.totalAssets() == 150e6, "tracked after harvest");

        usdc.mint(bob, 1);
        vm.prank(bob);
        usdc.approve(address(vault), 1);
        vm.prank(bob);
        vm.expectRevert();
        vault.deposit(1);

        usdc.mint(bob, 2);
        vm.prank(bob);
        usdc.approve(address(vault), 2);
        vm.prank(bob);
        uint256 shares = vault.deposit(2);
        require(shares == 1, "floor(2 * 100 / 150) should be 1");
    }

    function test_withdraw_rounds_up() public {
        _deposit(alice, 100e6);
        _harvest(50e6);

        vm.prank(alice);
        uint256 shares = vault.withdraw(1);
        require(shares == 1, "ceil(1 * 100 / 150) should be 1");
        require(vault.balanceOf(alice) == 100e6 - 1, "alice shares");
        require(vault.totalSupply() == 100e6 - 1, "supply");
        require(vault.totalAssets() == 150e6 - 1, "tracked after withdraw");
    }

    function test_withdraw_beyond_holdings_reverts() public {
        _deposit(alice, 100e6);
        vm.prank(alice);
        vm.expectRevert();
        vault.withdraw(100e6 + 1);

        _harvest(50e6);
        vm.prank(bob);
        vm.expectRevert();
        vault.withdraw(1);
    }

    function test_harvest_is_owner_only_and_moves_price() public {
        vm.prank(alice);
        vm.expectRevert();
        vault.harvest(1);

        _deposit(alice, 100e6);
        _harvest(50e6);
        require(vault.convertToShares(150e6) == 100e6, "share price did not rise");
    }

    function test_withdraw_all_after_yield() public {
        _deposit(alice, 100e6);
        _harvest(50e6);
        vm.prank(alice);
        uint256 shares = vault.withdraw(150e6);
        require(shares == 100e6, "burned shares");
        require(vault.totalSupply() == 0, "supply not zero");
        require(vault.totalAssets() == 0, "assets not zero");
        require(usdc.balanceOf(address(vault)) == 0, "vault still holds tokens");
    }
}
