// 全コインのサイトで共有する Worker。
//   /x/s.js     閲覧解析スクリプト（tracker.client.js）を配信
//   /x/e        閲覧イベントを受け取って D1 に保存
//   /x/export   研究用にイベントを書き出す（EXPORT_TOKEN が必要。GitHub Actions が使う）
//   それ以外    public/ の静的ファイルを配信。HTML には、閲覧者の国（data-country）と、
//               開発中の固定言語（data-force-lang。FORCE_LANG が設定されているときだけ）を埋め込む
//
// 個人情報は保存しない：IP アドレスは IP_HASH_KEY を使った HMAC にしてから保存し、元の値はどこにも残さない。
// 書き出し時は PUBLISH_HASH_KEY でさらにハッシュし直す（研究データを公開しても、保存側の値と突き合わせられない）。

import trackerSource from "./tracker.client.js";

const MAX_BODY = 16 * 1024;
const MAX_EVENTS = 50;
const EVENT_TYPES = new Set(["view", "click", "scroll", "hidden", "visible", "leave", "custom"]);

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    switch (url.pathname) {
      case "/x/s.js":
        return new Response(trackerSource, {
          headers: { "content-type": "text/javascript; charset=utf-8", "cache-control": "public, max-age=3600" },
        });
      case "/x/e":
        return collect(request, env);
      case "/x/export":
        return exportEvents(request, env, url);
      default:
        return withLangHints(await env.ASSETS.fetch(request), request, env);
    }
  },
};

// 言語の自動選択に使うヒントを <html> に埋め込む（ページを開いた後の言語の切り替わり＝ちらつきを防ぐため）
function withLangHints(response, request, env) {
  if (!(response.headers.get("content-type") || "").includes("text/html")) return response;
  const country = request.cf?.country;
  return new HTMLRewriter()
    .on("html", {
      element(el) {
        if (country) el.setAttribute("data-country", country);
        if (env.FORCE_LANG) el.setAttribute("data-force-lang", env.FORCE_LANG);
      },
    })
    .transform(response);
}

async function collect(request, env) {
  if (request.method !== "POST") return new Response(null, { status: 405 });
  const text = await request.text();
  if (text.length > MAX_BODY) return new Response(null, { status: 413 });

  let body;
  try {
    body = JSON.parse(text);
  } catch {
    return new Response(null, { status: 400 });
  }
  const events = Array.isArray(body.e) ? body.e.slice(0, MAX_EVENTS) : [];
  if (!events.length) return new Response(null, { status: 204 });

  const now = Date.now();
  // クライアントの時計のずれを補正：送信時刻 n と各イベント時刻 c の差を、サーバーの受信時刻から引く
  const sentAt = Number(body.n) || now;
  const receivedAt = new Date(now).toISOString();
  const sessionId = str(body.s, 64);
  const visitor = await hmac16(env.IP_HASH_KEY, request.headers.get("CF-Connecting-IP"));
  const country = request.cf?.country || null;
  const ua = parseUserAgent(request.headers.get("User-Agent") || "");

  const stmt = env.DB.prepare(
    `INSERT INTO events (site, received_at, event_at, elapsed_ms, session_id, visitor, country, device, os, browser, app, type, path, referrer, data)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15)`,
  );
  const rows = [];
  for (const ev of events) {
    if (!ev || !EVENT_TYPES.has(ev.t)) continue;
    const lag = Math.min(Math.max(sentAt - (Number(ev.c) || sentAt), 0), 86_400_000);
    const data = ev.d && typeof ev.d === "object" ? JSON.stringify(ev.d).slice(0, 1000) : null;
    rows.push(
      stmt.bind(
        env.SITE || "unknown",
        receivedAt,
        new Date(now - lag).toISOString(),
        Number.isFinite(ev.m) ? Math.round(ev.m) : null,
        sessionId,
        visitor,
        country,
        ua.device,
        ua.os,
        ua.browser,
        ua.app,
        ev.t,
        str(ev.p, 200),
        str(ev.r, 200),
        data,
      ),
    );
  }
  if (rows.length) await env.DB.batch(rows);
  return new Response(null, { status: 204 });
}

async function exportEvents(request, env, url) {
  const auth = request.headers.get("Authorization") || "";
  if (!env.EXPORT_TOKEN || !(await safeEqual(auth, `Bearer ${env.EXPORT_TOKEN}`))) {
    return new Response("unauthorized", { status: 401 });
  }
  const sinceId = Math.max(parseInt(url.searchParams.get("since_id") || "0", 10) || 0, 0);
  const limit = Math.min(Math.max(parseInt(url.searchParams.get("limit") || "5000", 10) || 5000, 1), 10000);
  const { results } = await env.DB.prepare(
    `SELECT id, received_at, event_at, elapsed_ms, session_id, visitor, country, device, os, browser, app, type, path, referrer, data
     FROM events WHERE site = ?1 AND id > ?2 ORDER BY id LIMIT ?3`,
  )
    .bind(env.SITE || "unknown", sinceId, limit)
    .all();
  for (const row of results) {
    // PUBLISH_HASH_KEY がなければ visitor は出さない（安全側に倒す）
    row.visitor = row.visitor && env.PUBLISH_HASH_KEY ? await hmac16(env.PUBLISH_HASH_KEY, row.visitor) : null;
  }
  return Response.json({ rows: results, last_id: results.length ? results[results.length - 1].id : sinceId });
}

function str(value, max) {
  return typeof value === "string" && value ? value.slice(0, max) : null;
}

async function hmac16(key, message) {
  if (!key || !message) return null;
  const enc = new TextEncoder();
  const cryptoKey = await crypto.subtle.importKey("raw", enc.encode(key), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
  ]);
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message)));
  return [...sig.slice(0, 8)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

async function safeEqual(a, b) {
  // 長さや内容による応答時間の差を出さないよう、ハッシュ同士を比べる
  const enc = new TextEncoder();
  const [x, y] = await Promise.all([a, b].map((s) => crypto.subtle.digest("SHA-256", enc.encode(s))));
  return crypto.subtle.timingSafeEqual(x, y);
}

function parseUserAgent(ua) {
  const has = (re) => re.test(ua);
  const device = has(/bot|crawl|spider|slurp|preview|headless|facebookexternalhit|embedly/i)
    ? "bot"
    : has(/iPad|Tablet/i)
      ? "tablet"
      : has(/Mobi|Android|iPhone/i)
        ? "mobile"
        : "desktop";
  const os = has(/iPhone|iPad|iPod/) ? "ios" : has(/Android/) ? "android" : has(/Mac OS X/) ? "macos" : has(/Windows/) ? "windows" : has(/Linux|CrOS/) ? "linux" : "other";
  const browser = has(/Edg\//) ? "edge" : has(/OPR\//) ? "opera" : has(/Firefox\//) ? "firefox" : has(/Chrome\/|CriOS/) ? "chrome" : has(/Safari\//) ? "safari" : "other";
  const app = has(/Instagram/)
    ? "instagram"
    : has(/FBAN|FBAV/)
      ? "facebook"
      : has(/\bLine\//i)
        ? "line"
        : has(/Twitter|TwitterAndroid/)
          ? "x"
          : has(/musical_ly|Bytedance|TikTok/i)
            ? "tiktok"
            : has(/com\.google\.ios\.youtube|YouTube/i)
              ? "youtube"
              : null;
  return { device, os, browser, app };
}
