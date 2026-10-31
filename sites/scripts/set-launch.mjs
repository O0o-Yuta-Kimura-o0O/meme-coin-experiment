// 本番のローンチ後に、サイトを本番用の表示に切り替える。
// 使い方: node scripts/set-launch.mjs <サイト名> <トークンのアドレス> [サイトの URL]
//   例: node scripts/set-launch.mjs seppuku 0x1234...abcd https://seppuku-site.meme-coin-sites.workers.dev
// やること（public/index.html と coins/<サイト名>/tracking.json を書き換える）
//   - コントラクトのアドレスを本番のものにし、リンク先を Basescan にする
//   - テストネットの表示を外す
//   - 「入手する」ボタンを Uniswap のスワップ画面へのリンクにする
//   - SNS のリンクを tracking.json のアカウントにする。アカウントが空のものは載せない
//   - サイトの URL を渡したときは、og:image を絶対 URL にし、og:url を入れる
// 何度実行しても同じ結果になる（アドレスを変えて実行し直してもよい）。
import { readFileSync, writeFileSync } from "node:fs";

const [site, token, siteUrlArg] = process.argv.slice(2);
if (!site || !/^0x[0-9a-fA-F]{40}$/.test(token || "")) {
  console.error("使い方: node scripts/set-launch.mjs <サイト名> <トークンのアドレス> [サイトの URL]");
  process.exit(1);
}

const htmlPath = new URL(`../${site}/public/index.html`, import.meta.url);
const trackingPath = new URL(`../../coins/${site}/tracking.json`, import.meta.url);
const tracking = JSON.parse(readFileSync(trackingPath, "utf8"));
const siteUrl = (siteUrlArg || tracking.site_url || "").replace(/\/+$/, "");
let html = readFileSync(htmlPath, "utf8");

function replaceOnce(pattern, replacement, what) {
  if (!pattern.test(html)) {
    console.error(`index.html に「${what}」が見つかりません。手で確認してください。`);
    process.exit(1);
  }
  html = html.replace(pattern, replacement);
}

const short = `${token.slice(0, 6)}…${token.slice(-4)}`;
const swapUrl = `https://app.uniswap.org/swap?chain=base&amp;inputCurrency=NATIVE&amp;outputCurrency=${token}`;

// コントラクトのアドレス
replaceOnce(
  /<code id="ca"[^>]*>[\s\S]*?<\/code>/,
  `<code id="ca" data-address="${token}"><a href="https://basescan.org/token/${token}" target="_blank" rel="noopener" data-track="ca_explorer">${short}</a></code>`,
  "コントラクトのアドレス（<code id=\"ca\">）"
);

// テストネットの表示（とその説明のコメント）
html = html.replace(/\s*<!-- テストネットのアドレスを載せている間だけ[^>]*-->/, "");
html = html.replace(/\s*<span class="net-badge"[^>]*>[^<]*<\/span>/, "");
html = html.replace(/<!-- ローンチ後: data-address にトークンのアドレスを入れ[^>]*-->/, "<!-- 本番のトークン（scripts/set-launch.mjs で設定） -->");

// 「入手する」ボタン
replaceOnce(
  /<a class="btn primary"[^>]*data-track="cta_buy"[^>]*>[^<]*<\/a>/,
  `<a class="btn primary" href="${swapUrl}" target="_blank" rel="noopener" data-track="cta_buy" data-i18n="cta_buy_live">Acquire on Uniswap</a>`,
  "「入手する」ボタン"
);
html = html.replace(/<!-- ローンチ後: href を Uniswap のスワップ URL に差し替え[^>]*-->/, "<!-- Uniswap のスワップ画面（scripts/set-launch.mjs で設定） -->");

// SNS のリンク
const social = {
  x: tracking.x?.username && `https://x.com/${tracking.x.username}`,
  youtube: tracking.youtube?.channel_id && `https://www.youtube.com/channel/${tracking.youtube.channel_id}`,
  instagram: tracking.instagram?.username && `https://www.instagram.com/${tracking.instagram.username}/`,
};
const labels = { x: "X", youtube: "YouTube", instagram: "Instagram" };
// いったん全部外してから、アカウントがあるものだけをプライバシーのリンクの前に入れ直す
html = html.replace(/\s*<a [^>]*data-track="social_[a-z]+"[^>]*>[^<]*<\/a>/g, "");
html = html.replace(/\s*<!-- アカウント開設後: href を差し替え -->/, "");
const links = Object.entries(social)
  .filter(([, url]) => url)
  .map(([key, url]) => `<a href="${url}" target="_blank" rel="noopener" data-track="social_${key}">${labels[key]}</a>\n    `)
  .join("");
replaceOnce(/<a href="privacy\.html"/, `${links}<a href="privacy.html"`, "プライバシーのリンク");

// og:image と og:url（サイトの URL がわかっているときだけ）
if (siteUrl) {
  html = html.replace(/\s*<!-- 独自ドメインが決まったら絶対 URL にする[^>]*-->/, "");
  html = html.replace(/<meta property="og:image" content="[^"]*">/, `<meta property="og:image" content="${siteUrl}/og.jpg">`);
  if (!html.includes('property="og:url"')) {
    html = html.replace(/(<meta property="og:type"[^>]*>)/, `$1\n  <meta property="og:url" content="${siteUrl}/">`);
  } else {
    html = html.replace(/<meta property="og:url" content="[^"]*">/, `<meta property="og:url" content="${siteUrl}/">`);
  }
}

writeFileSync(htmlPath, html);
tracking.token_address = token;
if (siteUrl) tracking.site_url = siteUrl;
writeFileSync(trackingPath, JSON.stringify(tracking, null, 2) + "\n");

const missing = Object.entries(social).filter(([, url]) => !url).map(([k]) => labels[k]);
console.log(`[${site}] 本番の表示に切り替えました: ${token}`);
if (!siteUrl) console.log("- サイトの URL が未設定のため、og:image は相対パスのまま（X などでプレビュー画像が出ない）");
if (missing.length) console.log(`- アカウント未設定のため載せていない SNS: ${missing.join("、")}（tracking.json に書いてから、もう一度実行する）`);
