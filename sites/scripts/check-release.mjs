// 公開前のチェック。開発用の設定が残っていたら、デプロイを止める。
// 使い方: node scripts/check-release.mjs <サイト名>
import { readFileSync } from "node:fs";

const site = process.argv[2];
const config = readFileSync(new URL(`../${site}/wrangler.jsonc`, import.meta.url), "utf8");
const problems = [];

if (/^\s*"FORCE_LANG"\s*:/m.test(config)) {
  problems.push('wrangler.jsonc の "FORCE_LANG"（開発中の日本語固定）が残っています。消してから公開してください。');
}
if (config.includes('"database_id": "00000000-0000-0000-0000-000000000000"')) {
  problems.push("wrangler.jsonc の database_id が仮の値のままです。`npx wrangler d1 create meme-analytics` の出力で置き換えてください。");
}

if (problems.length) {
  console.error(`[${site}] 公開を中止しました:\n- ` + problems.join("\n- "));
  process.exit(1);
}
console.log(`[${site}] 公開前のチェック OK`);
