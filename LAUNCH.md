# ローンチ手順書（テストネット → 本番）

コインごとに、同じ手順をテストネット（Base Sepolia）で通してから本番（Base）で行います。以下は SEPPUKU COIN の例です。コマンドは、リポジトリの直下（`~/Documents/Meme_Coin`）で実行します。

## 0. 準備（最初の1回だけ）

| やること | 方法 |
|---|---|
| デプロイ専用のウォレットを作る | MetaMask か Rabby で新しいアカウントを作る。ほかの用途には使わない |
| そのウォレットを Foundry に登録する | 下のコマンドを実行し、秘密鍵と、保護用のパスワードを入力する |
| テスト用の ETH を入手する | [Coinbase の faucet](https://portal.cdp.coinbase.com/products/faucet) で 0.001 ETH ほど（1回 0.0001 ETH × 10回）。デプロイと流動性の追加は合わせて 0.0001 ETH 未満で済む |
| （任意）Etherscan の API キー | なくてもよい。キーがなければ、ソースコードは **Blockscout** で自動的に検証・公開される。Etherscan の API は Base が有料プラン専用のため、Basescan での検証は、必要になったら Basescan の画面から手作業で行う |
| （任意）`.env` を作る | `cp .env.example .env`。なくても Base 公式の接続先で動く |

```bash
cast wallet import deployer --interactive
```

デプロイ用のアドレスは、次のコマンドで確認できます。

```bash
cast wallet address --account deployer
```

## 1. 設定を確認する

- `coins/seppuku/coin.env`：名前、発行枚数、配分、`TEAM_WALLETS`（木村・鳥間の順にカンマ区切り。チーム分を 2.5% ずつ分ける）、`COMMUNITY_WALLET`、流動性の方式（`LIQUIDITY_MODE`）と開始時の時価総額（`START_FDV_ETH`）
- `coins/seppuku/coin.testnet.env`：テストネットだけの上書き（半減期を1時間単位に短縮）

## 2. デプロイする

まずローカルで予行演習します（何も送信しません）。

```bash
./deploy.sh seppuku dry-run
```

問題がなければ、テストネットにデプロイします。

```bash
./deploy.sh seppuku base_sepolia
```

表示された `Token` と、二人分の `HalvingVesting`（それぞれの受取人も表示される）のアドレスを、`coins/seppuku/deployments.md` に記録します。Blockscout（テストネットは base-sepolia.blockscout.com）でソースコードが検証済みになっているかも確認します。

## 3. 流動性を追加する（ここで売買できるようになる）

```bash
./add-liquidity.sh seppuku base_sepolia <Token のアドレス>
```

SEPPUKU COIN は **片側流動性**（`LIQUIDITY_MODE=single`）を使います。

- ETH を入れず、デプロイしたウォレットが持つトークン全量（90%）だけでプールを作る（Uniswap v3、手数料 1%）
- 開始価格 = `START_FDV_ETH` ÷ 発行枚数。例：FDV 1 ETH・10億枚なら、1枚 ≈ 0.000000001 ETH
- 買われるほど価格が上がり、プールに ETH がたまる。売られても、買った人が入れた ETH が戻るだけで、価格は開始価格より下がらない
- 複数のコインで `START_FDV_ETH` を同じにすれば、開始条件をそろえられる
- 誰かが先に別の価格でプールを作っていた場合（先回り攻撃）は、自動で中止する
- **流動性は永久にロックする**（`LP_LOCK=permanent`）。作ったポジションを、その場で `PermanentLPLock` に預ける。元本（コインと、買い手が払った ETH）は誰も、発行者自身も引き出せない。取引手数料だけは、誰が `collect` を呼んでも、`LP_RECIPIENTS` の二人に届く。二人のどちらかが鍵を失っても、プールでの売買は続く
- `LP_RECIPIENTS` に二人のアドレスを書くと、同じ価格帯のポジション（NFT）を二人分作り、それぞれのウォレットに送る。買い手が払う ETH も取引手数料も、取引のたびに半分ずつ各自のポジションにたまる
- 最後に「実際に作られた LP ポジション」として表示される番号を、`Pool` と一緒に `deployments.md` に記録する（途中のログの番号は送信前の予定値で、ずれることがある）

両側（トークンと ETH を両方入れる）にしたい場合は、`LIQUIDITY_MODE=full` と `LIQUIDITY_ETH` を設定します。

## 4. 動作を確認する（テストネット）

| 確認すること | 方法 |
|---|---|
| 買える | Uniswap の画面（テストネット）か、別のウォレットからスワップ。0.001 ETH で約98万枚が目安（開始時の FDV 1 ETH の場合）。`cast send` で試す場合、最初の購入はガスの見積もりが足りずに失敗することがあるので、`--gas-limit 500000` を付ける |
| 売れる | 買った分を売り戻す。往復で手数料 2% ほど目減りする。プールにある ETH（買った人が入れた分）より多くは出てこない |
| 半減期 | 1時間後に、二人それぞれの `HalvingVesting` で `release()` を呼ぶと、各自のウォレットに自分の分の50%が届く。以後1時間ごとに残りの半分、3時間後に全量 |
| サイト | プレビュー版にテストネットのアドレスを載せ、コピーボタンと購入リンクを試す |

手数料の回収は、永久ロックのコントラクトで `collect(<LP の NFT 番号>)` を呼ぶ（誰が呼んでも受取人に届く）。受取人のアドレスを変える手順は [TEAM.md](TEAM.md) の「手数料の受取人のアドレスを変える手順」を参照。

```bash
cast send <Permanent lock のアドレス> "collect(uint256)" <LP の NFT 番号> --account deployer --rpc-url https://sepolia.base.org
```

`release()` は、Basescan の「Write Contract」から呼べます。コマンドなら次のとおりです。

```bash
cast send <HalvingVesting のアドレス> "release()" --account deployer --rpc-url https://sepolia.base.org
```

## 5. 本番の前に

- [x] テストネットで 2〜4 をすべて確認した（3 回目は本番と同じ構成。`coins/seppuku/deployments.md`）
- [x] ローカルの Base 本番の複製（anvil のフォーク）で、本番の設定のまま、デプロイ → 片側流動性と永久ロック → 購入 → 手数料の発生 まで通した（2026-10-31。ガス代 計 約 0.00005 ETH）
- [x] Base 本番の Uniswap のアドレス（Factory・PositionManager・WETH・SwapRouter02）がつながっていることを、チェーン上で確認した
- [x] デプロイ用ウォレット（旧Address2）に、Base の ETH がある（0.004 ETH。1 コイン 約 0.0001 ETH）
- [x] サイトの日本語固定（`FORCE_LANG`）を外した
- [x] 弁護士に相談した（2026-11 、Web3 に詳しい弁護士にカジュアルな場で。違法性がないことの保証ではないが、この対応で問題ないとの判断。問題視されたときは協力を得られる）
- [ ] 税理士に相談した（`private/legal/` の相談文。ローンチ後になる。法令と税務の責任は木村が負う方針で先に進める）
- [x] 共同制作の覚書を二人で確認した（相続などで受取人が変わる場合の取り決めは、後から強化する）
- [x] `TEAM_WALLETS`・`LP_RECIPIENTS`・`COMMUNITY_WALLET` が本番の二人とコミュニティ用のアドレスになっている（後から変更できない。2026-10-31 時点で設定済み）
- [x] `LIQUIDITY_MODE=single`・`START_FDV_ETH=10`・`LP_LOCK=permanent` になっている

## 6. 本番（ローンチの当日）

上から順に行います。コマンドは、リポジトリの直下（`~/Documents/Meme_Coin`）で実行します。どれも、途中でデプロイ鍵パスワードを聞かれます。

**1. デプロイ**（実行前に確認を求められるので `y`）

```bash
./deploy.sh seppuku base
```

**2. 流動性の追加と永久ロック**（表示された `Token` のアドレスを入れる）

```bash
./add-liquidity.sh seppuku base <Token のアドレス>
```

ソースコードの検証で `Too many requests` が出ても、送信が成功していれば問題ありません（あとで検証し直せる）。

**3. 記録する**：表示された Token、HalvingVesting（二人分）、Pool、永久ロック、実際の LP NFT の番号を `coins/seppuku/deployments.md` に書く

**4. 税務記録に足す**（設定ファイルを作り、コインの情報を送信記録から自動で書き足す）

```bash
cp private/tax/mainnet.pending.json private/tax/config.mainnet.json
```

```bash
python3 tax/add_coin.py 8453 private/tax/config.mainnet.json SEPPUKU
```

そのあと、非公開リポジトリ（`private/tax`）で commit して push する。GitHub Actions は `config.*.json` をすべて読むので、次の 6 時間ごとの実行から本番の記録が始まる。

**5. サイトを本番の表示に切り替える**（アドレス、Uniswap の購入リンク、テストネット表示の削除、SNS のリンク、og:image）。SNS のアカウントは、`coins/seppuku/tracking.json` に書いてから実行する（あとから書いて、もう一度実行してもよい）

```bash
cd sites && node scripts/set-launch.mjs seppuku <Token のアドレス> https://seppuku-site.meme-coin-sites.workers.dev
```

**6. サイトを公開する**（最初の 1 回だけ、`sites/README.md` の「本番に公開する」の 4・5 で秘密の鍵を登録する）

```bash
cd sites && npm run deploy:seppuku
```

公開前のチェック（`check-release.mjs`）が、テストネットの表示、「準備中」のボタン、リンク先のない SNS が残っていないかを確かめ、残っていれば止まります。

**7. 動作を確かめる**：サイトのコピーボタンと購入リンク、Basescan でのトークンの表示、少額の購入（任意）

**8. 保存する**：`git add -A && git commit` して push（`tracking.json` にアドレスが入ると、データの自動収集が始まる）
