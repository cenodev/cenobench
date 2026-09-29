// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StakingPool} from "../src/StakingPool.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
    function deal(address, uint256) external;
}

contract StakingPoolTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    StakingPool pool;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        pool = new StakingPool();
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
    }

    function test_stake_credits_caller() public {
        vm.prank(alice);
        pool.stake{value: 3 ether}();
        require(pool.stakeOf(alice) == 3 ether, "stake not credited");
    }

    function test_stake_zero_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.stake{value: 0}();
    }

    function test_withdraw_all_returns_funds_and_zeroes() public {
        vm.prank(alice);
        pool.stake{value: 3 ether}();
        uint256 before = alice.balance;
        vm.prank(alice);
        pool.withdrawAll();
        require(alice.balance == before + 3 ether, "funds not returned");
        require(pool.stakeOf(alice) == 0, "stake not zeroed");
    }

    function test_withdraw_without_stake_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.withdrawAll();
    }
}
