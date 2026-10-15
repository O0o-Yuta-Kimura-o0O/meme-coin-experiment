#!/usr/bin/env python3
"""片側流動性（ETH を入れずにトークンだけでプールを作る）の価格帯を計算する。

開始時の時価総額（FDV、ETH 建て）から開始価格を決め、トークンを「開始価格より上（トークンが高くなる側）」の
全範囲に置く。買われるほど価格が上がり、プールに ETH がたまる。価格は開始価格より下がらない。

Uniswap v3 の価格は token1 / token0。トークンと WETH のどちらが token0 になるかはアドレスの大小で決まるので、
両方の場合を扱う。tick は手数料 1% の間隔（200）にそろえる。

使い方:
  python3 script/liquidity_params.py <トークンのアドレス> <総供給量（wei）> <開始時の FDV（ETH）>        # 環境変数の形で出力
  python3 script/liquidity_params.py <トークンのアドレス> <総供給量（wei）> <開始時の FDV（ETH）> --abi  # forge の vm.ffi 用
"""

import math
import sys
from decimal import Decimal, getcontext

getcontext().prec = 80

WETH = int("0x4200000000000000000000000000000000000006", 16)
TICK_SPACING = 200
MAX_TICK = 887_200  # 887272 を 200 の倍数に切り下げたもの
Q96 = 2**96


def sqrt_price_x96_at(tick: int) -> int:
    return int((Decimal("1.0001") ** tick).sqrt() * Q96)


def params(token: int, supply_wei: int, fdv_eth: Decimal):
    if supply_wei <= 0 or fdv_eth <= 0:
        raise ValueError("supply and FDV must be > 0")
    # 1 トークンあたりの ETH（どちらも小数点以下 18 桁なので、wei どうしの比 = 枚数どうしの比）
    eth_per_token = fdv_eth * Decimal(10**18) / Decimal(supply_wei)

    if token < WETH:
        # token0 = トークン、価格 = WETH / トークン。買われると価格は上がる → 範囲は開始価格より上
        start_tick = math.floor(math.log(eth_per_token) / math.log(1.0001))
        tick_lower = -(-start_tick // TICK_SPACING) * TICK_SPACING  # 200 の倍数に切り上げ
        tick_upper = MAX_TICK
        init_tick = tick_lower - TICK_SPACING // 2  # 範囲のすぐ下で初期化 → トークンだけで作れる
    else:
        # token1 = トークン、価格 = トークン / WETH。買われると価格は下がる → 範囲は開始価格より下
        start_tick = math.floor(math.log(1 / eth_per_token) / math.log(1.0001))
        tick_upper = (start_tick // TICK_SPACING) * TICK_SPACING  # 200 の倍数に切り下げ
        tick_lower = -MAX_TICK
        init_tick = tick_upper + TICK_SPACING // 2  # 範囲のすぐ上で初期化 → トークンだけで作れる

    if not (-MAX_TICK <= tick_lower < tick_upper <= MAX_TICK):
        raise ValueError("FDV is out of the representable price range")
    return tick_lower, tick_upper, sqrt_price_x96_at(init_tick)


def abi_word(value: int) -> str:
    return (value % 2**256).to_bytes(32, "big").hex()


def main():
    if len(sys.argv) < 4:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    token = int(sys.argv[1], 16)
    supply_wei = int(sys.argv[2])
    fdv_eth = Decimal(sys.argv[3])
    tick_lower, tick_upper, sqrt_price = params(token, supply_wei, fdv_eth)
    if "--abi" in sys.argv:
        print("0x" + abi_word(tick_lower) + abi_word(tick_upper) + abi_word(sqrt_price))
    else:
        print(f"TICK_LOWER={tick_lower}")
        print(f"TICK_UPPER={tick_upper}")
        print(f"INIT_SQRT_PRICE_X96={sqrt_price}")


if __name__ == "__main__":
    main()
