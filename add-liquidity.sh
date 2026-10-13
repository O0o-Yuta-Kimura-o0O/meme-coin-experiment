#!/usr/bin/env bash
# 使い方: ./add-liquidity.sh <コイン名> <base_sepolia|base> <トークンのアドレス>
#   デプロイしたウォレットが持つトークン全量と、coin.env の LIQUIDITY_ETH の ETH で
#   Uniswap v3 にプール（手数料 1%、フルレンジ）を作る。LP ポジション（NFT）は LP_RECIPIENT へ。
set -euo pipefail
cd "$(dirname "$0")"
source scripts-env.sh "$1" "$2"
export TOKEN_ADDRESS="${3:?使い方: ./add-liquidity.sh <コイン名> <base_sepolia|base> <トークンのアドレス>}"
export LIQUIDITY_ETH_WEI
LIQUIDITY_ETH_WEI="$(cast to-wei "$LIQUIDITY_ETH")"

confirm_mainnet "$LIQUIDITY_ETH ETH と全トークンで流動性を追加"
# shellcheck disable=SC2086
forge script script/AddLiquidity.s.sol --rpc-url "$network" $signer_args --broadcast
