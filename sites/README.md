# サイト（Cloudflare Workers + 静的アセット）

コインごとの Web ページと閲覧解析です。全コインで、1つの Worker のコード（`shared/`）と1つのデータベース（D1 `meme-analytics`）を共有します。

```
shared/worker.js            静的ファイルの配信、閲覧イベントの受信（/x/e）、研究用の書き出し（/x/export）
shared/tracker.client.js    ページに埋め込む計測スクリプト（/x/s.js として配信）
migrations/                 D1 のテーブル定義
seppuku/wrangler.jsonc      SEPPUKU サイトの設定
seppuku/public/             SEPPUKU のページ（index.html、privacy.html、404.html、style.css、logo.svg）
```

## 記録する内容（個人情報は保存しない）

| 記録する | 記録しない |
|---|---|
| IP アドレスの HMAC（秘密鍵 `IP_HASH_KEY` 付き。先頭16桁） | IP アドレスそのもの |
| 国、端末の種類、OS、ブラウザ、アプリ内ブラウザ（Instagram / X など） | User-Agent の文字列そのもの |
| 来訪・クリック・スクロールの深さ・タブ離脱・ページ離脱と、それぞれの時刻 | Cookie、入力内容 |
| 外部の参照元（ホスト名のみ）、URL の `utm_*` | 参照元の URL の全体 |

- Global Privacy Control / Do Not Track が有効なブラウザからは、何も記録しない
- 研究用に書き出すときは、別の鍵（`PUBLISH_HASH_KEY`）で visitor をハッシュし直す
- 計測したいボタンやリンクには `data-track="名前"` を付ける

## ローカルで動かす（Cloudflare のアカウント不要）

```bash
cd sites && npm install && cp seppuku/.dev.vars.example seppuku/.dev.vars && npm run db:migrate:local
```

```bash
cd sites && npm run dev:seppuku
```

http://localhost:8787 で表示されます。記録されたイベントは、次のコマンドで確認できます。

```bash
cd sites && npx wrangler d1 execute meme-analytics --local --config seppuku/wrangler.jsonc --command "SELECT * FROM events ORDER BY id DESC LIMIT 20"
```

## 本番に公開する（最初の1回）

1. Cloudflare のアカウントを作る（https://dash.cloudflare.com/sign-up 。無料プランで足りる）
2. ログインする（ブラウザが開くので、許可する）

```bash
cd sites && npx wrangler login
```

3. データベースを作る。表示された `database_id` を `seppuku/wrangler.jsonc` に書き込む

```bash
cd sites && npx wrangler d1 create meme-analytics
```

```bash
cd sites && npm run db:migrate:remote
```

4. 秘密の鍵を3つ登録する。値はランダムに生成されて直接登録されるので、画面には表示されない。ただし `EXPORT_TOKEN` だけは、GitHub にも同じ値を登録する必要があるので、5 で一緒に登録する

```bash
cd sites && openssl rand -hex 32 | npx wrangler secret put IP_HASH_KEY --config seppuku/wrangler.jsonc
```

```bash
cd sites && openssl rand -hex 32 | npx wrangler secret put PUBLISH_HASH_KEY --config seppuku/wrangler.jsonc
```

5. 書き出し用のトークンを、Cloudflare と GitHub の両方に同じ値で登録する（画面には表示されない）

```bash
cd sites && T=$(openssl rand -hex 32) && printf %s "$T" | npx wrangler secret put EXPORT_TOKEN --config seppuku/wrangler.jsonc && printf %s "$T" | gh secret set SITE_EXPORT_TOKEN && unset T
```

6. 公開する

```bash
cd sites && npm run deploy:seppuku
```

`https://seppuku-site.<アカウント名>.workers.dev` で公開されます。この URL を `coins/seppuku/tracking.json` の `site_url` に書くと、GitHub Actions が6時間ごとに閲覧イベントを `research/data/seppuku/web_events.csv` に取り込みます。

**注意**：`IP_HASH_KEY` を後から変えると、それ以前の訪問者と、同じ人として突き合わせられなくなります。一度登録したら変えないでください。複数のコインのサイトで同じ人を突き合わせたい場合は、全サイトで同じ値を登録します（そのときは、ランダムに生成した値を一時的に変数に入れ、5 と同じ要領で登録します）。

## 独自ドメイン

ドメイン（例: seppuku.xyz）を Cloudflare で購入するか、Cloudflare に移すと、`wrangler.jsonc` に次を加えるだけで使えます。

```jsonc
"routes": [{ "pattern": "seppuku.xyz", "custom_domain": true }]
```

## 新しいコインのサイトを追加する

1. `seppuku/` をコピーする
2. `wrangler.jsonc` の `name` と `vars.SITE` を変える
3. `public/` の中身を差し替える
4. `package.json` に `dev:` と `deploy:` のスクリプトを足す

データベースは共有なので、作り直す必要はありません。
