// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {HalvingVesting} from "../src/HalvingVesting.sol";

contract MemeCoinTest is Test {
    MemeToken token;
    HalvingVesting vesting;
    address team = makeAddr("team");
    uint256 constant SUPPLY = 1_000_000_000e18;
    uint256 constant TEAM = 50_000_000e18;
    uint64 constant CLIFF = 90 days;
    uint64 constant PERIOD = 180 days;

    function setUp() public {
        token = new MemeToken("Test Coin", "TEST", SUPPLY, address(this));
        vesting = new HalvingVesting(token, team, uint64(block.timestamp) + CLIFF, PERIOD, 8);
        token.transfer(address(vesting), TEAM);
    }

    function test_FixedSupply() public view {
        assertEq(token.totalSupply(), SUPPLY);
        assertEq(token.decimals(), 18);
        assertEq(token.symbol(), "TEST");
    }

    function test_Burn() public {
        token.burn(1e18);
        assertEq(token.totalSupply(), SUPPLY - 1e18);
    }

    function test_NothingBeforeCliff() public {
        vm.warp(block.timestamp + CLIFF - 1);
        assertEq(vesting.releasable(), 0);
    }

    function test_HalvingSchedule() public {
        uint64 s = vesting.start();
        vm.warp(s);
        assertEq(vesting.releasable(), TEAM / 2);
        vm.warp(s + PERIOD);
        assertEq(vesting.releasable(), TEAM * 3 / 4);
        vm.warp(s + PERIOD * 2);
        assertEq(vesting.releasable(), TEAM * 7 / 8);
        vm.warp(s + PERIOD * 7); // 8回目 = 全量
        assertEq(vesting.releasable(), TEAM);
    }

    function test_ReleaseAlwaysGoesToBeneficiary() public {
        vm.warp(vesting.start());
        vm.prank(makeAddr("stranger"));
        vesting.release();
        assertEq(token.balanceOf(team), TEAM / 2);

        vm.warp(vesting.start() + PERIOD);
        vesting.release();
        assertEq(token.balanceOf(team), TEAM * 3 / 4);
        assertEq(vesting.releasable(), 0);

        vm.warp(vesting.start() + PERIOD * 100);
        vesting.release();
        assertEq(token.balanceOf(team), TEAM);
        assertEq(token.balanceOf(address(vesting)), 0);
    }
}
