// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {LinearVesting} from "../../src/LinearVesting.sol";
import {MockERC20} from "../../src/MockERC20.sol";

interface Vm {
    function prank(address) external;
    function expectRevert() external;
    function warp(uint256) external;
}

contract VestingTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    uint256 constant TOTAL = 1000e6;
    uint256 constant START = 1_000_000;
    uint256 constant CLIFF = 100;
    uint256 constant DURATION = 1000;

    address constant BENEFICIARY = address(0xB0B);
    address constant STRANGER = address(0x57A);

    MockERC20 token;
    LinearVesting vesting;

    function setUp() public {
        token = new MockERC20("Vested", "VST", 6);
        vesting = new LinearVesting(address(token), BENEFICIARY, START, CLIFF, DURATION, TOTAL);
        token.mint(address(vesting), TOTAL);
    }

    function test_before_cliff_vests_nothing() public {
        vm.warp(START + 1);
        require(vesting.vestedAmount(START + 1) == 0, "vested before start+cliff");
        vm.warp(START + 50);
        require(vesting.vestedAmount(START + 50) == 0, "not zero before cliff");
        require(vesting.releasable() == 0, "releasable before cliff");
        vm.expectRevert();
        vesting.release();
    }

    function test_cliff_boundary_is_exact() public {
        vm.warp(START + CLIFF - 1);
        require(vesting.vestedAmount(START + CLIFF - 1) == 0, "one second before cliff");
        vm.warp(START + CLIFF);
        require(vesting.vestedAmount(START + CLIFF) == (TOTAL * CLIFF) / DURATION, "at cliff");
    }

    function test_midpoint_and_end() public {
        vm.warp(START + 500);
        require(vesting.vestedAmount(START + 500) == TOTAL / 2, "midpoint");
        vm.warp(START + DURATION);
        require(vesting.vestedAmount(START + DURATION) == TOTAL, "at end");
        vm.warp(START + DURATION + 10_000);
        require(vesting.vestedAmount(START + DURATION + 10_000) == TOTAL, "after end caps");
    }

    function test_release_transfers_and_tracks_released() public {
        vm.warp(START + 500);
        vesting.release();
        require(token.balanceOf(BENEFICIARY) == TOTAL / 2, "beneficiary");
        require(vesting.released() == TOTAL / 2, "released");
        require(token.balanceOf(address(vesting)) == TOTAL / 2, "contract");

        vm.expectRevert();
        vesting.release();

        vm.warp(START + DURATION);
        vesting.release();
        require(token.balanceOf(BENEFICIARY) == TOTAL, "full amount");
        require(vesting.released() == TOTAL, "released total");
        require(token.balanceOf(address(vesting)) == 0, "contract empty");
    }

    function test_revoke_keeps_vested_and_stops_accrual() public {
        vm.warp(START + 500);
        vesting.revoke();
        require(token.balanceOf(address(this)) == TOTAL / 2, "owner gets unvested");
        require(token.balanceOf(address(vesting)) == TOTAL / 2, "vested stays");

        vm.warp(START + 900);
        require(vesting.vestedAmount(START + 900) == TOTAL / 2, "accrual stopped at revoke");

        vesting.release();
        require(token.balanceOf(BENEFICIARY) == TOTAL / 2, "beneficiary keeps vested");
        require(token.balanceOf(address(vesting)) == 0, "contract empty after release");
    }

    function test_revoke_is_owner_only_and_once() public {
        vm.prank(STRANGER);
        vm.expectRevert();
        vesting.revoke();
        vesting.revoke();
        vm.expectRevert();
        vesting.revoke();
    }

    function test_revoke_before_cliff_returns_everything() public {
        vm.warp(START + 10);
        vesting.revoke();
        require(token.balanceOf(address(this)) == TOTAL, "owner gets all");
        require(token.balanceOf(address(vesting)) == 0, "nothing vested");
        vm.expectRevert();
        vesting.release();
    }

    function test_constructor_validation() public {
        vm.expectRevert();
        new LinearVesting(address(token), BENEFICIARY, START, 1001, 1000, TOTAL);
        vm.expectRevert();
        new LinearVesting(address(token), address(0), START, CLIFF, DURATION, TOTAL);
        vm.expectRevert();
        new LinearVesting(address(token), BENEFICIARY, START, CLIFF, 0, TOTAL);
        vm.expectRevert();
        new LinearVesting(address(token), BENEFICIARY, START, CLIFF, DURATION, 0);
    }
}
