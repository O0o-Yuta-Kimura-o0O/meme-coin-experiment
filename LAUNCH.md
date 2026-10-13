# ローンチ手順書（テストネット → 本番）

コインごとに、同じ手順をテストネット（Base Sepolia）で通してから本番（Base）で行います。以下は SEPPUKU COIN の例です。コマンドは、リポジトリの直下（`~/Documents/Meme_Coin`）で実行します。

## 0. 準備（最初の1回だけ）

| やること | 方法 |
|---|---|
| デプロイ専用のウォレットを作る | MetaMask か Rabby で新しいアカウントを作る。ほかの用途には使わない |
| そのウォレットを Foundry に登録する | 下のコマンドを実行し、秘密鍵と、保護用のパスワードを入力する |
| テスト用の ETH を入手する | Base Sepolia の faucet から 0.1 ETH ほど（デプロイ用と流動性 0.02 ETH 用） |
| Etherscan の API キーを取る | etherscan.io の無料アカウントで発行し、`.env` の `ETHERSCAN_API_KEY` に書く（Base と Base Sepolia の両方で使える） |
| `.env` を作る | `cp .env.example .env` |

```bash
cast wallet import deployer --interactive
```

デプロイ用のアドレスは、次のコマンドで確認できます。

```bash
cast wallet address --account deployer
```

## 1. 設定を確認する

- `coins/seppuku/coin.env`：名前、発行枚数、配分、`TEAM_WALLET`、`COMMUNITY_WALLET`、`LIQUIDITY_ETH`
- `coins/seppuku/coin.testnet.env`：テストネットだけの上書き（半減期を1時間単位に短縮、流動性 0.02 ETH）

## 2. デプロイする

まずローカルで予行演習します（何も送信しません）。

```bash
./deploy.sh seppuku dry-run
```

問題がなければ、テストネットにデプロイします。

```bash
./deploy.sh seppuku base_sepolia
```

表示された `Token` と `HalvingVesting` のアドレスを、`coins/seppuku/deployments.md` に記録します。Basescan（テストネットは sepolia.basescan.org）でソースコードが検証済みになっているかも確認します。

## 3. 流動性を追加する（ここで売買できるようになる）

```bash
./add-liquidity.sh seppuku base_sepolia <Token のアドレス>
```

- デプロイしたウォレットが持つトークン全量（90%）と、`LIQUIDITY_ETH` の ETH で、Uniswap v3 にプールを作る（手数料 1%、フルレンジ）
- 初期価格は「入れた ETH ÷ 入れたトークン」で決まるので、全コインで同じ条件にそろえられる
- 誰かが先に別の価格でプールを作っていた場合（先回り攻撃）は、自動で中止する
- 表示された `Pool` と `LP NFT tokenId` も `deployments.md` に記録する

## 4. 動作を確認する（テストネット）

| 確認すること | 方法 |
|---|---|
| 買える | Uniswap の画面（テストネット）か、別のウォレットからスワップ。0.001 ETH で約4,200万枚が目安（流動性 0.02 ETH の場合） |
| 売れる | 買った分を売り戻す。往復で手数料 2% ほど目減りする |
| 半減期 | 1時間後に `release()` を呼ぶと、チーム用ウォレットに50%が届く。以後1時間ごとに残りの半分、3時間後に全量 |
| サイト | プレビュー版にテストネットのアドレスを載せ、コピーボタンと購入リンクを試す |

`release()` は、Basescan の「Write Contract」から呼べます。コマンドなら次のとおりです。

```bash
cast send <HalvingVesting のアドレス> "release()" --account deployer --rpc-url base_sepolia
```

## 5. 本番の前に

- [ ] テストネットで 2〜4 をすべて確認した
- [ ] 弁護士に相談した（暗号資産交換業に当たらないか）
- [ ] `TEAM_WALLET` はハードウェアウォレットか Safe のマルチシグになっている（後から変更できない）
- [ ] `LIQUIDITY_ETH` は全コインで同じ値になっている
- [ ] サイトの日本語固定（`sites/seppuku/wrangler.jsonc` の `FORCE_LANG`）を外した
- [ ] LP をロックするロッカー（UNCX など）を決めた

## 6. 本番

テストネットと同じコマンドで、ネットワークを `base` にします。実行前に確認を求められます。

```bash
./deploy.sh seppuku base
```

```bash
./add-liquidity.sh seppuku base <Token のアドレス>
```

その後、LP（NFT）をロッカーでロックし、トークンのアドレスを `coins/seppuku/tracking.json` の `token_address` に書くと、データの自動収集が始まります。
