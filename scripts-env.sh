# deploy.sh と add-liquidity.sh が読み込む共通処理（直接は実行しない）
# 使い方: source scripts-env.sh <コイン名> <ネットワーク>
usage="使い方: $0 <コイン名> <dry-run|base_sepolia|base>"
coin="${1:?$usage}"
network="${2:?$usage}"
cfg="coins/$coin/coin.env"
[ -f "$cfg" ] || { echo "見つかりません: $cfg" >&2; exit 1; }

set -a
[ -f .env ] && source .env
source "$cfg"
# テストネットでは coin.testnet.env で上書きする（半減期の短縮など）
if [ "$network" = "base_sepolia" ] && [ -f "coins/$coin/coin.testnet.env" ]; then
  source "coins/$coin/coin.testnet.env"
  echo "テストネット用の設定 coins/$coin/coin.testnet.env を使います"
fi
set +a

# 本番では実行前に確認する
confirm_mainnet() {
  if [ "$network" = "base" ]; then
    read -r -p "本番（Base Mainnet）で実行します: $1 よろしいですか？ [y/N] " ans
    [ "$ans" = "y" ] || { echo "中止しました"; exit 1; }
  fi
}

# 署名の方法（通常は cast wallet import で登録したキーストア）。
# ローカルの試験チェーン（anvil）で通しのリハーサルをするときだけ、FORGE_SIGNER_ARGS で差し替える。
signer_args="${FORGE_SIGNER_ARGS:---account ${DEPLOYER_ACCOUNT:-deployer}}"
verify_args="--verify"
[ -n "${NO_VERIFY:-}" ] && verify_args=""
