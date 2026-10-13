#!/usr/bin/env bash
# 使い方: ./deploy.sh <コイン名> <dry-run|base_sepolia|base>
#   例: ./deploy.sh seppuku dry-run       # ローカルで試すだけ（送信しない）
#       ./deploy.sh seppuku base_sepolia  # テストネット（coin.testnet.env の上書きを使う）
#       ./deploy.sh seppuku base          # 本番
set -euo pipefail
cd "$(dirname "$0")"
source scripts-env.sh "$@"

if [ "$network" = "dry-run" ]; then
  forge script script/Deploy.s.sol
else
  confirm_mainnet "$TOKEN_NAME ($TOKEN_SYMBOL) をデプロイ"
  # shellcheck disable=SC2086
  forge script script/Deploy.s.sol --rpc-url "$network" $signer_args --broadcast $verify_args
fi
