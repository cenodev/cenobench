// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardFaucet} from "../../src/RewardFaucet.sol";
import {MockERC20} from "../../src/MockERC20.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
}

contract RewardFaucetBehaviorTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    MockERC20 token;
    RewardFaucet faucet;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        token = new MockERC20("Reward", "RWD", 6);
        faucet = new RewardFaucet(address(token));
        token.mint(address(faucet), 500e6);
    }

    function test_owner_sets_minter_and_minter_mints() public {
        faucet.setMinter(address(this));
        faucet.mint(bob, 10e6);
        require(token.balanceOf(bob) == 10e6, "not minted");
        require(token.balanceOf(address(faucet)) == 490e6, "faucet balance");
    }

    function test_non_minter_mint_reverts() public {
        faucet.setMinter(alice);
        vm.prank(bob);
        vm.expectRevert();
        faucet.mint(bob, 1e6);
    }

    function test_non_owner_set_minter_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.setMinter(alice);
        require(faucet.minter() == address(0), "minter changed");
    }

    function test_non_owner_sweep_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        faucet.sweep(alice);
        require(token.balanceOf(address(faucet)) == 500e6, "faucet drained");
    }

    function test_owner_sweep_sends_balance() public {
        faucet.sweep(alice);
        require(token.balanceOf(alice) == 500e6, "not swept");
        require(token.balanceOf(address(faucet)) == 0, "leftovers");
    }
}
