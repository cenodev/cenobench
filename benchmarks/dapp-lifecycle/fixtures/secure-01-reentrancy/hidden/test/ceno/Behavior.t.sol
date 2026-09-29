// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {StakingPool} from "../../src/StakingPool.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
    function deal(address, uint256) external;
}

contract StakingPoolBehaviorTest {
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
        require(address(pool).balance == 3 ether, "eth not held");
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
        require(address(pool).balance == 0, "pool still holds eth");
    }

    function test_withdraw_without_stake_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        pool.withdrawAll();
    }

    function test_withdrawals_are_independent() public {
        vm.prank(alice);
        pool.stake{value: 2 ether}();
        vm.prank(bob);
        pool.stake{value: 5 ether}();

        vm.prank(alice);
        pool.withdrawAll();
        require(alice.balance == 100 ether, "alice wrong");
        require(pool.stakeOf(bob) == 5 ether, "bob touched");
        require(address(pool).balance == 5 ether, "pool wrong");

        vm.prank(bob);
        pool.withdrawAll();
        require(bob.balance == 100 ether, "bob wrong");
        require(address(pool).balance == 0, "pool not empty");
    }
}
