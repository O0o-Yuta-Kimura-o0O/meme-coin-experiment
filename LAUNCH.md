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
- `LP_RECIPIENTS` に二人のアドレスを書くと、同じ価格帯のポジション（NFT）を二人分作り、それぞれのウォレットに送る。買い手が払う ETH も取引手数料も、取引のたびに半分ずつ各自のポジションにたまる
- 表示された `Pool` と、二人分の `LP NFT tokenId` を `deployments.md` に記録する

両側（トークンと ETH を両方入れる）にしたい場合は、`LIQUIDITY_MODE=full` と `LIQUIDITY_ETH` を設定します。

## 4. 動作を確認する（テストネット）

| 確認すること | 方法 |
|---|---|
| 買える | Uniswap の画面（テストネット）か、別のウォレットからスワップ。0.001 ETH で約98万枚が目安（開始時の FDV 1 ETH の場合）。`cast send` で試す場合、最初の購入はガスの見積もりが足りずに失敗することがあるので、`--gas-limit 500000` を付ける |
| 売れる | 買った分を売り戻す。往復で手数料 2% ほど目減りする。プールにある ETH（買った人が入れた分）より多くは出てこない |
| 半減期 | 1時間後に、二人それぞれの `HalvingVesting` で `release()` を呼ぶと、各自のウォレットに自分の分の50%が届く。以後1時間ごとに残りの半分、3時間後に全量 |
| サイト | プレビュー版にテストネットのアドレスを載せ、コピーボタンと購入リンクを試す |

`release()` は、Basescan の「Write Contract」から呼べます。コマンドなら次のとおりです。

```bash
cast send <HalvingVesting のアドレス> "release()" --account deployer --rpc-url base_sepolia
```

## 5. 本番の前に

- [ ] テストネットで 2〜4 をすべて確認した
- [ ] 弁護士に相談した（暗号資産交換業に当たらないか）
- [ ] `TEAM_WALLETS` の二人のアドレスが正しい（後から変更できない）。本番はハードウェアウォレットを推奨
- [ ] `LIQUIDITY_MODE` と `START_FDV_ETH` は全コインで同じ値になっている
- [ ] サイトの日本語固定（`sites/seppuku/wrangler.jsonc` の `FORCE_LANG`）を外した
- [ ] `LP_RECIPIENTS` の二人のアドレスが正しい（本番はハードウェアウォレットを推奨）
- [ ] LP をロックするロッカー（UNCX など）を決めた。ロックする場合は、二人分の NFT をそれぞれロックする

## 6. 本番

テストネットと同じコマンドで、ネットワークを `base` にします。実行前に確認を求められます。

```bash
./deploy.sh seppuku base
```

```bash
./add-liquidity.sh seppuku base <Token のアドレス>
```

その後、LP（NFT）をロッカーでロックし、トークンのアドレスを `coins/seppuku/tracking.json` の `token_address` に書くと、データの自動収集が始まります。
