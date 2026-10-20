// スクロールに合わせた演出。
// - 本文は画面に入ったところで静かに浮かび上がる（.reveal → .in。画面より上にあるものも表示済みになる）
// - ヒーローの写真はスクロールに合わせてゆっくり奥へ引いていく
// - 画面上端の細い線が読み進めた割合を示す
// 「視差効果を減らす」設定の人や、古いブラウザでは何もしない（すべて最初から表示される）。
(() => {
  if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;

  const root = document.documentElement;
  root.classList.add("motion");

  const targets = document.querySelectorAll(
    ".section .label, .prose p, blockquote, .defs > div, .portrait, .statement, .formula, .halving, .steps li, #experiment p, .remark p, .fin",
  );
  targets.forEach((el) => el.classList.add("reveal"));
  document.querySelectorAll(".defs > div, .steps li").forEach((el, i) => {
    el.style.transitionDelay = `${(i % 3) * 120}ms`;
  });

  // 画面の下から 1 割のところまで入ってきたら表示する。
  // IntersectionObserver は環境によって発火しないことがあったので、スクロールのたびに位置で判定する（要素は 30 個ほど）。
  let pending = [...targets];
  const reveal = () => {
    const line = innerHeight * 0.9;
    pending = pending.filter((el) => {
      if (el.getBoundingClientRect().top < line) {
        el.classList.add("in");
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
  const img = document.querySelector(".hero-figure img");
  let ticking = false;
  const update = () => {
    ticking = false;
    const y = scrollY;
    const max = root.scrollHeight - innerHeight;
    bar.style.transform = `scaleX(${max > 0 ? Math.min(y / max, 1) : 0})`;
    nav?.classList.toggle("scrolled", y > 8);
    if (img) {
      const h = img.parentElement.offsetHeight || 1;
      const p = Math.min(Math.max(y / h, 0), 1);
      img.style.transform = `translateY(${(p * h * 0.18).toFixed(1)}px) scale(${(1.06 - p * 0.06).toFixed(4)})`;
      img.style.opacity = String(1 - p * 0.35);
    }
  };
  addEventListener(
    "scroll",
    () => {
      // 表示の判定は描画のタイミング（requestAnimationFrame）に頼らず、毎回すぐ行う。
      // タブが裏にあるときなど rAF が止まっても、本文が隠れたままにならないようにするため。
      reveal();
      if (!ticking) {
        ticking = true;
        requestAnimationFrame(update);
      }
    },
    { passive: true },
  );
  addEventListener("resize", () => (reveal(), update()), { passive: true });
  // 裏のタブで開かれてから表に出てきたときにも、その時点の位置で表示し直す
  document.addEventListener("visibilitychange", () => (reveal(), update()));
  reveal();
  update();
  // 念のため：何らかの理由で表示されないままの要素が残らないよう、4秒後に画面より上にあるものはすべて表示する
  setTimeout(reveal, 4000);
})();
