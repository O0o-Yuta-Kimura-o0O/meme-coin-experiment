// 公開前のチェック。開発用の設定が残っていたら、デプロイを止める。
// 使い方: node scripts/check-release.mjs <サイト名> [--env preview]
// --env preview のときは、プレビュー版として FORCE_LANG（開発中の日本語固定）のチェックを省く
//（環境ごとの vars は本番の設定を引き継がないので、プレビュー版には FORCE_LANG は入らない）
import { readFileSync } from "node:fs";

const site = process.argv[2];
const isPreview = process.argv.includes("--env") && process.argv[process.argv.indexOf("--env") + 1] === "preview";
const config = readFileSync(new URL(`../${site}/wrangler.jsonc`, import.meta.url), "utf8");
const problems = [];

if (!isPreview && /^\s*"FORCE_LANG"\s*:/m.test(config)) {
  problems.push('wrangler.jsonc の "FORCE_LANG"（開発中の日本語固定）が残っています。消してから公開してください。');
}
if (config.includes('"database_id": "00000000-0000-0000-0000-000000000000"')) {
  problems.push("wrangler.jsonc の database_id が仮の値のままです。`npx wrangler d1 create meme-analytics` の出力で置き換えてください。");
}

// 本番だけ：テストネットの表示や、まだ押せないボタンが残っていないか
// （scripts/set-launch.mjs を実行すれば直る）
if (!isPreview) {
  const html = readFileSync(new URL(`../${site}/public/index.html`, import.meta.url), "utf8");
  if (/class="net-badge"/.test(html) || /sepolia/i.test(html)) {
    problems.push("index.html にテストネット（Base Sepolia）の表示が残っています。`node scripts/set-launch.mjs` で本番のアドレスに切り替えてください。");
  }
  if (/data-track="cta_buy"[^>]*aria-disabled="true"|aria-disabled="true"[^>]*data-track="cta_buy"/.test(html)) {
    problems.push("index.html の「入手する」ボタンが「準備中」のままです。`node scripts/set-launch.mjs` で切り替えてください。");
  }
  if (/<a href="#"[^>]*data-track="social_/.test(html)) {
    problems.push("index.html に、リンク先のない SNS のリンク（href=\"#\"）が残っています。");
  }
}

if (problems.length) {
  console.error(`[${site}] 公開を中止しました:\n- ` + problems.join("\n- "));
  process.exit(1);
}
console.log(`[${site}] 公開前のチェック OK`);
