// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {MemeToken} from "../src/MemeToken.sol";
import {HalvingVesting} from "../src/HalvingVesting.sol";

/// @notice トークン発行 → チーム分を半減期ベスティングへ → コミュニティ分を送付。
///         流動性分（LIQUIDITY_PCT）はデプロイしたウォレットに残るので、
///         その後 Uniswap / Aerodrome の画面でプールを作成する（README 参照）。
contract Deploy is Script {
    function run() external {
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");
        uint256 supply = vm.envUint("TOTAL_SUPPLY") * 1e18;

        uint256 liquidityPct = vm.envUint("LIQUIDITY_PCT");
        uint256 teamPct = vm.envUint("TEAM_PCT");
        uint256 communityPct = vm.envUint("COMMUNITY_PCT");
        require(liquidityPct + teamPct + communityPct == 100, "pct must sum to 100");

        address teamWallet = vm.envAddress("TEAM_WALLET");
        address communityWallet = vm.envAddress("COMMUNITY_WALLET");

        uint64 cliff = uint64(vm.envUint("VESTING_CLIFF_DAYS") * 1 days);
        uint64 period = uint64(vm.envUint("VESTING_PERIOD_DAYS") * 1 days);
        uint8 halvings = uint8(vm.envUint("VESTING_HALVINGS"));

        vm.startBroadcast();
        address deployer = msg.sender;

        MemeToken token = new MemeToken(name, symbol, supply, deployer);

        HalvingVesting vesting =
            new HalvingVesting(token, teamWallet, uint64(block.timestamp) + cliff, period, halvings);

        uint256 teamAmount = supply * teamPct / 100;
        uint256 communityAmount = supply * communityPct / 100;
        if (teamAmount > 0) token.transfer(address(vesting), teamAmount);
        if (communityAmount > 0) token.transfer(communityWallet, communityAmount);

        vm.stopBroadcast();

        console2.log("Token          :", address(token));
        console2.log("HalvingVesting :", address(vesting));
        console2.log("Liquidity left in deployer:", token.balanceOf(deployer) / 1e18);
    }
}
