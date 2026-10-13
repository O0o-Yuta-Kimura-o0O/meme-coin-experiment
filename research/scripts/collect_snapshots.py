#!/usr/bin/env python3
"""コインごとの市場データと SNS の指標を取得し、research/data/<コイン名>/snapshots.csv に追記する。

- 設定: coins/<コイン名>/tracking.json（空欄の項目はスキップ）
- 認証情報: 環境変数 X_BEARER_TOKEN / YOUTUBE_API_KEY / IG_ACCESS_TOKEN（未設定ならスキップ）
- 1つのデータ源が失敗しても、ほかのデータ源の記録は続ける
- 標準ライブラリのみで動く（依存パッケージなし）

使い方: python3 research/scripts/collect_snapshots.py [--dry-run]
"""

import csv
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COINS_DIR = ROOT / "coins"
DATA_DIR = ROOT / "research" / "data"
CSV_HEADER = ["timestamp_utc", "source", "metric", "value"]

IG_GRAPH_VERSION = os.environ.get("IG_GRAPH_VERSION") or "v24.0"
# 指標は「直近24時間」の件数として記録する（実行間隔より長い窓なので、取りこぼしが出ない）
WINDOW = timedelta(hours=24)


def log(msg):
    print(msg, file=sys.stderr)


def get_json(url, headers=None):
    req = urllib.request.Request(url, headers={"User-Agent": "meme-coin-experiment", **(headers or {})})
    try:
        with urllib.request.urlopen(req, timeout=30) as res:
            return json.load(res)
    except urllib.error.HTTPError as e:
        body = e.read().decode("utf-8", "replace")[:300]
        log(f"  HTTP {e.code} {url.split('?')[0]}: {body}")
    except Exception as e:  # ネットワークエラーなど
        log(f"  error {url.split('?')[0]}: {e}")
    return None


def dig(obj, *keys):
    for k in keys:
        if isinstance(obj, dict):
            obj = obj.get(k)
        elif isinstance(obj, list) and isinstance(k, int) and len(obj) > k:
            obj = obj[k]
        else:
            return None
    return obj


def norm(value):
    """API によって文字列・桁数がまちまちな数値を、有効数字10桁にそろえる（整数はそのまま）"""
    if isinstance(value, int) or (isinstance(value, str) and value.isdigit()):
        return int(value)
    try:
        f = float(value)
    except (TypeError, ValueError):
        return value
    r = float(f"{f:.10g}")
    return int(r) if r.is_integer() and abs(r) < 1e15 else r


def iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


# ---------- オンチェーン / 市場（キー不要） ----------

def collect_market(address):
    rows = []
    gt = "https://api.geckoterminal.com/api/v2/networks/base/tokens/" + address
    headers = {"Accept": "application/json;version=20230302"}
    a = dig(get_json(gt, headers), "data", "attributes") or {}
    for metric, key in [
        ("price_usd", ("price_usd",)),
        ("fdv_usd", ("fdv_usd",)),
        ("market_cap_usd", ("market_cap_usd",)),
        ("liquidity_usd", ("total_reserve_in_usd",)),
        ("volume_24h_usd", ("volume_usd", "h24")),
    ]:
        rows.append(("geckoterminal", metric, dig(a, *key)))
    info = dig(get_json(gt + "/info", headers), "data", "attributes") or {}
    rows.append(("geckoterminal", "holders", dig(info, "holders", "count")))

    ds = get_json("https://api.dexscreener.com/latest/dex/tokens/" + address) or {}
    pairs = [p for p in (ds.get("pairs") or []) if p.get("chainId") == "base"]
    if pairs:
        main = max(pairs, key=lambda p: dig(p, "liquidity", "usd") or 0)
        rows += [
            ("dexscreener", "buys_24h", dig(main, "txns", "h24", "buys")),
            ("dexscreener", "sells_24h", dig(main, "txns", "h24", "sells")),
            ("dexscreener", "volume_24h_usd", dig(main, "volume", "h24")),
            ("dexscreener", "liquidity_usd", dig(main, "liquidity", "usd")),
            ("dexscreener", "pair_count", len(pairs)),
        ]
    return rows


# ---------- X（有料 API。アクセスレベルによっては一部の指標が取れない） ----------

def collect_x(cfg, now):
    token = os.environ.get("X_BEARER_TOKEN")
    if not token:
        return []
    headers = {"Authorization": "Bearer " + token}
    rows = []
    if cfg.get("username"):
        u = get_json(
            "https://api.x.com/2/users/by/username/"
            + urllib.parse.quote(cfg["username"])
            + "?user.fields=public_metrics",
            headers,
        )
        m = dig(u, "data", "public_metrics") or {}
        rows += [
            ("x", "followers", m.get("followers_count")),
            ("x", "posts", m.get("tweet_count")),
        ]
    if cfg.get("query"):
        q = urllib.parse.urlencode(
            {"query": cfg["query"], "granularity": "hour", "start_time": iso(now - WINDOW + timedelta(minutes=1))}
        )
        c = get_json("https://api.x.com/2/tweets/counts/recent?" + q, headers)
        rows.append(("x", "mentions_24h", dig(c, "meta", "total_tweet_count")))
    return rows


# ---------- YouTube（無料枠: 1日 10,000 ユニット。検索は1回 100 ユニット） ----------

def collect_youtube(cfg, now):
    key = os.environ.get("YOUTUBE_API_KEY")
    if not key:
        return []
    base = "https://www.googleapis.com/youtube/v3/"
    rows = []
    if cfg.get("channel_id"):
        q = urllib.parse.urlencode({"part": "statistics", "id": cfg["channel_id"], "key": key})
        s = dig(get_json(base + "channels?" + q), "items", 0, "statistics") or {}
        rows += [
            ("youtube", "subscribers", s.get("subscriberCount")),
            ("youtube", "channel_views", s.get("viewCount")),
            ("youtube", "channel_videos", s.get("videoCount")),
        ]
    if cfg.get("query"):
        q = urllib.parse.urlencode(
            {
                "part": "id",
                "type": "video",
                "q": cfg["query"],
                "publishedAfter": iso(now - WINDOW),
                "maxResults": 1,
                "key": key,
            }
        )
        # totalResults は YouTube 側の概算値
        rows.append(("youtube", "videos_24h_approx", dig(get_json(base + "search?" + q), "pageInfo", "totalResults")))
    return rows


# ---------- Instagram（Graph API。ビジネス / クリエイターアカウントが必要） ----------

def collect_instagram(cfg, now):
    token = os.environ.get("IG_ACCESS_TOKEN")
    user_id = cfg.get("user_id")
    if not token or not user_id:
        return []
    base = f"https://graph.facebook.com/{IG_GRAPH_VERSION}/"
    rows = []
    q = urllib.parse.urlencode({"fields": "followers_count,media_count", "access_token": token})
    u = get_json(base + user_id + "?" + q) or {}
    rows += [
        ("instagram", "followers", u.get("followers_count")),
        ("instagram", "posts", u.get("media_count")),
    ]
    tag = (cfg.get("hashtag") or "").lstrip("#")
    if tag:
        q = urllib.parse.urlencode({"user_id": user_id, "q": tag, "access_token": token})
        tag_id = dig(get_json(base + "ig_hashtag_search?" + q), "data", 0, "id")
        if tag_id:
            # recent_media は直近24時間の投稿だけを返す。最大 1,000 件まで数える
            count = 0
            url = base + tag_id + "/recent_media?" + urllib.parse.urlencode(
                {"user_id": user_id, "fields": "timestamp", "limit": 50, "access_token": token}
            )
            for _ in range(20):
                page = get_json(url)
                if not page:
                    break
                count += len(page.get("data") or [])
                url = dig(page, "paging", "next")
                if not url:
                    break
            rows.append(("instagram", "hashtag_posts_24h", count))
    return rows


def collect_coin(coin_dir, now):
    cfg = json.loads((coin_dir / "tracking.json").read_text(encoding="utf-8"))
    rows = []
    if cfg.get("token_address"):
        rows += collect_market(cfg["token_address"])
    rows += collect_x(cfg.get("x") or {}, now)
    rows += collect_youtube(cfg.get("youtube") or {}, now)
    rows += collect_instagram(cfg.get("instagram") or {}, now)
    return [(source, metric, norm(value)) for source, metric, value in rows if value is not None]


def append_csv(path, ts, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    new = not path.exists()
    with path.open("a", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        if new:
            w.writerow(CSV_HEADER)
        for source, metric, value in rows:
            w.writerow([ts, source, metric, value])


def main():
    dry_run = "--dry-run" in sys.argv
    now = datetime.now(timezone.utc).replace(microsecond=0)
    ts = iso(now)
    total = 0
    for coin_dir in sorted(COINS_DIR.iterdir()):
        if coin_dir.name.startswith("_") or not (coin_dir / "tracking.json").exists():
            continue
        log(f"[{coin_dir.name}]")
        rows = collect_coin(coin_dir, now)
        for source, metric, value in rows:
            log(f"  {source:14} {metric:20} {value}")
        if not rows:
            log("  (記録できる指標なし。tracking.json と認証情報を確認)")
        elif not dry_run:
            append_csv(DATA_DIR / coin_dir.name / "snapshots.csv", ts, rows)
        total += len(rows)
    log(f"done: {total} rows{' (dry-run)' if dry_run else ''}")


if __name__ == "__main__":
    main()
