// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {HalvingVesting} from "../src/HalvingVesting.sol";

/// @notice デプロイスクリプトが、チーム分を人数で均等に分けて別々の半減期ロックに入れることを確かめる
contract DeployScriptTest is Test {
    address kimura = makeAddr("kimura");
    address torima = makeAddr("torima");
    address community = makeAddr("community");

    function setUp() public {
        vm.setEnv("TOKEN_NAME", "SEPPUKU COIN");
        vm.setEnv("TOKEN_SYMBOL", "SEPPUKU");
        vm.setEnv("TOTAL_SUPPLY", "1000000000");
        vm.setEnv("LIQUIDITY_PCT", "90");
        vm.setEnv("TEAM_PCT", "5");
        vm.setEnv("COMMUNITY_PCT", "5");
        vm.setEnv("COMMUNITY_WALLET", vm.toString(community));
        vm.setEnv("VESTING_CLIFF_DAYS", "90");
        vm.setEnv("VESTING_PERIOD_DAYS", "180");
        vm.setEnv("VESTING_HALVINGS", "8");
    }

    function _twoMembers() internal {
        vm.setEnv("TEAM_WALLETS", string.concat(vm.toString(kimura), ",", vm.toString(torima)));
        (MemeToken token, HalvingVesting[] memory v) = new Deploy().run();

        assertEq(v.length, 2);
        assertEq(v[0].beneficiary(), kimura);
        assertEq(v[1].beneficiary(), torima);
        assertEq(token.balanceOf(address(v[0])), 25_000_000e18);
        assertEq(token.balanceOf(address(v[1])), 25_000_000e18);
        assertEq(token.balanceOf(community), 50_000_000e18);

        // 二人とも同じスケジュール：90日後に、それぞれ自分の半分（1,250万枚）だけを受け取れる
        vm.warp(v[0].start());
        v[0].release();
        v[1].release();
        assertEq(token.balanceOf(kimura), 12_500_000e18);
        assertEq(token.balanceOf(torima), 12_500_000e18);
    }

    // vm.setEnv は同時に走るテストの間で共有されるので、人数を変える確認は1つのテストの中で順に行う
    function test_SplitsTeamEquallyAmongMembers() public {
        _twoMembers();
        address third = makeAddr("third");
        vm.setEnv(
            "TEAM_WALLETS", string.concat(vm.toString(kimura), ",", vm.toString(torima), ",", vm.toString(third))
        );
        (MemeToken token, HalvingVesting[] memory v) = new Deploy().run();
        uint256 team = 50_000_000e18;
        assertEq(token.balanceOf(address(v[0])), team / 3 + team % 3);
        assertEq(token.balanceOf(address(v[1])), team / 3);
        assertEq(token.balanceOf(address(v[2])), team / 3);
    }
}
