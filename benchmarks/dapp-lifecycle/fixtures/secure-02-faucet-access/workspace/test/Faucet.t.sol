// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {RewardFaucet} from "../src/RewardFaucet.sol";
import {MockERC20} from "../src/MockERC20.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
    function deal(address, uint256) external;
}

contract RewardFaucetTest {
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

    function test_owner_can_set_minter() public {
        faucet.setMinter(alice);
        require(faucet.minter() == alice, "minter not set");
    }

    function test_minter_can_mint() public {
        faucet.setMinter(address(this));
        faucet.mint(bob, 10e6);
        require(token.balanceOf(bob) == 10e6, "not minted");
    }

    function test_non_minter_cannot_mint() public {
        faucet.setMinter(alice);
        vm.prank(bob);
        vm.expectRevert();
        faucet.mint(bob, 1e6);
    }

    function test_owner_can_sweep() public {
        faucet.sweep(alice);
        require(token.balanceOf(alice) == 500e6, "not swept");
    }
}
