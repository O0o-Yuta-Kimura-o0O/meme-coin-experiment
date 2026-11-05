// スクロールに合わせた演出（控えめに）。
// - 本文はふわっと弾むように現れる（.reveal → .in）
// - ヒーローの小判ちゃんとコインは、スクロールに合わせて奥行きのある速さでずれる
// - 泳ぐ絵は枠の中でゆっくり動き、泡がのぼる
// - カートの小判ちゃん（小さい）が、読み進めた割合に合わせて画面の下を走る。戻ると向きを変える
// - カートの絵が見えたとき、小さな小判ちゃんが一度だけ画面を飛び越える
// 「視差効果を減らす」設定の人には何もしない（すべて最初から表示される）。
(() => {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const root = document.documentElement;
  root.classList.add("motion");

  const targets = document.querySelectorAll(
    ".ca-card, .section .label, .section h2, .section h3, .chapter p, .proverb, .art, .card, .halving, .steps li, .experiment p, .remark p",
  );
  targets.forEach((el) => el.classList.add("reveal"));
  document.querySelectorAll(".card, .steps li").forEach((el, i) => {
    el.style.transitionDelay = `${(i % 3) * 110}ms`;
  });

  // 画面の下から 1 割のところまで入ってきたら表示する（スクロールのたびに位置で判定する）
  let pending = [...targets];
  const reveal = () => {
    const line = innerHeight * 0.9;
    pending = pending.filter((el) => {
      if (el.getBoundingClientRect().top < line) {
        el.classList.add("in");
        if (el.classList.contains("cart")) hop();
        return false;
      }
      return true;
    });
  };

  const bar = document.createElement("div");
  bar.className = "progress";
  bar.setAttribute("aria-hidden", "true");
  document.body.append(bar);

  const nav = document.querySelector(".nav");
  const heroCat = document.querySelector(".hero-cat");
  const coins = [...document.querySelectorAll(".fc")];
  const swim = document.querySelector(".art.swim img");
  const cart = document.querySelector(".sprite-cart");
  const hopper = document.querySelector(".sprite-hop");
  const footer = document.querySelector(".footer");

  let lastY = scrollY;
  let facing = 1; // 1 = 右向きに進む（絵は左向きなので反転して表示する）
  let ticking = false;
  let hideTimer = 0;

  const update = () => {
    ticking = false;
    const y = scrollY;
    const max = root.scrollHeight - innerHeight;
    const p = max > 0 ? Math.min(Math.max(y / max, 0), 1) : 0;
    bar.style.transform = `scaleX(${p})`;
    nav?.classList.toggle("scrolled", y > 8);

    // ヒーロー：猫はゆっくり、コインはそれぞれの深さでずれる
    if (heroCat && y < innerHeight * 1.2) {
      heroCat.style.transform = `translateY(${(y * 0.18).toFixed(1)}px)`;
      coins.forEach((c) => {
        c.style.translate = `0 ${(-y * Number(c.dataset.depth || 0.3)).toFixed(1)}px`;
      });
    }

    // 泳ぐ絵：枠の中で少しだけ上下する
    if (swim) {
      const r = swim.parentElement.getBoundingClientRect();
      if (r.bottom > 0 && r.top < innerHeight) {
        const k = (r.top + r.height / 2 - innerHeight / 2) / innerHeight; // -1〜1
        swim.style.transform = `translateY(${(-6 + k * 6).toFixed(2)}%)`;
      }
    }

    // カートの小判ちゃん：ヒーローを過ぎたら現れ、読んだ割合に合わせて左から右へ走る。フッターに着いたら隠れる
    if (cart) {
      const w = cart.offsetWidth || 70;
      const x = 12 + p * (innerWidth - w - 24);
      if (y !== lastY) facing = y > lastY ? 1 : -1;
      // 文章に重ならないよう、スクロールしている間だけ見せ、止まって 1.2 秒たったら消える
      const nearEnd = footer && footer.getBoundingClientRect().top < innerHeight - 10;
      const moving = y !== lastY;
      if (moving) {
        clearTimeout(hideTimer);
        hideTimer = setTimeout(() => cart.classList.remove("show"), 1200);
      }
      cart.classList.toggle("show", moving && y > innerHeight * 0.6 && !nearEnd);
      const bump = Math.abs(y - lastY) > 1 ? Math.sin(y / 18) * 2 : 0; // 走っている間だけ小さく揺れる
      cart.style.transform = `translate(${x.toFixed(1)}px, ${bump.toFixed(1)}px) scaleX(${-facing})`;
    }
    lastY = y;
  };

  // 小さな小判ちゃんが、画面の右下から左上へ弧を描いて一度だけ飛ぶ
  let hopped = false;
  function hop() {
    if (hopped || !hopper) return;
    hopped = true;
    const w = innerWidth, h = innerHeight;
    const from = { x: w + 40, y: h * 0.75 };
    const to = { x: -120, y: h * 0.55 };
    const peak = h * 0.12;
    const frames = [];
    for (let i = 0; i <= 24; i++) {
      const t = i / 24;
      const x = from.x + (to.x - from.x) * t;
      const y = from.y + (to.y - from.y) * t - 4 * (from.y - peak) * t * (1 - t) * 0.9;
      frames.push({ transform: `translate(${x}px, ${y}px) rotate(${-25 + 50 * t}deg)`, opacity: t < 0.05 || t > 0.95 ? 0 : 1 });
    }
    hopper.animate(frames, { duration: 2200, easing: "ease-in-out", fill: "forwards" });
  }

  addEventListener(
    "scroll",
    () => {
      reveal();
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    },
    { passive: true },
  );
  addEventListener("resize", () => (reveal(), update()), { passive: true });
  document.addEventListener("visibilitychange", () => (reveal(), update()));
  reveal();
  update();
  setTimeout(reveal, 4000);
})();
