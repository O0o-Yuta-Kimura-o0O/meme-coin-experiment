#!/usr/bin/env python3
"""add-liquidity.sh の送信後に、実際に作られた LP ポジション（NFT）の番号と持ち主を表示する。

forge script のログに出る番号は送信前のシミュレーションの値で、同じ時間に他の人がポジションを作ると
実際の番号とずれる。送信記録（broadcast/.../run-latest.json）の NFT の Transfer イベントから読み取る。

使い方: python3 script/show_lp_nfts.py <チェーン ID>
"""

import json
import sys
from pathlib import Path

POSITION_MANAGERS = {
    "8453": "0x03a520b32c04bf3beef7beb72e919cf822ed34f1",
    "84532": "0x27f971cb582bf9e50f397e4d29a5c7a34f11faa2",
}
TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
LOCKED = "0x748bbc70c40b2e3e3b828688a7a7d8c2afb1e06ebe33406a029f4e985f94e07a"  # PermanentLPLock.Locked(uint256 indexed tokenId, address indexed beneficiary)
ZERO = "0x" + "0" * 64


def main():
    chain = sys.argv[1]
    npm = POSITION_MANAGERS[chain]
    path = Path(__file__).resolve().parents[1] / "broadcast" / "AddLiquidity.s.sol" / chain / "run-latest.json"
    data = json.loads(path.read_text())
    minted, locked = [], {}
    for receipt in data.get("receipts", []):
        for log in receipt.get("logs", []):
            t = log.get("topics", [])
            if log["address"].lower() == npm and len(t) == 4 and t[0] == TRANSFER and t[1] == ZERO:
                minted.append((int(t[3], 16), "0x" + t[2][-40:]))
            elif len(t) == 3 and t[0] == LOCKED:
                locked[int(t[1], 16)] = ("0x" + t[2][-40:], log["address"])
    for tid, owner in minted:
        if tid in locked:
            beneficiary, lock = locked[tid]
            print(f"  実際の LP NFT : {tid} -> 永久ロック {lock}（手数料の受取人 {beneficiary}）")
        else:
            print(f"  実際の LP NFT : {tid} -> 持ち主 {owner}")


if __name__ == "__main__":
    main()
