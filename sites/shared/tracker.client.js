// 閲覧解析スクリプト（Worker が /x/s.js として配信する）。
// Cookie は使わない。セッション ID はタブごとのランダム値（sessionStorage）。
// Global Privacy Control / Do Not Track が有効なブラウザでは何も送らない。
// 計測したい要素には data-track="名前" を付ける。任意のイベントは window.skTrack("名前", {...}) で送る。
(() => {
  if (navigator.globalPrivacyControl || navigator.doNotTrack === "1") return;

  const ENDPOINT = "/x/e";
  const t0 = performance.now();
  const elapsed = () => Math.round(performance.now() - t0);
  const queue = [];

  let sid;
  try {
    sid = sessionStorage.getItem("sk_sid") || crypto.randomUUID();
    sessionStorage.setItem("sk_sid", sid);
  } catch {
    sid = crypto.randomUUID();
  }

  const flush = (beacon) => {
    if (!queue.length) return;
    const body = JSON.stringify({ s: sid, n: Date.now(), e: queue.splice(0) });
    if (beacon && navigator.sendBeacon && navigator.sendBeacon(ENDPOINT, body)) return;
    fetch(ENDPOINT, { method: "POST", body, keepalive: true }).catch(() => {});
  };

  const push = (t, d, r) => {
    queue.push({ t, c: Date.now(), m: elapsed(), p: location.pathname, r, d });
    if (queue.length >= 20) flush();
  };

  // 来訪：外部の参照元（ホスト名のみ）と UTM パラメータ
  let ref;
  try {
    const u = new URL(document.referrer);
    if (u.host !== location.host) ref = u.host;
  } catch {}
  const params = new URLSearchParams(location.search);
  const view = { lang: navigator.language, page_lang: document.documentElement.lang, w: innerWidth };
  for (const k of ["utm_source", "utm_medium", "utm_campaign", "ref"]) {
    const v = params.get(k);
    if (v) view[k] = v.slice(0, 64);
  }
  push("view", view, ref);

  // クリック：data-track の付いた要素とリンク
  document.addEventListener(
    "click",
    (ev) => {
      const el = ev.target instanceof Element && ev.target.closest("[data-track], a");
      if (!el) return;
      push("click", { id: el.dataset.track || null, href: (el.getAttribute("href") || "").slice(0, 200) || null });
      if (el.tagName === "A" && el.host && el.host !== location.host) flush(true);
    },
    { capture: true },
  );

  // スクロールの深さ（25 / 50 / 75 / 100%）
  const marks = [25, 50, 75, 100];
  let hit = 0;
  addEventListener(
    "scroll",
    () => {
      const h = document.documentElement;
      const pct = ((h.scrollTop + innerHeight) / h.scrollHeight) * 100;
      while (hit < marks.length && pct >= marks[hit] - 1) push("scroll", { pct: marks[hit++] });
    },
    { passive: true },
  );

  // 表示時間と離脱：hidden（タブを離れた）/ visible（戻った）/ leave（ページを閉じた）
  let visibleMs = 0;
  let visibleSince = document.visibilityState === "visible" ? elapsed() : null;
  const stopClock = () => {
    if (visibleSince !== null) {
      visibleMs += elapsed() - visibleSince;
      visibleSince = null;
    }
  };
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "hidden") {
      stopClock();
      push("hidden", { visible_ms: visibleMs });
      flush(true);
    } else {
      visibleSince = elapsed();
      push("visible");
    }
  });
  addEventListener("pagehide", () => {
    stopClock();
    push("leave", { visible_ms: visibleMs });
    flush(true);
  });

  setInterval(() => flush(), 15000);
  window.skTrack = (id, d) => push("custom", { id, ...(d || {}) });
})();
