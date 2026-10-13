#!/usr/bin/env bash
# 使い方: ./deploy.sh <コイン名> <dry-run|base_sepolia|base>
#   例: ./deploy.sh seppuku dry-run       # ローカルで試すだけ（送信しない）
#       ./deploy.sh seppuku base_sepolia  # テストネット
#       ./deploy.sh seppuku base          # 本番
set -euo pipefail
cd "$(dirname "$0")"

coin="${1:?使い方: ./deploy.sh <コイン名> <dry-run|base_sepolia|base>}"
network="${2:?使い方: ./deploy.sh <コイン名> <dry-run|base_sepolia|base>}"
cfg="coins/$coin/coin.env"
[ -f "$cfg" ] || { echo "見つかりません: $cfg" >&2; exit 1; }

set -a
[ -f .env ] && source .env
source "$cfg"
set +a

if [ "$network" = "dry-run" ]; then
  forge script script/Deploy.s.sol
else
  forge script script/Deploy.s.sol --rpc-url "$network" --account "${DEPLOYER_ACCOUNT:-deployer}" --broadcast --verify
fi
