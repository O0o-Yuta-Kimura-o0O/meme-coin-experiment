#!/usr/bin/env bash
# 使い方: ./add-liquidity.sh <コイン名> <base_sepolia|base> <トークンのアドレス>
#   デプロイしたウォレットが持つトークン全量で、Uniswap v3（手数料 1%）にプールを作る。
#   LIQUIDITY_MODE=single：ETH なしの片側流動性（開始時の FDV = START_FDV_ETH）
#   LIQUIDITY_MODE=full  ：トークン + LIQUIDITY_ETH の ETH をフルレンジで
#   LP_LOCK=permanent（既定）なら、ポジションを永久ロックに預け、LP_RECIPIENTS は手数料の受取人になる。
#   LP_LOCK=none なら、LP ポジション（NFT）は LP_RECIPIENTS（カンマ区切り。人数で均等に分けて人数分作る。空ならデプロイしたウォレット）へ。
set -euo pipefail
cd "$(dirname "$0")"
source scripts-env.sh "$1" "$2"
export TOKEN_ADDRESS="${3:?使い方: ./add-liquidity.sh <コイン名> <base_sepolia|base> <トークンのアドレス>}"
export LIQUIDITY_MODE="${LIQUIDITY_MODE:-full}"

if [ "$LIQUIDITY_MODE" = "single" ]; then
  : "${START_FDV_ETH:?coin.env に START_FDV_ETH（開始時の時価総額、ETH 建て）を設定してください}"
  supply_wei="$(cast to-wei "$TOTAL_SUPPLY")"
  # 価格帯と初期価格を計算して環境変数にする（TICK_LOWER / TICK_UPPER / INIT_SQRT_PRICE_X96）
  while IFS='=' read -r key value; do
    export "$key=$value"
  done < <(python3 script/liquidity_params.py "$TOKEN_ADDRESS" "$supply_wei" "$START_FDV_ETH")
  echo "片側流動性：開始時の FDV ${START_FDV_ETH} ETH、tick ${TICK_LOWER} 〜 ${TICK_UPPER}"
  confirm_mainnet "ETH なしの片側流動性（開始時の FDV ${START_FDV_ETH} ETH）でプールを作成"
else
  export LIQUIDITY_ETH_WEI
  LIQUIDITY_ETH_WEI="$(cast to-wei "$LIQUIDITY_ETH")"
  confirm_mainnet "$LIQUIDITY_ETH ETH と全トークンで流動性を追加"
fi

# shellcheck disable=SC2086
forge script script/AddLiquidity.s.sol --rpc-url "$network" $signer_args --broadcast $verify_args || {
  # 送信は成功していて、ソースコードの検証の確認だけが失敗することがある（Blockscout の回数制限など）
  echo "（注意）上でエラーが出ても、送信が成功していれば続きの表示を確認してください"
}

# 上のログの tokenId は送信前のシミュレーションの値。実際の番号を送信記録から表示する
chain_id="$(cast chain-id --rpc-url "$( [ "$network" = base ] && echo "$BASE_RPC_URL" || echo "$BASE_SEPOLIA_RPC_URL" )")"
echo ""
echo "== 実際に作られた LP ポジション（これを記録する）=="
python3 script/show_lp_nfts.py "$chain_id"
