// Originally created by Codex && MYNAMEISJEFF482 for Scenic Route Servers & other communities

(() => {
  const OVERLAY_ID   = "srs-loading-overlay";
  const CONFIG_URL   = "/ui/scenic_route_loading/loading_config.json";
  const PIT_TRIGGER  = "5.jpg";
  const GIF_BASE     = "/ui/scenic_route_loading/images/";
  const GIF_NAMES    = ["PIT1.gif", "PIT2.gif", "PIT3.gif", "PIT4.gif"];
  let completedStages = 0;
  let totalStages = 6;

  let cfg = null;
  let lastCfg = null;
  let overlayEl = null;
  let mo = null;
  let slideshowTimer = 0;
  let progressTimer = 0;
  let audioEl = null;
  let images = [];
  let tracks = [];
  let imgIndex = 0;
  let lastStatus = "";
  let lastPct = -1;
  let eventStatus = "";
  let eventProgress = null;
  let eventsBound = false;
  let holdUntil = 0;
  const audioFadeMs = 1500;
  let audioFading = false;
  let audioFadeUntil = 0;

  function tryBindBridgeEvents() {
    if (eventsBound) return;
    const events = window.bridge?.events;
    if (!events || typeof events.on !== "function") return;

    events.on("UpdateLoadingProgressV2", (data) => {
      if (!data || typeof data !== "object") return;
      const entry = Array.isArray(data.currentEntries) ? data.currentEntries[0] : null;
      const msg = entry?.message;
      const prog = entry?.progress;
      if (typeof msg === "string" && msg.trim()) {
        eventStatus = msg.trim().replace(/\s+/g, " ");
      }
      if (Number.isFinite(prog)) {
        eventProgress = Math.max(0, Math.min(100, Number(prog)));
      }
      if (Array.isArray(data.historyEntries)) {
        completedStages = data.historyEntries.length;
        const currentCount = Array.isArray(data.currentEntries) ? data.currentEntries.length : 0;
        totalStages = Math.max(totalStages, completedStages + currentCount + 1);
      }
    });

    events.on("LoadingScreen", (data) => {
      if (!data || typeof data !== "object") return;
      if (data.active === false) {
        eventStatus = "";
        eventProgress = null;
        if (audioEl) {
          const fadeMs = Number(lastCfg?.music?.fadeOutMs ?? audioFadeMs);
          fadeOutAudio(audioEl, fadeMs);
        }
      }
    });

    eventsBound = true;
  }

  function normalizeCfg(raw) {
    const def = {
      title: "Welcome to the server",
      holdAfterLoadSec: 0,
      slideshow: {
        enabled: true,
        intervalSec: 12,
        fadeSec: 3,
        shuffle: true,
        useStockImages: false,
        stockCount: 18,
        images: [],
      },
      music: { enabled: false, volume: 0.45, tracks: [], shuffle: true, fadeOutMs: 1500 },
    };
    const c = Object.assign({}, def, raw || {});
    c.slideshow = Object.assign({}, def.slideshow, c.slideshow || {});
    c.music = Object.assign({}, def.music, c.music || {});
    c.slideshow.intervalSec = Math.max(3, Number(c.slideshow.intervalSec || def.slideshow.intervalSec));
    c.slideshow.fadeSec = Math.max(0.5, Number(c.slideshow.fadeSec || def.slideshow.fadeSec));
    c.music.volume = Math.min(1, Math.max(0, Number(c.music.volume ?? def.music.volume)));
    c.music.fadeOutMs = Math.max(0, Number(c.music.fadeOutMs ?? def.music.fadeOutMs));
    c.slideshow.images = Array.isArray(c.slideshow.images) ? c.slideshow.images.filter(Boolean) : [];
    c.music.tracks = Array.isArray(c.music.tracks) ? c.music.tracks.filter(Boolean) : [];
    c.slideshow.shuffle = !!c.slideshow.shuffle;
    c.slideshow.useStockImages = c.slideshow.useStockImages !== false;
    c.slideshow.stockCount = Math.max(0, Math.floor(Number(c.slideshow.stockCount ?? def.slideshow.stockCount)));
    c.music.shuffle = !!c.music.shuffle;
    c.holdAfterLoadSec = Math.max(0, Number(c.holdAfterLoadSec ?? def.holdAfterLoadSec));
    return c;
  }

  function buildStockImageList(count) {
    const n = Math.max(0, Math.floor(Number(count || 0)));
    const out = [];
    for (let i = 1; i <= n; i++) {
      out.push(`/ui/ui-vue/src/assets/images/loading/drive/${i}.jpg`);
    }
    return out;
  }

  async function loadConfig() {
    if (cfg) return cfg;
    try {
      const res = await fetch(CONFIG_URL, { cache: "no-store" });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      cfg = normalizeCfg(await res.json());
      return cfg;
    } catch (e) {
      cfg = normalizeCfg(null);
      return cfg;
    }
  }

  function isLoadingScreenPresent() {
    return !!document.querySelector(".loading-screen");
  }

  function ensureOverlay(c) {
    if (overlayEl) return overlayEl;

    const root = document.querySelector(".loading-screen");
    if (!root) return null;

    document.body.classList.add("srs-loading-active");

    overlayEl = document.createElement("div");
    overlayEl.id = OVERLAY_ID;

    overlayEl.innerHTML = `
      <div class="srs-bg">
        <div class="srs-bg-layer srs-bg-a"></div>
        <div class="srs-bg-layer srs-bg-b"></div>
      </div>
      <div class="srs-title"></div>
      <div class="srs-bottom">
        <div class="srs-status"></div>
        <div class="srs-bar-wrap">
          <div class="srs-bar"><div class="srs-bar-fill"></div></div>
          <span class="srs-bar-pct"></span>
        </div>
      </div>
    `;

    document.body.appendChild(overlayEl);

    const gifDiv = document.createElement("div");
    gifDiv.id = "srs-pit-gifs";
    gifDiv.innerHTML = GIF_NAMES.map(g => `<img src="${GIF_BASE}${g}" alt="">`).join("");
    overlayEl.appendChild(gifDiv);

    overlayEl.style.setProperty("--srs-fade", `${c.slideshow.fadeSec}s`);
    lastCfg = c;

    const titleEl = overlayEl.querySelector(".srs-title");
    if (titleEl) titleEl.textContent = c.title;

    const stock = c.slideshow.useStockImages ? buildStockImageList(c.slideshow.stockCount) : [];
    const custom = (c.slideshow.images || []).slice();
    const seen = new Set();
    images = [];
    for (const u of stock.concat(custom)) {
      if (!u || typeof u !== "string") continue;
      if (seen.has(u)) continue;
      seen.add(u);
      images.push(u);
    }
    tracks = (c.music.tracks || []).slice();

    if (c.slideshow.shuffle) shuffleInPlace(images);
    if (c.music.shuffle) shuffleInPlace(tracks);

    imgIndex = 0;

    preloadImages(images);

    if (c.slideshow.enabled) startSlideshow(c);
    if (c.music.enabled) startMusic(c);

    return overlayEl;
  }

  function teardown() {
    if (audioFadeUntil && Date.now() < audioFadeUntil) return;
    if (mo) { mo.disconnect(); mo = null; }
    if (slideshowTimer) { clearTimeout(slideshowTimer); slideshowTimer = 0; }
    if (progressTimer) { clearInterval(progressTimer); progressTimer = 0; }
    stopMusic();
    images = [];
    tracks = [];
    imgIndex = 0;
    lastStatus = "";
    lastPct = -1;
    eventStatus = "";
    eventProgress = null;
    completedStages = 0;
    totalStages = 6;
    holdUntil = 0;
    audioFadeUntil = 0;
    document.body.classList.remove("srs-loading-active");
    if (overlayEl) { overlayEl.remove(); overlayEl = null; }
  }

  function shuffleInPlace(arr) {
    for (let i = arr.length - 1; i > 0; i--) {
      const j = Math.floor(Math.random() * (i + 1));
      [arr[i], arr[j]] = [arr[j], arr[i]];
    }
  }

  function updateGifOverlay(imageUrl) {
    const el = overlayEl?.querySelector("#srs-pit-gifs");
    if (!el) return;
    el.classList.toggle("is-visible", typeof imageUrl === "string" && imageUrl.includes(PIT_TRIGGER));
  }

  function startSlideshow(c) {
    const a = overlayEl?.querySelector(".srs-bg-a");
    const b = overlayEl?.querySelector(".srs-bg-b");
    if (!a || !b) return;

    if (!images.length) {
      a.classList.add("is-active");
      a.style.backgroundImage = "none";
      b.style.backgroundImage = "none";
      return;
    }

    a.style.backgroundImage = `url("${images[imgIndex % images.length]}")`;
    a.classList.add("is-active");
    b.classList.remove("is-active");
    updateGifOverlay(images[imgIndex % images.length]);

    const tick = async () => {
      if (!overlayEl || !isLoadingScreenPresent()) return;
      const nextUrl = images[(++imgIndex) % images.length];
      const inactive = a.classList.contains("is-active") ? b : a;
      const active   = a.classList.contains("is-active") ? a : b;
      inactive.style.backgroundImage = `url("${nextUrl}")`;
      inactive.classList.add("is-active");
      active.classList.remove("is-active");
      updateGifOverlay(nextUrl);
      slideshowTimer = setTimeout(tick, Math.floor(c.slideshow.intervalSec * 1000));
    };

    slideshowTimer = setTimeout(tick, Math.floor(c.slideshow.intervalSec * 1000));
  }

  function startMusic(c) {
    if (!tracks.length) return;
    audioEl = document.createElement("audio");
    audioEl.preload = "auto";
    audioEl.loop = true;
    audioEl.volume = c.music.volume;
    audioEl.src = tracks[0];
    audioFading = false;
    overlayEl?.appendChild(audioEl);
    audioEl.play().catch(() => {});
  }

  function stopMusic() {
    if (!audioEl) return;
    try {
      const fadeMs = Number(lastCfg?.music?.fadeOutMs ?? audioFadeMs);
      fadeOutAudio(audioEl, fadeMs);
    } catch {}
  }

  function fadeOutAudio(el, durationMs) {
    if (audioFading) return;
    audioFading = true;
    audioFadeUntil = Date.now() + Math.max(0, Number(durationMs || 0));
    const startVol = el.volume;
    const start = performance.now();
    const step = (t) => {
      const k = Math.min(1, (t - start) / durationMs);
      el.volume = Math.max(0, startVol * (1 - k));
      if (k < 1) {
        requestAnimationFrame(step);
      } else {
        try { el.pause(); } catch {}
        el.remove();
        if (audioEl === el) audioEl = null;
        audioFading = false;
        audioFadeUntil = 0;
      }
    };
    requestAnimationFrame(step);
  }

  function preloadImages(list) {
    for (const src of list) {
      if (!src || typeof src !== "string") continue;
      const img = new Image();
      img.decoding = "async";
      img.src = src;
    }
  }

  function getProgressPercent(root) {
    const stagePct = 100 / totalStages;
    const base = completedStages * stagePct;
    let stageProg = null;

    if (eventProgress != null) {
      stageProg = eventProgress;
    } else {
      const fill = root.querySelector(".bng-progress-bar .progress-fill");
      if (fill && fill instanceof HTMLElement) {
        const bar = fill.parentElement;
        if (bar instanceof HTMLElement) {
          const barWidth = bar.getBoundingClientRect().width;
          const rightPx = parseFloat(getComputedStyle(fill).right || "");
          if (Number.isFinite(rightPx) && barWidth > 0) {
            stageProg = Math.max(0, Math.min(100, 100 - (rightPx / barWidth) * 100));
          }
        }
      }
      if (stageProg == null) {
        const pb = root.querySelector('[role="progressbar"][aria-valuenow]');
        if (pb) {
          const v = Number(pb.getAttribute("aria-valuenow"));
          if (Number.isFinite(v)) stageProg = Math.max(0, Math.min(100, v));
        }
      }
    }

    if (stageProg != null) return Math.min(99, base + (stageProg / 100) * stagePct);
    return completedStages > 0 ? Math.min(99, base) : null;
  }

  function getStatusText(root) {
    if (eventStatus) return eventStatus;
    const preferred = [
      ".loading-screen-progress .progress-status",
      ".loading-screen-progress .progress-box",
      ".loading-screen .progress-status",
      ".loading-screen .custom-text-panel",
    ];
    for (const sel of preferred) {
      const el = root.querySelector(sel);
      if (el) {
        const t = (el.textContent || "").trim().replace(/\s+/g, " ");
        if (t) return t;
      }
    }
    let best = "";
    const nodes = root.querySelectorAll("li, span, p, div");
    for (const el of nodes) {
      if (!(el instanceof HTMLElement)) continue;
      if (el.children && el.children.length) continue;
      const t = (el.textContent || "").trim().replace(/\s+/g, " ");
      if (!t || t.length > 120) continue;
      if (/^\d+%$/.test(t)) continue;
      if (/javascript enabled/i.test(t)) continue;
      if (t.length >= best.length) best = t;
    }
    return best;
  }

  function applyOverlayState(root) {
    if (!overlayEl) return;
    const status = getStatusText(root);
    const pct = getProgressPercent(root);
    const statusEl = overlayEl.querySelector(".srs-status");
    const fillEl   = overlayEl.querySelector(".srs-bar-fill");
    const pctEl    = overlayEl.querySelector(".srs-bar-pct");
    if (statusEl && status && status !== lastStatus) {
      statusEl.textContent = status;
      lastStatus = status;
    }
    if (fillEl) {
      if (pct == null) {
        if (lastPct < 0) fillEl.classList.add("is-indeterminate");
      } else {
        fillEl.classList.remove("is-indeterminate");
        if (pct > lastPct) {
          fillEl.style.width = `${pct}%`;
          lastPct = pct;
        }
      }
    }
    if (pctEl && pct != null) {
      pctEl.textContent = `${Math.round(pct)}%`;
    }
  }

  function ensureMutationObserver(root) {
    if (mo) return;
    mo = new MutationObserver(() => {
      if (!overlayEl) return;
      applyOverlayState(root);
    });
    mo.observe(root, { subtree: true, childList: true, characterData: true, attributes: true });
  }

  async function tick() {
    tryBindBridgeEvents();
    const c = await loadConfig();
    const root = document.querySelector(".loading-screen");
    if (!root) {
      if (overlayEl || mo) {
        const holdMs = Math.max(0, Number(c?.holdAfterLoadSec || 0)) * 1000;
        if (holdMs > 0) {
          if (!holdUntil) holdUntil = Date.now() + holdMs;
          if (Date.now() < holdUntil) return;
        }
        teardown();
      }
      return;
    }
    holdUntil = 0;
    const ov = ensureOverlay(c);
    if (!ov) return;
    ensureMutationObserver(root);
    applyOverlayState(root);
    if (!progressTimer) {
      progressTimer = setInterval(() => {
        const r = document.querySelector(".loading-screen");
        if (!r) { teardown(); return; }
        applyOverlayState(r);
      }, 250);
    }
  }

  setInterval(() => {
    tick().catch(() => {});
  }, 300);
})();
