// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {HalvingVesting} from "../src/HalvingVesting.sol";

/// @notice トークン発行 → チーム分を半減期ベスティングへ → コミュニティ分を送付。
///         流動性分（LIQUIDITY_PCT）はデプロイしたウォレットに残るので、
///         その後 Uniswap / Aerodrome の画面でプールを作成する（README 参照）。
///         設定値は coins/<コイン名>/coin.env から deploy.sh 経由で渡される。
contract Deploy is Script {
    struct Config {
        string name;
        string symbol;
        uint256 supply;
        uint256 liquidityPct;
        uint256 teamPct;
        uint256 communityPct;
        address teamWallet;
        address communityWallet;
        uint64 cliff;
        uint64 period;
        uint8 halvings;
    }

    function loadConfig() internal view returns (Config memory c) {
        c.name = vm.envString("TOKEN_NAME");
        c.symbol = vm.envString("TOKEN_SYMBOL");
        c.supply = vm.envUint("TOTAL_SUPPLY") * 1e18;

        c.liquidityPct = vm.envUint("LIQUIDITY_PCT");
        c.teamPct = vm.envUint("TEAM_PCT");
        c.communityPct = vm.envUint("COMMUNITY_PCT");
        require(c.liquidityPct + c.teamPct + c.communityPct == 100, "pct must sum to 100");

        c.teamWallet = vm.envAddress("TEAM_WALLET");
        c.communityWallet = vm.envAddress("COMMUNITY_WALLET");

        uint256 halvings = vm.envUint("VESTING_HALVINGS");
        uint256 periodDays = vm.envUint("VESTING_PERIOD_DAYS");
        require(halvings >= 1 && halvings <= 64, "VESTING_HALVINGS must be 1-64");
        require(periodDays > 0, "VESTING_PERIOD_DAYS must be > 0");
        // テストネット用：*_SECONDS があれば日数より優先する（半減期の動きを数時間で確かめるため）
        c.cliff = uint64(vm.envOr("VESTING_CLIFF_SECONDS", vm.envUint("VESTING_CLIFF_DAYS") * 1 days));
        c.period = uint64(vm.envOr("VESTING_PERIOD_SECONDS", periodDays * 1 days));
        require(c.period > 0, "vesting period must be > 0");
        c.halvings = uint8(halvings);
    }

    function run() external {
        Config memory c = loadConfig();

        vm.startBroadcast();
        address deployer = msg.sender;

        MemeToken token = new MemeToken(c.name, c.symbol, c.supply, deployer);

        HalvingVesting vesting =
            new HalvingVesting(token, c.teamWallet, uint64(block.timestamp) + c.cliff, c.period, c.halvings);

        uint256 teamAmount = c.supply * c.teamPct / 100;
        uint256 communityAmount = c.supply * c.communityPct / 100;
        if (teamAmount > 0) token.transfer(address(vesting), teamAmount);
        if (communityAmount > 0) token.transfer(c.communityWallet, communityAmount);

        vm.stopBroadcast();

        console2.log("Coin           :", c.name, c.symbol);
        console2.log("Supply         :", c.supply / 1e18);
        console2.log("Split L/T/C %  :", c.liquidityPct, c.teamPct, c.communityPct);
        console2.log("Token          :", address(token));
        console2.log("HalvingVesting :", address(vesting));
        console2.log("Liquidity left in deployer:", token.balanceOf(deployer) / 1e18);
    }
}
