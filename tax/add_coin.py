#!/usr/bin/env python3
"""デプロイと流動性の追加が終わったコインを、税務記録の設定ファイルに書き足す。

送信記録（broadcast/Deploy.s.sol と broadcast/AddLiquidity.s.sol の run-latest.json）から、
トークン、プール、LP ポジション（NFT）の番号と手数料の受取人、半減期ロックと受取人を読み取る。
受取人のアドレスは、設定ファイルの owners の wallets と突き合わせて、メンバーに割り当てる。

使い方: python3 tax/add_coin.py <チェーン ID> <設定ファイル> <記号>
  例: python3 tax/add_coin.py 8453 private/tax/config.mainnet.json SEPPUKU
- 同じトークンが既に書かれていれば、上書きする
- start_block が 0 のときは、デプロイしたブロックにする
- from_block（デプロイしたブロック）も書く。記録が既にその先まで進んでいても、ledger.py が次の実行で
  このコインの分だけさかのぼって読む
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
POSITION_MANAGERS = {
    "8453": "0x03a520b32c04bf3beef7beb72e919cf822ed34f1",
    "84532": "0x27f971cb582bf9e50f397e4d29a5c7a34f11faa2",
}
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
LOCKED = "0x748bbc70c40b2e3e3b828688a7a7d8c2afb1e06ebe33406a029f4e985f94e07a"  # PermanentLPLock.Locked(tokenId, beneficiary)
POOL_CREATED = "0x783cca1c0412dd0d695e784568c96da2e9c22ff989357a2e8b1d9b2b4e6b7118"  # UniswapV3Factory.PoolCreated
ZERO = "0x" + "0" * 64


def load(script, chain):
    return json.loads((ROOT / "broadcast" / script / chain / "run-latest.json").read_text())


def main():
    chain, config_path, symbol = sys.argv[1], Path(sys.argv[2]), sys.argv[3]
    config = json.loads(config_path.read_text())
    owner_of = {w.lower(): name for name, o in config["owners"].items() for w in o["wallets"]}

    def owner(address):
        name = owner_of.get(address.lower())
        if not name:
            sys.exit(f"{address} が設定ファイルの owners のどのウォレットにもありません。先に wallets に足してください。")
        return name

    deploy = load("Deploy.s.sol", chain)
    token = next(t["contractAddress"] for t in deploy["transactions"] if t["contractName"] == "MemeToken")
    vestings = {}
    for t in deploy["transactions"]:
        if t["contractName"] == "HalvingVesting" and t["transactionType"] == "CREATE":
            vestings[t["contractAddress"]] = owner(t["arguments"][1])  # constructor(token, beneficiary, ...)
    deploy_block = min(int(r["blockNumber"], 16) for r in deploy["receipts"])

    liquidity = load("AddLiquidity.s.sol", chain)
    npm = POSITION_MANAGERS[chain]
    pool, minted, locked = None, [], {}
    for receipt in liquidity["receipts"]:
        for log in receipt["logs"]:
            t = log["topics"]
            if t[0] == POOL_CREATED:
                pool = "0x" + log["data"][-40:]
            elif log["address"].lower() == npm and len(t) == 4 and t[0] == TRANSFER and t[1] == ZERO:
                minted.append((int(t[3], 16), "0x" + t[2][-40:]))
            elif len(t) == 3 and t[0] == LOCKED:
                locked[int(t[1], 16)] = "0x" + t[2][-40:]
    if pool is None:
        sys.exit("送信記録にプールの作成が見つかりません（既存のプールに足した場合は、手で pool を書いてください）")
    lp_positions = {str(tid): owner(locked.get(tid, holder)) for tid, holder in minted}

    entry = {"symbol": symbol, "token": token, "pool": pool, "lp_positions": lp_positions, "vestings": vestings,
             "from_block": deploy_block}
    coins = [c for c in config.get("coins", []) if c["token"].lower() != token.lower()]
    config["coins"] = coins + [entry]
    if not config.get("start_block"):
        config["start_block"] = deploy_block
    config.pop("_todo", None)
    config_path.write_text(json.dumps(config, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(entry, ensure_ascii=False, indent=2))
    print(f"{config_path} に書き足しました（start_block = {config['start_block']}）")


if __name__ == "__main__":
    main()
