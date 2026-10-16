# 研究設計：同一仕様のミームコインは、名前とストーリーだけでどれだけ差がつくか

## 問い

コントラクト（バイトコード）、発行枚数、配分、初期流動性を同じにしたとき、**名前・ストーリー・ミーム**の違いだけで、流動性・取引高・保有者数などにどの程度の差が生まれるか。

## 実験の軸

| 軸 | 変えるもの | どこで変えるか |
|---|---|---|
| 名前の軸 | 名前、ティッカー、ストーリー、ビジュアル | `coins/<コイン名>/README.md` と `coin.env` の `TOKEN_NAME` / `TOKEN_SYMBOL` |
| 運営の軸 | 出来事に合わせた焼却（例：AI が有名な未解決問題を解いたら X% を焼却）、配布の方法など | `coins/<コイン名>/README.md` に運営のルールを書く（コントラクトは共通のまま。焼却はトークンの `burn` を使う） |
| 仕様の軸（A: 設定値） | 発行枚数（`TOTAL_SUPPLY`）、配分（`*_PCT`）、半減期のクリフ・間隔・回数（`VESTING_*`） | `coins/<コイン名>/coin.env` のみ（コントラクトは共通のまま） |

**原則：1つの比較では、1つの軸の1つの要素だけを変える。** 例えば「発行枚数 10億 vs 1兆」を比べるなら、名前の印象の差が混ざらないよう、ストーリーの強さが同程度の名前どうしで比べる。各コインがどの比較に属するかは、下の「実験一覧」に記録する。

### 仕様の軸で試せる例

| 比較 | 条件 1 | 条件 2 | 見たいこと |
|---|---|---|---|
| 単位価格の錯覚 | `TOTAL_SUPPLY=1000000000`（10億） | `TOTAL_SUPPLY=1000000000000`（1兆） | 1枚あたりの価格が安く見えると、買われやすくなるか |
| チーム保有比率 | `TEAM_PCT=0` | `TEAM_PCT=10` | 発行者の取り分の大きさが警戒されるか |
| 解放の速さ | `VESTING_PERIOD_DAYS=30` | `VESTING_PERIOD_DAYS=365` | ロックの長さが信頼と値動きに効くか |

## 実験一覧

| 実験 ID | 軸 | 比較する要素 | コイン | ローンチ方式（同時 / ずらす） | 状態 |
|---|---|---|---|---|---|
| — | — | — | seppuku | — | 準備中 |

## 変数

| 種類 | 内容 |
|---|---|
| 独立変数 | 実験ごとに、上の「実験の軸」から1つ選ぶ |
| 統制する変数 | コントラクト（全コインで `src/` を共有）、独立変数に選ばなかった設定値、初期流動性の ETH 量、DEX と手数料ティア、LP のロック期間、チーム分の売却方針、宣伝にかける労力・費用 |
| 交絡しやすい変数 | ローンチの時刻と市場環境（ETH の価格、ミームコイン全体の盛り上がり）、宣伝の量と質、bot の挙動、同時期の類似コイン |

**ローンチ時期の扱い**：全コインを同時に出すと市場環境はそろいますが、コイン同士で注目を奪い合います。時期をずらすと市場環境の差が混ざります。どちらを選ぶかを事前に決め、ここに記録してください。

## 指標（ローンチ後 1時間 / 24時間 / 7日 / 30日 / 90日 の各時点）

- 価格、FDV（完全希薄化後の時価総額）、流動性（プール内の ETH）
- 取引高、取引回数、ユニークな買い手の数、ユニークな売り手の数
- 保有者数、上位10アドレスの保有比率
- LP 手数料の累計
- SNS での言及数（X、Farcaster）、検索トレンド
- 外部の反応：CoinGecko・CMC への掲載可否、取引所・広告の審査結果

## データ源（維持費ゼロで取れるもの）

- GeckoTerminal API / DexScreener API（価格、取引高、流動性）
- Basescan（保有者、トランザクション）
- Dune（オンチェーンデータに SQL でクエリでき、ダッシュボードも公開できる）

## 自動データ収集

GitHub Actions（[.github/workflows/collect-snapshots.yml](../.github/workflows/collect-snapshots.yml)）が **6時間ごと** に [scripts/collect_snapshots.py](scripts/collect_snapshots.py) を動かし、結果を `research/data/<コイン名>/snapshots.csv` に追記して自動でコミットします。サーバーは不要です。GitHub の画面の Actions タブ → Collect snapshots → Run workflow から、手動でも実行できます。

- CSV の列：`timestamp_utc, source, metric, value`（縦長の形式。指標を増やしても列は変わらない）
- SNS の言及数は「**直近24時間**」の件数（6時間ごとに記録するので、窓が重なり、取りこぼしが出ない）
- 設定や認証情報が空のデータ源はスキップされる。1つが失敗しても、ほかの記録は続く
- 費用：非公開リポジトリの Actions 無料枠（月2,000分）のうち、月120分程度

### 記録する指標

| データ源 | 指標 | 必要なもの | 費用 |
|---|---|---|---|
| GeckoTerminal | 価格、FDV、時価総額、流動性、24時間の取引高、保有者数 | `token_address` のみ | 無料 |
| DexScreener | 24時間の買い・売りの回数、取引高、流動性、プール数 | `token_address` のみ | 無料 |
| X | フォロワー数、投稿数、直近24時間の言及数 | `X_BEARER_TOKEN` | **有料**（料金体系がよく変わる。言及数の取得は、上位プランでないと使えない場合がある） |
| YouTube | 登録者数、総再生数、動画数、直近24時間の関連動画数（概算） | `YOUTUBE_API_KEY` | 無料（1日 10,000 ユニットの枠内。1回の実行で 1コインあたり約 101 ユニット） |
| Instagram | フォロワー数、投稿数、直近24時間のハッシュタグ投稿数 | `IG_ACCESS_TOKEN` | 無料 |

| 自分のサイト（Cloudflare） | 来訪・クリック・スクロール・離脱の時刻、ハッシュ化した訪問者 ID、国、端末、参照元、アプリ内ブラウザ | `site_url` と `SITE_EXPORT_TOKEN` | 無料（詳しくは [sites/README.md](../sites/README.md)） |

### 設定の手順

**1. コインごとの対象を書く**：`coins/<コイン名>/tracking.json`

| 項目 | 書くもの |
|---|---|
| `token_address` | デプロイしたトークンのアドレス（デプロイするまでは空欄） |
| `site_url` | コインのサイトの URL（例: `https://seppuku-site.xxx.workers.dev`） |
| `x.username` / `x.query` | 公式アカウント名（@ なし）/ 言及を数える検索条件 |
| `youtube.channel_id` / `youtube.query` | 公式チャンネルの ID（`UC` で始まる）/ 関連動画の検索語 |
| `instagram.user_id` / `instagram.hashtag` | Instagram ビジネスアカウントの ID（数字）/ 数えるハッシュタグ（# なし） |

**2. 認証情報を GitHub の Secrets に登録する**：キーはファイルに書かず、ターミナルで下のコマンドを実行して、表示された入力欄に貼り付けます（GitHub の画面の Settings → Secrets and variables → Actions からも登録できます）。

```bash
gh secret set YOUTUBE_API_KEY
```

```bash
gh secret set X_BEARER_TOKEN
```

```bash
gh secret set IG_ACCESS_TOKEN
```

- **YouTube**：Google Cloud Console でプロジェクトを作成 →「YouTube Data API v3」を有効化 → 認証情報から API キーを作成。キーは YouTube Data API だけに使えるよう制限をかける
- **X**：developer.x.com でアプリを作成し、Bearer Token を発行する。有料なので、言及数が研究に必要になってからでよい
- **Instagram**：手順が一番多い
  1. Instagram をビジネスかクリエイターのアカウントにする
  2. Facebook ページとつなぐ
  3. Meta for Developers でアプリを作成する
  4. 権限 `instagram_basic` と `instagram_manage_insights` を付けたトークンを発行する
  - 通常の長期トークンは **60日で失効する**。Meta Business Suite の「システムユーザー」で発行したトークンなら失効しないので、維持の手間がなくなる
  - Graph API のバージョンは既定で `v24.0`。古くなったら、リポジトリの Variables に `IG_GRAPH_VERSION`（例: `v26.0`）を登録して変える

**3. ローカルで試す**（記録はせず、表示するだけ）

```bash
python3 research/scripts/collect_snapshots.py --dry-run
```

## 倫理面の注意

買い手は実際のお金を使う実在の人です。

- 「実験の一環である」ことを、各コインの Web / X で明示する
- 結果を操作するための自己売買（ウォッシュトレード）や、買い手を欺く行為はしない
- 結果を公開する際、個人を特定できる形でアドレスを晒さない
