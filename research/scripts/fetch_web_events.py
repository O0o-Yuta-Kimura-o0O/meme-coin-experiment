#!/usr/bin/env python3
"""各コインのサイト（Cloudflare Worker）から閲覧イベントを取得し、research/data/<コイン名>/web_events.csv に追記する。

- 取得先: coins/<コイン名>/tracking.json の site_url（空ならスキップ）
- 認証: 環境変数 SITE_EXPORT_TOKEN（Worker の EXPORT_TOKEN と同じ値。未設定ならスキップ）
- 前回の続き（CSV の最後の id より後）だけを取得する
- visitor は Worker 側で公開用の鍵によりハッシュし直されている（保存側の値とは突き合わせられない）

使い方: python3 research/scripts/fetch_web_events.py
"""

import csv
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
COINS_DIR = ROOT / "coins"
DATA_DIR = ROOT / "research" / "data"
COLUMNS = [
    "id", "received_at", "event_at", "elapsed_ms", "session_id", "visitor", "country",
    "device", "os", "browser", "app", "type", "path", "referrer", "data",
]
PAGE = 5000


def log(msg):
    print(msg, file=sys.stderr)


def last_id(path):
    if not path.exists():
        return 0
    last = 0
    with path.open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            last = max(last, int(row["id"]))
    return last


def fetch(site_url, token, since_id):
    url = f"{site_url.rstrip('/')}/x/export?since_id={since_id}&limit={PAGE}"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}", "User-Agent": "meme-coin-experiment"})
    with urllib.request.urlopen(req, timeout=60) as res:
        return json.load(res)


def main():
    token = os.environ.get("SITE_EXPORT_TOKEN")
    if not token:
        log("SITE_EXPORT_TOKEN が未設定のためスキップ")
        return
    for coin_dir in sorted(COINS_DIR.iterdir()):
        cfg_path = coin_dir / "tracking.json"
        if coin_dir.name.startswith("_") or not cfg_path.exists():
            continue
        site_url = json.loads(cfg_path.read_text(encoding="utf-8")).get("site_url")
        if not site_url:
            continue
        out = DATA_DIR / coin_dir.name / "web_events.csv"
        since = last_id(out)
        added = 0
        try:
            while True:
                rows = fetch(site_url, token, since).get("rows") or []
                if not rows:
                    break
                out.parent.mkdir(parents=True, exist_ok=True)
                new = not out.exists()
                with out.open("a", newline="", encoding="utf-8") as f:
                    w = csv.DictWriter(f, fieldnames=COLUMNS, extrasaction="ignore")
                    if new:
                        w.writeheader()
                    w.writerows(rows)
                since = rows[-1]["id"]
                added += len(rows)
                if len(rows) < PAGE:
                    break
        except (urllib.error.URLError, ValueError) as e:
            log(f"[{coin_dir.name}] error: {e}")
        log(f"[{coin_dir.name}] +{added} events")


if __name__ == "__main__":
    main()
