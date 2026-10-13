# meme-coin-experiment

**Base**（Coinbase が運営するイーサリアムのレイヤー2）上で、**仕様が同じで名前とストーリーだけが違う**ミームコインを複数発行し、市場での広がり方の違いを観察する実験プロジェクトです。

- すべてのコインが同じコントラクト（`src/`）を使います。違うのは `coins/<コイン名>/` の設定とストーリーだけです
- 研究の設計 → [research/README.md](research/README.md)

## コイン一覧

| コイン | ティッカー | 発行枚数 | 配分（流動性 / チーム / コミュニティ） | 半減期（クリフ / 間隔 / 回数） | 状態 | フォルダ |
|---|---|---|---|---|---|---|
| SEPPUKU | $SEPPUKU | 10億 | 90 / 5 / 5 | 90日 / 180日 / 8回 | 準備中 | [coins/seppuku](coins/seppuku) |

仕様の違い（発行枚数・配分・半減期）は、すべて各コインの `coin.env` で設定します。コントラクトのコードは全コイン共通です。

## 共通仕様（PEPE 型 + ビットコイン風の半減期）

| 項目 | 内容 |
|---|---|
| 規格 | ERC-20（OpenZeppelin v5.4）+ Burnable + Permit |
| 発行枚数 | 1,000,000,000（10億）※ `coin.env` で変更可。デプロイ時に全量を発行し、追加発行はできない |
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
src/MemeToken.sol         トークン本体（全コイン共通。約20行）
src/HalvingVesting.sol    半減期型のチーム分ロック（全コイン共通）
script/Deploy.s.sol       デプロイと配分を一括で行うスクリプト
test/MemeCoin.t.sol       テスト
deploy.sh                 コインを指定してデプロイするラッパー
.env.example              全コイン共通の秘密情報（RPC、API キー）のテンプレート
coins/
  _template/              新しいコインを作るときのひな形
  seppuku/
    coin.env              名前・発行枚数・配分・ウォレット・半減期
    README.md             コンセプト、ストーリー、リンク
    deployments.md        デプロイ記録（アドレス、日時、初期流動性）
    tracking.json         データ収集の対象（トークンのアドレス、サイトの URL、SNS アカウント、検索語）
research/                 研究の設計、データ、分析
  scripts/collect_snapshots.py   市場データと SNS の指標を取得するスクリプト
  data/<コイン名>/snapshots.csv   6時間ごとの自動記録
  scripts/fetch_web_events.py    サイトの閲覧イベントを取り込むスクリプト
  data/<コイン名>/web_events.csv  閲覧イベント（訪問者 ID は公開用にハッシュし直したもの）
sites/                    コインごとの Web ページと閲覧解析（Cloudflare Workers。sites/README.md 参照）
.github/workflows/        GitHub Actions（データの自動収集）
```

## 新しいコインを追加する

```bash
cp -R coins/_template coins/新しいコイン名
```

`coin.env` の `TOKEN_NAME` と `TOKEN_SYMBOL`、ウォレット、`README.md` のストーリーを書き換えます。比較したい要素以外の値は、ほかのコインとそろえておきます（[research/README.md](research/README.md) の「実験の軸」を参照）。

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

`.env` に Etherscan の API キーなどを記入します。次に `coins/<コイン名>/coin.env` を開いて、`TEAM_WALLET` と `COMMUNITY_WALLET` を記入します。`TEAM_WALLET` は**後から変更できません**。ハードウェアウォレットか [Safe](https://app.safe.global) のマルチシグにしてください。

まず、ローカルで試します（何も送信しません）。

```bash
./deploy.sh seppuku dry-run
```

### 1. テストネット（Base Sepolia）で本番と同じ手順を試す

テストネット用の ETH は faucet（無料配布サイト）で入手します。

```bash
./deploy.sh seppuku base_sepolia
```

### 2. 本番（Base Mainnet）

```bash
./deploy.sh seppuku base
```

デプロイのガス代は通常 **1ドル未満** です。Basescan でのソースコードの公開・検証まで自動で行います（信頼を得るために必須）。終わったら、表示されたアドレスを `coins/<コイン名>/deployments.md` に記録します。

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
