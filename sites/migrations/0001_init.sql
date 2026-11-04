-- 全コインのサイトで共有する閲覧イベントのテーブル
-- 名前・メールアドレス・IP アドレスそのものは保存しない：IP アドレスは秘密鍵つき HMAC の先頭16桁（visitor）にしてから保存し、元の値は残さない
CREATE TABLE events (
  id          INTEGER PRIMARY KEY AUTOINCREMENT,
  site        TEXT    NOT NULL,           -- コイン名（wrangler.jsonc の SITE）
  received_at TEXT    NOT NULL,           -- サーバーが受け取った時刻（UTC, ISO 8601）
  event_at    TEXT    NOT NULL,           -- イベントが起きた時刻（サーバー時計に補正済み）
  elapsed_ms  INTEGER,                    -- ページを開いてからの経過ミリ秒
  session_id  TEXT,                       -- タブごとのランダム ID（sessionStorage。Cookie なし）
  visitor     TEXT,                       -- HMAC(IP_HASH_KEY, IP) の先頭16桁
  country     TEXT,                       -- Cloudflare が判定した国コード
  device      TEXT,                       -- mobile / tablet / desktop / bot
  os          TEXT,
  browser     TEXT,
  app         TEXT,                       -- アプリ内ブラウザ（instagram / x / facebook / line / tiktok / youtube）
  type        TEXT    NOT NULL,           -- view / click / scroll / hidden / visible / leave / custom
  path        TEXT,
  referrer    TEXT,                       -- 外部の参照元のホスト名のみ
  data        TEXT                        -- そのほかの値（JSON）
);
CREATE INDEX idx_events_site_id ON events (site, id);
CREATE INDEX idx_events_session ON events (session_id);
