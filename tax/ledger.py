#!/usr/bin/env python3
"""税務申告用の取引記録（メンバーごとの CSV）を、ブロックチェーンから作って追記し続ける。

- 何を記録するか：tax/README.md の「記録する出来事」を参照
- 前回どこまで読んだか（ブロック番号）、LP ポジションの持ち分、プールの価格、ETH の円相場を state.json に保存し、
  毎回その続きから読む。接続先は publicnode（1 回の問い合わせが 50,000 ブロックまで。設定の max_block_range）
- 円換算：ETH は CoinGecko の 1 時間ごとの円相場、コインはプールの価格 × ETH の円相場
- 標準ライブラリのみで動く。個人情報（誰のウォレットか）は設定ファイルにだけ書き、GitHub には上げない

使い方: python3 tax/ledger.py private/tax/config.testnet.json
"""

import csv
import json
import sys
import time
import urllib.request
from datetime import datetime, timedelta, timezone
from decimal import Decimal, getcontext
from pathlib import Path

getcontext().prec = 60

JST = timezone(timedelta(hours=9))
ZERO_ADDR = "0x" + "0" * 40
WETH = "0x4200000000000000000000000000000000000006"
FEE_PPM = 10_000  # 手数料 1%
Q96 = Decimal(2) ** 96
E18 = Decimal(10) ** 18

T_SWAP = "0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67"
T_INIT = "0x98636036cb66a9c19a37435efc1e90142190214e8abeb821bdba3f2990dd4c95"
T_INC = "0x3067048beee31b25b2f1681f88dac838c8bba36af25bfb2b7cf7473a5847e35f"
T_DEC = "0x26f6a048ee9138f2c0ce266f322cb99228e8d619ae2bff30c67f8dcf9d2377b4"
T_COLLECT = "0x40d0efd1a53d60ecbf40971b9daf7dc90178c3aadc7aab1765632738fa8b8f01"
T_TRANSFER = "0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef"
T_APPROVAL = "0x8c5be1e5ebec7d5bd14f71427d1e84f3dd0314c0f7b2291e5b200ac8c7c3b925"

COLUMNS = [
    "datetime_jst", "unix_time", "network", "owner", "coin", "category", "asset", "amount",
    "unit_price_jpy", "value_jpy", "eth_jpy", "tx_hash", "block", "note",
]


def log(msg):
    print(msg, file=sys.stderr)


# ---------------------------------------------------------------- RPC

class Rpc:
    def __init__(self, url):
        self.url = url
        self.id = 0

    def call(self, method, params):
        for attempt in range(6):
            self.id += 1
            body = json.dumps({"jsonrpc": "2.0", "id": self.id, "method": method, "params": params}).encode()
            req = urllib.request.Request(self.url, body, {"content-type": "application/json", "User-Agent": "seppuku-ledger/1.0"})
            try:
                with urllib.request.urlopen(req, timeout=60) as res:
                    data = json.load(res)
            except Exception as e:  # ネットワークの一時的な失敗
                log(f"  rpc retry ({e})")
                time.sleep(2 * (attempt + 1))
                continue
            if "error" in data:
                raise RuntimeError(data["error"])
            return data["result"]
        raise RuntimeError(f"rpc failed: {method}")


def pad(addr):
    return "0x" + addr.lower()[2:].rjust(64, "0")


def topic_addr(t):
    return "0x" + t[-40:]


def words(data):
    h = data[2:]
    return [int(h[i:i + 64], 16) for i in range(0, len(h), 64)]


def signed(v, bits=256):
    return v - (1 << bits) if v >= 1 << (bits - 1) else v


# ---------------------------------------------------------------- 価格

class Prices:
    """ETH の円相場（1 時間ごと）。CoinGecko から取り、state に残す（90 日を過ぎると日次しか取れないため）"""

    def __init__(self, cache):
        self.cache = cache  # {hour_unix(str): jpy}

    def ensure(self, ts_from, ts_to):
        need = [h for h in range(ts_from // 3600 * 3600, ts_to // 3600 * 3600 + 3600, 3600) if str(h) not in self.cache]
        if not need:
            return
        # 範囲が短いと（直近の数時間だけなど）値が返らないことがあるため、前に 2 日広げて問い合わせる
        url = (
            "https://api.coingecko.com/api/v3/coins/ethereum/market_chart/range"
            f"?vs_currency=jpy&from={need[0] - 2 * 86400}&to={need[-1] + 3600}"
        )
        for attempt in range(5):
            try:
                with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": "seppuku-ledger"}), timeout=60) as res:
                    points = json.load(res)["prices"]
                if points:
                    break
                log("  coingecko returned no prices; retrying")
                time.sleep(15 * (attempt + 1))
            except Exception as e:
                log(f"  coingecko retry ({e})")
                time.sleep(15 * (attempt + 1))
        else:
            raise RuntimeError("could not fetch ETH/JPY prices")
        for h in need:
            nearest = min(points, key=lambda p: abs(p[0] / 1000 - h))
            self.cache[str(h)] = round(nearest[1], 2)

    def eth_jpy(self, ts):
        return Decimal(str(self.cache[str(ts // 3600 * 3600)]))


# ---------------------------------------------------------------- 本体

class Ledger:
    def __init__(self, config_path):
        self.config_path = Path(config_path).resolve()
        self.cfg = json.loads(self.config_path.read_text(encoding="utf-8"))
        self.dir = self.config_path.parent / self.cfg["output_dir"]
        self.dir.mkdir(parents=True, exist_ok=True)
        self.state_path = self.dir / "state.json"
        self.state = json.loads(self.state_path.read_text()) if self.state_path.exists() else {}
        self.rpc = Rpc(self.cfg["rpc"])
        self.prices = Prices(self.state.setdefault("eth_jpy_hourly", {}))
        self.network = self.cfg["network"]

        self.wallet_owner = {}
        for owner, o in self.cfg["owners"].items():
            for w in o["wallets"]:
                self.wallet_owner[w.lower()] = owner
        self.coins = []
        for c in self.cfg["coins"]:
            c = dict(c)
            c["token"] = c["token"].lower()
            c["pool"] = c["pool"].lower()
            c["token_is0"] = c["token"] < WETH.lower()
            c["positions"] = {str(k): v for k, v in c["lp_positions"].items()}
            c["vestings"] = {k.lower(): v for k, v in c["vestings"].items()}
            self.coins.append(c)
        self.npm = self.cfg["position_manager"].lower()
        self.ts_cache = {}
        self.state.pop("ts_ref", None)  # 以前の推計用の基準点（使わなくなった）

    # ---- ブロックと時刻
    # ブロックの間隔は一定ではない（Base Sepolia は 2026 年 10 月に 2 秒から約 0.2 秒になった）ため、
    # 推計せず、ブロックごとの実際の時刻を使う
    def block_ts(self, block):
        if block not in self.ts_cache:
            b = self.rpc.call("eth_getBlockByNumber", [hex(block), False])
            self.ts_cache[block] = int(b["timestamp"], 16)
        return self.ts_cache[block]

    # ---- ログの取得（範囲は max_block_range ずつ。断られたら縮める）
    def logs(self, frm, to, flt):
        out, start, span = [], frm, self.cfg.get("max_block_range", 200)
        while start <= to:
            end = min(start + span - 1, to)
            try:
                out += self.rpc.call("eth_getLogs", [dict(flt, fromBlock=hex(start), toBlock=hex(end))])
                start = end + 1
            except RuntimeError as e:
                if span <= 10:
                    raise
                span //= 2
                log(f"  shrinking range to {span} ({e})")
        return out

    def fetch(self, frm, to):
        owners = [pad(w) for w in self.wallet_owner]
        tokens = [c["token"] for c in self.coins] + [WETH.lower()]
        contracts = [c["pool"] for c in self.coins] + [v for c in self.coins for v in c["vestings"]]
        ids = ["0x" + hex(int(i))[2:].rjust(64, "0") for c in self.coins for i in c["positions"]]
        logs = []
        logs += self.logs(frm, to, {"address": contracts})
        if ids:
            logs += self.logs(frm, to, {"address": self.npm, "topics": [[T_INC, T_DEC, T_COLLECT], ids]})
        logs += self.logs(frm, to, {"address": tokens, "topics": [[T_TRANSFER, T_APPROVAL], owners]})
        logs += self.logs(frm, to, {"address": tokens, "topics": [T_TRANSFER, None, owners]})
        seen, uniq = set(), []
        for lg in logs:
            key = (lg["transactionHash"], lg["logIndex"])
            if key not in seen:
                seen.add(key)
                uniq.append(lg)
        uniq.sort(key=lambda lg: (int(lg["blockNumber"], 16), int(lg["logIndex"], 16)))
        return uniq

    # ---- 価格
    def coin_price_eth(self, coin):
        p = self.state.setdefault("pool_sqrt_price", {}).get(coin["pool"])
        if not p:
            return Decimal(0)
        ratio = (Decimal(p) / Q96) ** 2  # token1 / token0
        return ratio if coin["token_is0"] else (Decimal(1) / ratio if ratio else Decimal(0))

    def unit_jpy(self, asset, coin, ts):
        eth = self.prices.eth_jpy(ts)
        if asset in ("ETH", "WETH"):
            return eth
        return self.coin_price_eth(coin) * eth

    # ---- 記録の行
    def row(self, rows, lg, owner, coin, category, asset, amount_wei, note=""):
        if not owner or amount_wei == 0:
            return
        block = int(lg["blockNumber"], 16)
        ts = self.block_ts(block)
        amount = Decimal(amount_wei) / E18
        price = self.unit_jpy(asset, coin, ts)
        rows.append({
            "datetime_jst": datetime.fromtimestamp(ts, JST).strftime("%Y-%m-%d %H:%M:%S"),
            "unix_time": ts,
            "network": self.network,
            "owner": owner,
            "coin": coin["symbol"] if coin else "",
            "category": category,
            "asset": asset,
            "amount": f"{amount:.18f}".rstrip("0").rstrip("."),
            "unit_price_jpy": f"{price:.10f}".rstrip("0").rstrip("."),
            "value_jpy": f"{amount * price:.2f}",
            "eth_jpy": f"{self.prices.eth_jpy(ts):.2f}",
            "tx_hash": lg["transactionHash"],
            "block": block,
            "note": note,
        })

    def asset_of(self, coin, is_token0):
        return coin["symbol"] if is_token0 == coin["token_is0"] else "WETH"

    # ---- 1 回分の処理
    def process(self, logs):
        rows = []
        positions = self.state.setdefault("positions", {})  # tokenId -> {"liquidity": int, "lower": int, "upper": int}
        sqrt_prices = self.state.setdefault("pool_sqrt_price", {})
        by_tx = {}
        for lg in logs:
            by_tx.setdefault(lg["transactionHash"], []).append(lg)
        coin_by_pool = {c["pool"]: c for c in self.coins}
        coin_by_token = {c["token"]: c for c in self.coins}

        if logs:
            for lg in logs:  # RPC が時刻を返すときは、それを使う（問い合わせを減らすため）
                if lg.get("blockTimestamp"):
                    self.ts_cache[int(lg["blockNumber"], 16)] = int(lg["blockTimestamp"], 16)
            ts = [self.block_ts(int(lg["blockNumber"], 16)) for lg in logs]
            self.prices.ensure(min(ts), max(ts))

        for tx, tx_logs in by_tx.items():
            swap_txs = {lg["address"].lower() for lg in tx_logs if lg["topics"][0] == T_SWAP}
            inc_in_tx = any(lg["topics"][0] == T_INC for lg in tx_logs)
            collect_in_tx = any(lg["topics"][0] == T_COLLECT and lg["address"].lower() == self.npm for lg in tx_logs)
            owner_traded = set()

            for lg in tx_logs:
                addr, t0 = lg["address"].lower(), lg["topics"][0]

                # --- プールの価格と、LP ポジションの持ち分に応じた交換・手数料
                if addr in coin_by_pool and t0 == T_INIT:
                    sqrt_prices[addr] = str(words(lg["data"])[0])
                elif addr in coin_by_pool and t0 == T_SWAP:
                    coin = coin_by_pool[addr]
                    w = words(lg["data"])
                    d0, d1 = signed(w[0]), signed(w[1])
                    sqrt_prices[addr] = str(w[2])
                    active, tick = w[3], signed(w[4])  # ABI では int24 も 256 ビットに符号拡張されている
                    for tid, owner in coin["positions"].items():
                        p = positions.get(tid)
                        if not p or not active or not (p["lower"] <= tick < p["upper"]):
                            continue
                        share = Decimal(p["liquidity"]) / Decimal(active)
                        for is0, d in ((True, d0), (False, d1)):
                            asset = self.asset_of(coin, is0)
                            if d > 0:  # プールに入った側（手数料を含む）
                                fee = Decimal(d) * FEE_PPM / 1_000_000
                                self.row(rows, lg, owner, coin, "lp_swap", asset, int((Decimal(d) - fee) * share),
                                         f"LP #{tid} の持ち分 {share:.6f}")
                                self.row(rows, lg, owner, coin, "lp_fee", asset, int(fee * share),
                                         f"LP #{tid} に発生した取引手数料の持ち分")
                            elif d < 0:
                                self.row(rows, lg, owner, coin, "lp_swap", asset, int(Decimal(d) * share),
                                         f"LP #{tid} の持ち分 {share:.6f}")
                    # この取引をメンバー自身のウォレットが行ったか（コインの受け渡しで判定）
                    for x in tx_logs:
                        if x["address"].lower() == coin["token"] and x["topics"][0] == T_TRANSFER:
                            frm, to = topic_addr(x["topics"][1]), topic_addr(x["topics"][2])
                            trader = self.wallet_owner.get(to if frm == addr else frm if to == addr else "")
                            if trader and (frm == addr or to == addr):
                                owner_traded.add((trader, addr))
                    for trader, pool in owner_traded:
                        if pool != addr:
                            continue
                        for is0, d in ((True, d0), (False, d1)):
                            self.row(rows, lg, trader, coin, "trade", self.asset_of(coin, is0), -d,
                                     "自分のウォレットでの売買（このプール）")

                # --- LP ポジションの増減と回収
                elif addr == self.npm and t0 in (T_INC, T_DEC, T_COLLECT):
                    tid = str(int(lg["topics"][1], 16))
                    coin = next(c for c in self.coins if tid in c["positions"])
                    owner = coin["positions"][tid]
                    w = words(lg["data"])
                    p = positions.setdefault(tid, self.position_range(tid))
                    if t0 == T_INC:
                        p["liquidity"] += w[0]
                        self.row(rows, lg, owner, coin, "lp_position_in", self.asset_of(coin, True), w[1],
                                 f"LP #{tid} へ元本が入った")
                        self.row(rows, lg, owner, coin, "lp_position_in", self.asset_of(coin, False), w[2],
                                 f"LP #{tid} へ元本が入った")
                    elif t0 == T_DEC:
                        p["liquidity"] -= w[0]
                    else:  # Collect：ポジションからウォレットへ
                        self.row(rows, lg, owner, coin, "lp_withdraw", self.asset_of(coin, True), w[1],
                                 f"LP #{tid} から回収（元本と手数料を含む）")
                        self.row(rows, lg, owner, coin, "lp_withdraw", self.asset_of(coin, False), w[2],
                                 f"LP #{tid} から回収（元本と手数料を含む）")

                # --- コイン・WETH の受け渡し
                elif t0 == T_TRANSFER and (addr in coin_by_token or addr == WETH.lower()):
                    coin = coin_by_token.get(addr) or (self.coins[0] if self.coins else None)
                    asset = coin_by_token[addr]["symbol"] if addr in coin_by_token else "WETH"
                    frm, to = topic_addr(lg["topics"][1]), topic_addr(lg["topics"][2])
                    amount = words(lg["data"])[0]
                    fo, to_owner = self.wallet_owner.get(frm), self.wallet_owner.get(to)
                    pools = {c["pool"] for c in self.coins}
                    # 自分のプールでの売買は "trade" で記録済み
                    if (frm in pools or to in pools) and (fo or to_owner) and (frm in swap_txs or to in swap_txs):
                        continue
                    # LP ポジションからの回収で、プールからウォレットへ届いた分は "lp_withdraw" で記録済み
                    if frm in pools and to_owner and collect_in_tx:
                        continue
                    vest_owner = next((c["vestings"][a] for c in self.coins for a in (frm, to) if a in c["vestings"]), None)
                    if frm == ZERO_ADDR:
                        self.row(rows, lg, to_owner, coin, "issuance", asset, amount, "発行（取得価額は 0）")
                    elif to in pools and inc_in_tx:
                        self.row(rows, lg, fo, coin, "lp_deposit", asset, -amount, "ウォレットから流動性へ預け入れ")
                    elif fo and vest_owner and to not in self.wallet_owner:
                        self.row(rows, lg, fo, coin, "vesting_lock", asset, -amount, f"半減期ロック（受取人: {vest_owner}）へ割当")
                    elif to_owner and frm in {v for c in self.coins for v in c["vestings"]}:
                        self.row(rows, lg, to_owner, coin, "vesting_release", asset, amount, "半減期ロックから受け取り")
                    elif fo and to_owner:
                        if fo != to_owner:
                            self.row(rows, lg, fo, coin, "partner_transfer", asset, -amount, f"{to_owner} へ送付")
                            self.row(rows, lg, to_owner, coin, "partner_transfer", asset, amount, f"{fo} から受け取り")
                    else:
                        self.row(rows, lg, fo, coin, "transfer_out", asset, -amount, f"送付先 {to}")
                        self.row(rows, lg, to_owner, coin, "transfer_in", asset, amount, f"送付元 {frm}")

            # --- メンバーが送信した取引の手数料（経費）。メンバーが関わる取引だけ調べる（他人の売買は除く）
            involved = any(
                lg["address"].lower() in coin_by_token
                or lg["address"].lower() in (WETH.lower(), self.npm)
                or any(lg["address"].lower() in c["vestings"] for c in self.coins)
                for lg in tx_logs
            )
            if involved:
                self.gas_row(rows, tx, tx_logs[0])
        return rows

    def position_range(self, tid):
        data = "0x99fbab88" + hex(int(tid))[2:].rjust(64, "0")  # positions(uint256)
        w = words(self.rpc.call("eth_call", [{"to": self.npm, "data": data}, "latest"]))
        return {"liquidity": 0, "lower": signed(w[5]), "upper": signed(w[6])}

    def gas_row(self, rows, tx, lg):
        r = self.rpc.call("eth_getTransactionReceipt", [tx])
        owner = self.wallet_owner.get(r["from"].lower())
        if not owner:
            return
        fee = int(r["gasUsed"], 16) * int(r["effectiveGasPrice"], 16) + int(r.get("l1Fee", "0x0"), 16)
        self.row(rows, lg, owner, None, "gas_fee", "ETH", -fee, f"送信元 {r['from']}（経費）")

    # ---- 実行
    def backfill(self):
        """読み終えたブロックより後から設定に足したコイン（from_block 付き）を、そのコインだけ過去にさかのぼって読む。"""
        done = set(self.state.setdefault("backfilled", []))
        nxt = self.state.get("next_block")
        rows = []
        for coin in [c for c in self.coins if c.get("from_block") is not None and c["token"] not in done]:
            if nxt is not None and coin["from_block"] < nxt:
                log(f"[{self.network}] backfill {coin['symbol']}: blocks {coin['from_block']} .. {nxt - 1}")
                everything, self.coins = self.coins, [coin]
                try:
                    rows += [r for r in self.process(self.fetch(coin["from_block"], nxt - 1))
                             if r["coin"] in (coin["symbol"], "")]
                finally:
                    self.coins = everything
            self.state["backfilled"].append(coin["token"])
        return rows

    def write_rows(self, rows):
        for owner in self.cfg["owners"]:
            path = self.dir / f"{owner}.csv"
            seen = set()
            if path.exists():
                with path.open(newline="", encoding="utf-8") as f:
                    seen = {(r["tx_hash"], r["category"], r["asset"], r["amount"]) for r in csv.DictReader(f)}
            # 同じ取引の同じ記録を二重に書かない（過去にさかのぼって読んだときのため）
            mine = [r for r in rows if r["owner"] == owner
                    and (r["tx_hash"], r["category"], r["asset"], r["amount"]) not in seen]
            new = not path.exists()
            with path.open("a", newline="", encoding="utf-8") as f:
                w = csv.DictWriter(f, fieldnames=COLUMNS)
                if new:
                    w.writeheader()
                w.writerows(mine)
            log(f"  {owner}: +{len(mine)} rows -> {path}")

    def run(self):
        latest = int(self.rpc.call("eth_blockNumber", []), 16) - self.cfg.get("confirmations", 10)
        rows = self.backfill()
        frm = self.state.get("next_block", self.cfg["start_block"])
        if frm <= latest:
            log(f"[{self.network}] blocks {frm} .. {latest}")
            rows += self.process(self.fetch(frm, latest))
            self.state["next_block"] = latest + 1
        else:
            log("up to date")
        self.write_rows(rows)
        self.state_path.write_text(json.dumps(self.state, indent=1, ensure_ascii=False))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    Ledger(sys.argv[1]).run()
