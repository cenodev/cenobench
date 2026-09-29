// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Crowdfund} from "../../src/Crowdfund.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
    function warp(uint256) external;
    function deal(address, uint256) external;
}

contract CrowdfundHiddenTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    Crowdfund c;
    uint256 constant GOAL = 10 ether;
    uint256 deadline;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address carol = address(0xCA401);
    address deployer = address(0xD3);

    function setUp() public {
        deadline = block.timestamp + 7 days;
        vm.prank(deployer);
        c = new Crowdfund(GOAL, deadline);
        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);
        vm.deal(carol, 100 ether);
    }

    function _give(address who, uint256 amount) internal {
        vm.prank(who);
        c.contribute{value: amount}();
    }

    function test_contributions_record() public {
        _give(alice, 3 ether);
        _give(bob, 2 ether);
        require(c.totalRaised() == 5 ether, "total");
        require(c.contributions(alice) == 3 ether, "alice");
        require(c.contributions(bob) == 2 ether, "bob");
        require(address(c).balance == 5 ether, "balance");
        require(c.owner() == deployer, "owner");
    }

    function test_zero_value_reverts() public {
        vm.prank(alice);
        vm.expectRevert();
        c.contribute{value: 0}();
    }

    function test_plain_eth_transfer_rejected() public {
        (bool ok,) = address(c).call{value: 1 ether}("");
        require(!ok, "plain send accepted");
        require(address(c).balance == 0, "contract holds stray ETH");
    }

    function test_contribute_at_deadline_reverts() public {
        _give(alice, 1 ether);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert();
        c.contribute{value: 1 ether}();
    }

    function test_hard_cap() public {
        _give(alice, 6 ether);
        _give(bob, 4 ether);
        require(c.totalRaised() == GOAL, "goal not reached");

        vm.prank(carol);
        vm.expectRevert();
        c.contribute{value: 1 ether}();

        vm.prank(carol);
        vm.expectRevert();
        c.contribute{value: 1}();
    }

    function test_withdraw_requires_deadline_and_goal() public {
        _give(alice, 3 ether);
        vm.prank(alice);
        vm.expectRevert();
        c.withdrawFunds();

        vm.warp(deadline);
        vm.prank(deployer);
        vm.expectRevert();
        c.withdrawFunds();
    }

    function test_withdraw_before_deadline_reverts_even_when_funded() public {
        _give(alice, 10 ether);
        vm.prank(deployer);
        vm.expectRevert();
        c.withdrawFunds();
        require(address(c).balance == 10 ether, "balance moved early");
    }

    function test_withdraw_transfers_balance_and_zeroes_total() public {
        _give(alice, 10 ether);
        vm.warp(deadline);

        vm.prank(alice);
        vm.expectRevert();
        c.withdrawFunds();

        uint256 before = deployer.balance;
        vm.prank(deployer);
        c.withdrawFunds();
        require(deployer.balance == before + 10 ether, "owner did not receive funds");
        require(c.totalRaised() == 0, "total not reset");
        require(address(c).balance == 0, "contract not drained");

        vm.prank(deployer);
        vm.expectRevert();
        c.withdrawFunds();
    }

    function test_refund_requires_deadline_and_contribution() public {
        _give(alice, 2 ether);
        vm.prank(alice);
        vm.expectRevert();
        c.refund();

        vm.warp(deadline);
        vm.prank(carol);
        vm.expectRevert();
        c.refund();
    }

    function test_refund_returns_deposit_and_blocks_double_refund() public {
        _give(alice, 2 ether);
        _give(bob, 4 ether);
        require(c.totalRaised() < GOAL, "setup must miss the goal");

        vm.warp(deadline);
        vm.prank(alice);
        c.refund();
        require(alice.balance == 100 ether, "alice not made whole");
        require(c.contributions(alice) == 0, "contribution not zeroed");
        require(c.totalRaised() == 4 ether, "total not decremented");

        vm.prank(alice);
        vm.expectRevert();
        c.refund();

        vm.prank(bob);
        c.refund();
        require(bob.balance == 100 ether, "bob not made whole");
        require(c.totalRaised() == 0, "total not fully decremented");
        require(address(c).balance == 0, "contract still holds ETH");
    }

    function test_refund_blocked_when_goal_met() public {
        _give(alice, 10 ether);
        vm.warp(deadline);
        vm.prank(alice);
        vm.expectRevert();
        c.refund();
    }

    function test_constructor_validation() public {
        vm.expectRevert();
        new Crowdfund(0, block.timestamp + 1 days);
        vm.expectRevert();
        new Crowdfund(1 ether, block.timestamp);
        vm.expectRevert();
        new Crowdfund(1 ether, block.timestamp - 1);
    }
}
