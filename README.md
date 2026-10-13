# SEPPUKU（$SEPPUKU）

**Base**（Coinbase が運営するイーサリアムのレイヤー2）上で発行する、維持費がほぼかからない ERC-20 ミームコインです。

このファイルでは、設計とデプロイの手順を説明します。

## 設計（PEPE 型 + ビットコイン風の半減期）

| 項目 | 内容 |
|---|---|
| 規格 | ERC-20（OpenZeppelin v5.4）+ Burnable + Permit |
| 発行枚数 | 1,000,000,000（10億）※ `.env` で変更可。デプロイ時に全量を発行し、追加発行はできない |
| 管理者権限 | **なし**（オーナーなし、mint なし、一時停止なし、ブラックリストなし、売買税なし） |
| 配分 | 流動性（DEX）90% / チーム 5% / コミュニティ・エアドロップ 5% |
| 半減期 | チーム分は `HalvingVesting` でロック。クリフ（90日）明けに 50%、その後 180 日ごとに残りの半分ずつ解放され、8 回目で全量解放 |
| 維持費 | **0円**。運営が動かすサーバーや定期処理はなく、ガス代は取引する人が払う |

ビットコインの半減期はマイニング報酬が半分になっていく仕組みですが、ミームコインにはマイニングがありません。そこで「**発行者の売れる量が半減期ごとに減っていく**」形にしました。発行者が一気に売り抜けできないことをコントラクトで保証するので、買う人を安心させる材料（話題）になります。

```
チーム分の解放スケジュール（5% = 5,000万枚 の場合）
 90日後 ─ 50%   (2,500万枚)
270日後 ─ 75%
450日後 ─ 87.5%
   ...
 約3.7年後 ─ 100%
```

## ファイル構成

```
src/MemeToken.sol        トークン本体（約20行。シンプルなほど監査・信頼の面で有利）
src/HalvingVesting.sol   半減期型のチーム分ロック
script/Deploy.s.sol      デプロイと配分を一括で行うスクリプト
test/MemeCoin.t.sol      テスト（5件、すべて通過）
.env.example             設定のテンプレート
```

## 手順

### 0. 準備

```bash
curl -L https://foundry.paradigm.xyz | bash && foundryup
```

```bash
forge install && forge test
```

デプロイ用のウォレットを、暗号化したキーストアとして登録します（秘密鍵を `.env` に書かないため）。

```bash
cast wallet import deployer --interactive
```

```bash
cp .env.example .env
```

`.env` を開いて、名前・シンボル・`TEAM_WALLET`・`COMMUNITY_WALLET` を記入します。`TEAM_WALLET` は**後から変更できません**。ハードウェアウォレットか [Safe](https://app.safe.global) のマルチシグにしてください。

### 1. テストネット（Base Sepolia）で本番と同じ手順を試す

テストネット用の ETH は faucet（無料配布サイト）で入手します。

```bash
source .env && forge script script/Deploy.s.sol --rpc-url base_sepolia --account deployer --broadcast --verify
```

### 2. 本番（Base Mainnet）

```bash
source .env && forge script script/Deploy.s.sol --rpc-url base --account deployer --broadcast --verify
```

デプロイのガス代は通常 **1ドル未満** です。`--verify` を付けると、Basescan でソースコードが公開・検証されます（信頼を得るために必須）。

### 3. DEX に流動性を追加する（ここで取引が始まる）

デプロイしたウォレットに 90%（9億枚）が残っています。これと ETH をペアにしてプールを作ります。

- **Uniswap**（app.uniswap.org → Base を選択 → Pool → 新規作成）: 手数料 1%、価格帯はフルレンジ
- **Aerodrome**（Base で最大の DEX）: Volatile プール

**初期の時価総額 ≒ 入れた ETH ÷ 0.9** になります。例えば 9億枚 + 1 ETH で始めると、時価総額は約 1.1 ETH です。入れる ETH が少ないと価格がすぐ大きく動き、bot に狙われやすくなります。

### 4. 流動性をロックする（強く推奨）

LP（流動性ポジション）を UNCX や Team Finance などのロッカーで 1 年以上ロックし、そのリンクを公開します。ロックしない場合、「いつでも流動性を抜ける＝ラグプルできる」と判断され、ほとんど買われません。Uniswap v3/v4 のポジションは、ロッカーによってはロック中も**手数料だけは受け取れます**。

### 5. 公開したあと

- DexScreener / GeckoTerminal にはプールが自動で表示されます。DexScreener のトークン情報（ロゴ・SNS リンク）を登録すると、目立ちやすくなります（有料）
- CoinGecko / CoinMarketCap への掲載申請（無料、審査あり）
- X（Twitter）、Farcaster、Telegram でコミュニティを作る

## 安全性について

- コントラクトに管理者機能がないので、**デプロイしたあとは誰にも（発行者自身にも）変更できません**。ハニーポットチェッカーや Token Sniffer で「安全」と判定されやすい構成です
- 一方で、バグを見つけても修正できません。必ずテストネットで一通り試してください
- 大きな金額を扱う前に、第三者による監査を検討してください
