# meme-coin-experiment

**Base**（Coinbase が運営するイーサリアムのレイヤー2）上で、**同じ仕組みを土台に、名前・ストーリー・運営のしかたなどを変えた**ミームコインを複数発行し、市場での広がり方の違いを観察する実験プロジェクトです。

- すべてのコインが同じコントラクト（`src/`）を使います。違うのは `coins/<コイン名>/` の設定とストーリーだけです
- 研究の設計 → [research/README.md](research/README.md)
- ローンチの手順（テストネット → 本番）→ [LAUNCH.md](LAUNCH.md)
- 制作：**Team SEPPUKU**（木村 祐太 Yuta Kimura・鳥間 勇 Yu Torima、貢献度 50% / 50%）→ [TEAM.md](TEAM.md)

## コイン一覧

| コイン | ティッカー | 発行枚数 | 配分（流動性 / チーム / コミュニティ） | 半減期（クリフ / 間隔 / 回数） | 状態 | フォルダ |
|---|---|---|---|---|---|---|
| SEPPUKU COIN | $SEPPUKU | 10億 | 90 / 5 / 5 | 90日 / 180日 / 8回 | 準備中 | [coins/seppuku](coins/seppuku) |

仕様の違い（発行枚数・配分・半減期）は、すべて各コインの `coin.env` で設定します。コントラクトのコードは全コイン共通です。

## 共通仕様（PEPE 型 + ビットコイン風の半減期）

| 項目 | 内容 |
|---|---|
| 規格 | ERC-20（OpenZeppelin v5.4）+ Burnable + Permit |
| 発行枚数 | 1,000,000,000（10億）※ `coin.env` で変更可。デプロイ時に全量を発行し、追加発行はできない |
| 管理者権限 | **なし**（オーナーなし、mint なし、一時停止なし、ブラックリストなし、売買税なし） |
| 配分 | 流動性（DEX）90% / チーム 5% / コミュニティ・エアドロップ 5% |
| 流動性 | ETH を入れない片側流動性。メンバーごとの同量のポジションに分け、`PermanentLPLock` で **永久にロック**（元本は誰も引き出せず、取引手数料だけが各メンバーに届く） |
| 半減期 | チーム分は `HalvingVesting` でロック（メンバーごとに1つ。Team SEPPUKU は二人で 2.5% ずつ）。クリフ（90日）明けに 50%、その後 180 日ごとに残りの半分ずつ解放され、8 回目で全量解放 |
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
src/PermanentLPLock.sol   流動性ポジションの永久ロック（手数料だけ受取人に届く。全コイン共通）
script/Deploy.s.sol       デプロイと配分を一括で行うスクリプト
test/MemeCoin.t.sol       テスト
deploy.sh                 コインを指定してデプロイするラッパー
add-liquidity.sh          Uniswap v3 にプールを作り流動性を入れるラッパー（script/AddLiquidity.s.sol）。片側（ETH なし）と両側を選べる
script/liquidity_params.py  片側流動性の価格帯と初期価格を、開始時の時価総額から計算する
scripts-env.sh            上の2つが読み込む共通処理（coin.env / coin.testnet.env の読み込み、本番の確認）
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
tax/                      税務申告用の取引記録をメンバーごとの CSV で作り続けるツール（設定と出力は private/tax/。tax/README.md 参照）
sites/                    コインごとの Web ページと閲覧解析（Cloudflare Workers。sites/README.md 参照）
.github/workflows/        GitHub Actions（データの自動収集）
```

## 新しいコインを追加する

```bash
cp -R coins/_template coins/新しいコイン名
```

`coin.env` の `TOKEN_NAME` と `TOKEN_SYMBOL`、ウォレット、`README.md` のストーリーを書き換えます。比較したい要素以外の値は、ほかのコインとそろえておきます（[research/README.md](research/README.md) の「実験の軸」を参照）。

## 手順

Foundry の準備、デプロイ、流動性の追加、テストネットでの確認、本番の前のチェックリストは、[LAUNCH.md](LAUNCH.md) にまとめています。

```bash
forge test
```

Base Sepolia を複製して、プールの作成・購入・売却まで確かめるテスト（ネットワークが必要。片側流動性の価格帯の計算に Python を呼ぶので `--ffi` を付ける）:

```bash
BASE_SEPOLIA_RPC_URL=https://sepolia.base.org forge test --match-contract Fork --ffi -vv
```

## 安全性について

- コントラクトに管理者機能がないので、**デプロイしたあとは誰にも（発行者自身にも）変更できません**。ハニーポットチェッカーや Token Sniffer で「安全」と判定されやすい構成です
- 一方で、バグを見つけても修正できません。必ずテストネットで一通り試してください
- 大きな金額を扱う前に、第三者による監査を検討してください
