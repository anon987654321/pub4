// MASTER particle face 2026 — vision features 81–118 (interaction, aesthetic, a11y).
(() => {
  "use strict";

  const V = window.MASTER_FACE_VISION;
  if (!V) return;

  const root = document.documentElement;
  const body = document.body;
  const qs = (k) => new URLSearchParams(location.search).get(k);

  function emit(type, detail = {}) {
    window.MASTERVisual?.event?.(type, detail);
  }

  const KONAMI = ["ArrowUp", "ArrowUp", "ArrowDown", "ArrowDown", "ArrowLeft", "ArrowRight", "ArrowLeft", "ArrowRight", "b", "a"];

  /* 81–95 interaction */
  V.register(81, "tap-hold accelerate", (ctx) => {
    const on = !!ctx.detail.accelerate;
    ctx.st.accelerate = on;
    root.dataset.tapHoldAccel = on ? "1" : "";
    if (on) {
      ctx.st.pulse = Math.min(1, (ctx.st.pulse || 0) + 0.35);
      emit("input:accelerate", { topology: "papua-mask", entropy: 0.35, confidence: 0.8, mode: "accelerate" });
      V.spawn(2, { kind: 81, arousal: 0.6, vy: 0.014, decay: 0.012 });
    }
  });

  V.register(82, "gyro gravity", (ctx) => {
    const beta = Number(ctx.detail.beta ?? 0);
    const gamma = Number(ctx.detail.gamma ?? 0);
    ctx.st.gravityX = Math.max(-1, Math.min(1, gamma / 45));
    ctx.st.gravityY = Math.max(-1, Math.min(1, (beta - 45) / 45));
    root.dataset.gyroGravity = `${ctx.st.gravityX.toFixed(2)},${ctx.st.gravityY.toFixed(2)}`;
    V.css("--gyro-x", ctx.st.gravityX.toFixed(3));
    V.css("--gyro-y", ctx.st.gravityY.toFixed(3));
  });

  V.register(83, "chat scroll parallax", (ctx) => {
    const y = Number(ctx.detail.scrollTop ?? 0);
    V.css("--chat-parallax", `${(y * 0.02) | 0}px`);
    root.dataset.chatParallax = String(y);
  });

  V.register(84, "pinch mouth zoom dev", (ctx) => {
    const zoom = Math.max(0.5, Math.min(2.5, Number(ctx.detail.zoom ?? ctx.st.mouthZoom ?? 1)));
    ctx.st.mouthZoom = zoom;
    root.dataset.mouthZoom = zoom.toFixed(2);
    V.css("--mouth-zoom", zoom.toFixed(2));
    window.MASTER_FACE_BLEND?.pushBlend?.({ mouthWide: zoom * 0.1 });
  });

  V.register(85, "long-press felt inspector", () => {
    const felt = window.MASTERFeltState?.collectFeltState?.() || window.collectFeltState?.();
    let panel = document.getElementById("felt-inspector");
    if (!panel) {
      panel = document.createElement("pre");
      panel.id = "felt-inspector";
      panel.className = "felt-inspector";
      panel.setAttribute("aria-live", "polite");
      body.appendChild(panel);
    }
    panel.textContent = felt ? String(felt) : "no felt";
    panel.dataset.visible = "1";
    window.setTimeout(() => { panel.dataset.visible = "0"; }, 3200);
  });

  V.register(86, "space council pulse", (ctx) => {
    ctx.st.pulse = Math.min(1, (ctx.st.pulse || 0) + 0.45);
    root.dataset.spaceCouncilPulse = String(Date.now());
    emit("council:pulse", { topology: "papua-mask", entropy: 0.32, confidence: 0.7, mode: "council" });
    for (let n = 0; n < 3; n++) {
      V.spawn(3, { kind: 86, vx: (n - 1) * 0.012, arousal: 0.5, decay: 0.014 });
    }
  });

  V.register(87, "photograph supernova", (ctx) => {
    ctx.st.flash = 1;
    ctx.st.pulse = 1;
    root.dataset.photoSupernova = "1";
    for (let n = 0; n < 6; n++) {
      V.spawn(2, { kind: 87, vx: (Math.random() - 0.5) * 0.04, vy: (Math.random() - 0.5) * 0.04, arousal: 0.9, decay: 0.01 });
    }
    window.setTimeout(() => delete root.dataset.photoSupernova, 800);
  });

  V.register(88, "zin focus beam", (ctx) => {
    const focused = !!ctx.detail.focused;
    root.dataset.zinFocusBeam = focused ? "1" : "";
    V.css("--zin-beam", focused ? "1" : "0");
    if (focused) {
      emit("input:focus", { topology: "papua-mask", entropy: 0.14, confidence: 0.88, mode: "attending" });
      V.spawn(2, { kind: 88, attention: 0.75, decay: 0.013 });
    }
  });

  V.register(89, "viseme haptics", (ctx) => {
    const shape = ctx.detail.shape || ctx.detail.viseme || "rest";
    const amp = Number(ctx.detail.amp ?? 0.5);
    if (navigator.vibrate) navigator.vibrate(Math.min(40, 8 + amp * 20));
    root.dataset.visemeHaptic = String(shape).slice(0, 8);
  });

  V.register(90, "gamepad OK primer", () => {
    const primer = document.getElementById("primer");
    primer?.click?.();
    root.dataset.gamepadPrimer = "1";
  });

  V.register(91, "double-tap focus dim", (ctx) => {
    body.classList.toggle("focus-dim", !!ctx.detail.active);
    root.dataset.doubleTapFocus = "1";
    window.MASTER_FACE?.toggleFocusMode?.();
  });

  V.register(92, "URL mood restore", (ctx) => {
    const mood = ctx.detail.mood || qs("mood");
    const mode = ctx.detail.mode || qs("mode");
    if (mood) ctx.st.mood = mood;
    if (mode && ctx.st.mode === "idle") ctx.st.mode = mode;
    if (mood || mode) root.dataset.urlMoodRestore = `${mood || ""}/${mode || ""}`;
  });

  V.register(93, "share card hook", async (ctx) => {
    const data = {
      title: "MASTER face",
      text: ctx.detail.text || `mood ${V.state().mood || "idle"}`,
      url: location.href
    };
    if (navigator.share) {
      try { await navigator.share(data); return; } catch (err) { window.MASTER_LOG?.warn?.("face_vision_c:share", err); }
    }
    await navigator.clipboard?.writeText?.(data.url).catch(() => {});
    emit("share:card", { topology: "papua-mask", entropy: 0.1, confidence: 0.9, mode: "share" });
  });

  V.register(94, "describe face TTS", (ctx) => {
    const st = ctx.st;
    const line = `mode ${st.mode || "idle"}, mood ${st.mood || "idle"}, confidence ${(st.confidence ?? 0.86).toFixed(2)}`;
    window.MASTER_FACE?.ttsSpeak?.(line) || window.MASTER_FACE?.speak?.(line);
    emit("face:describe", { topology: "papua-mask", entropy: 0.12, confidence: st.confidence || 0.86, mode: "describe" });
  });

  V.register(95, "Konami CRT", () => {
    root.dataset.runtimeProfile = "crt";
    root.dataset.konamiCrt = "1";
    V.css("--face-scanline", "0.42");
    emit("konami:crt", { topology: "papua-mask", entropy: 0.2, confidence: 0.95, mode: "crt" });
    V.spawn(2, { kind: 95, confidence: 0.9, decay: 0.02 });
  });

  /* 96–108 aesthetic */
  V.register(96, "Inter 200 typography", () => {
    V.css("--face-font", '"Inter", system-ui, sans-serif');
    V.css("--face-font-weight", "200");
    root.dataset.typography = "Inter-200";
  });

  V.register(97, "brutalist flag", () => {
    const brutal = qs("brutalist") === "1"
      || window.MASTER_RUNTIME?.enhancements?.includes?.("brutalist_profile");
    if (brutal) {
      root.dataset.brutalist = "1";
      body.classList.add("brutalist-mode");
    }
  });

  V.register(98, "film stock grade per city", (ctx) => {
    const city = ctx.detail.city || qs("city") || "default";
    const grades = { default: "neutral", kl: "warm-teal", nyc: "cool-contrast", tokyo: "high-key", london: "desaturated" };
    const grade = grades[city] || grades.default;
    root.dataset.filmStock = grade;
    V.css("--film-grade", grade);
  });

  V.register(99, "nav wipe fade", () => {
    body.classList.add("nav-wipe-ready");
    body.dataset.navWipe = "1";
    window.setTimeout(() => delete body.dataset.navWipe, 400);
  });

  V.register(100, "Malay warm core", () => {
    const warm = qs("locale") === "ms" || qs("malay") === "1" || navigator.language?.startsWith?.("ms");
    if (warm) {
      root.dataset.malayWarm = "1";
      V.css("--face-warm-core", "#e8c4a0");
    }
  });

  V.register(101, "ABSOLUTE freeze", (ctx) => {
    ctx.st.frozen = true;
    ctx.st.idleAlphaDrift = 0;
    root.dataset.absoluteFreeze = "1";
    V.css("--face-motion-scale", "0");
  });

  V.register(102, "seasonal topology fetch hook", (ctx) => {
    const month = new Date().getMonth();
    const season = month < 3 ? "winter" : month < 6 ? "spring" : month < 9 ? "summer" : "autumn";
    root.dataset.season = season;
    if (ctx.detail.topology) root.dataset.seasonalTopology = ctx.detail.topology;
  });

  V.register(103, "minimal UI particles-only", () => {
    root.dataset.minimalUi = "particles-only";
    body.classList.add("particles-only");
    document.querySelectorAll(".prompt-bar, #chat-log, .status-bar").forEach((el) => {
      el.style.opacity = "0";
      el.style.pointerEvents = "none";
    });
  });

  V.register(105, "logo disintegration", () => {
    const logo = document.querySelector(".top-left-logo");
    if (!logo) return;
    logo.classList.add("disintegrate");
    window.setTimeout(() => logo.classList.remove("disintegrate"), 1200);
  });

  V.register(106, "noir R-only", () => {
    root.dataset.noir = "r-only";
    V.css("--face-color-mode", "r-only");
    body.classList.add("noir-mode");
  });

  V.register(107, "aurora hue cycle", (ctx) => {
    const hue = Number(ctx.detail.hue ?? 0) % 360;
    V.css("--aurora-hue", `${hue}`);
    root.dataset.auroraHue = String(hue | 0);
  });

  V.register(108, "print SVG export", () => {
    const cv = document.getElementById("face") || document.getElementById("mask");
    if (!cv?.toDataURL) return null;
    const data = cv.toDataURL("image/png");
    const svg = `<svg xmlns="http://www.w3.org/2000/svg" width="${cv.width}" height="${cv.height}"><image href="${data}" width="100%" height="100%"/></svg>`;
    const blob = new Blob([svg], { type: "image/svg+xml" });
    const a = document.createElement("a");
    a.href = URL.createObjectURL(blob);
    a.download = "master-face.svg";
    a.click();
    URL.revokeObjectURL(a.href);
    return svg;
  });

  /* 109–118 a11y */
  V.register(109, "reduced-motion constellation", (ctx) => {
    const rm = !!ctx.detail.reducedMotion;
    ctx.st.reducedMotion = rm;
    root.dataset.reducedMotion = rm ? "1" : "";
    V.css("--face-motion-scale", rm ? "0.2" : "1");
  });

  V.register(110, "contrast 2x luminance", (ctx) => {
    const on = !!ctx.detail.on;
    root.dataset.contrast2x = on ? "1" : "";
    root.dataset.highContrast = on ? "1" : "";
    V.css("--face-luminance-mul", on ? "2" : "1");
  });

  V.register(111, "aria-live mode announce", (ctx) => {
    const mode = String(ctx.detail.mode || ctx.type || "");
    if (!mode) return;
    let live = document.getElementById("face-mode-live");
    if (!live) {
      live = document.createElement("div");
      live.id = "face-mode-live";
      live.className = "sr-only";
      live.setAttribute("aria-live", "polite");
      live.setAttribute("aria-atomic", "true");
      body.appendChild(live);
    }
    if (live._last !== mode) {
      live._last = mode;
      live.textContent = `mode ${mode}`;
    }
  });

  V.register(112, "particle legend text", () => {
    let legend = document.getElementById("particle-legend");
    if (!legend) {
      legend = document.createElement("p");
      legend.id = "particle-legend";
      legend.className = "particle-legend sr-only";
      body.appendChild(legend);
    }
    legend.textContent = "Particle face: eyes attend, mouth speaks, terrain reflects mood.";
  });

  V.register(113, "tts-live viseme highlight", (ctx) => {
    const shape = ctx.detail.shape || ctx.detail.viseme || "rest";
    let el = document.getElementById("tts-viseme-live");
    if (!el) {
      el = document.createElement("span");
      el.id = "tts-viseme-live";
      el.className = "sr-only";
      el.setAttribute("aria-live", "off");
      body.appendChild(el);
    }
    el.textContent = `viseme ${shape}`;
    el.dataset.active = "1";
    window.setTimeout(() => delete el.dataset.active, 120);
  });

  V.register(114, "sound-on chip", (ctx) => {
    let chip = document.getElementById("sound-on-chip");
    if (!chip) {
      chip = document.createElement("button");
      chip.id = "sound-on-chip";
      chip.type = "button";
      chip.className = "sound-on-chip";
      chip.addEventListener("click", () => {
        window.MASTER_FACE?.ttsToggleMute?.();
        V.run(114, { type: "sound:toggle", detail: {} });
      });
      body.appendChild(chip);
    }
    const muted = window.MASTER_FACE?.tts?.muted;
    chip.textContent = muted ? "sound off" : "sound on";
    chip.setAttribute("aria-pressed", muted ? "false" : "true");
  });

  V.register(115, "color-blind shape motion", (ctx) => {
    body.classList.add("cb-shape-motion");
    root.dataset.colorBlindShapes = "1";
    ctx.st.shapeMotion = (ctx.st.shapeMotion || 0) + (ctx.st.reducedMotion ? 0.01 : 0.04);
    V.css("--shape-motion", ctx.st.shapeMotion.toFixed(3));
  });

  V.register(116, "font-scale HUD", (ctx) => {
    const scale = Math.max(0.8, Math.min(1.6, Number(ctx.detail.scale ?? 1)));
    V.css("--font-scale", String(scale));
    root.dataset.fontScale = scale.toFixed(2);
    try { localStorage.setItem("master:font-scale", String(scale)); } catch (err) { window.MASTER_LOG?.warn?.("face_vision_c:font_scale_store", err); }
  });

V.register(118, "degraded WebGL UI trigger", (ctx) => {
    const reason = ctx.detail.message || ctx.detail.reason || "Degraded text mode";
    root.dataset.degradedWebgl = "1";
    body.dataset.errorBoundary = "1";
    body.dataset.runtimeProfile = "text";
    let banner = document.getElementById("face-error-banner");
    if (!banner) {
      banner = document.createElement("div");
      banner.id = "face-error-banner";
      banner.className = "face-error-banner";
      body.appendChild(banner);
    }
    banner.textContent = reason;
  });

  /* wiring */
  (function wireVisionC() {
    V.run(92, { type: "init", detail: {} });
    V.run(96, { type: "init", detail: {} });
    V.run(97, { type: "init", detail: {} });
    V.run(100, { type: "init", detail: {} });
    V.run(112, { type: "init", detail: {} });
    V.run(114, { type: "init", detail: {} });
    V.run(117, { type: "init", detail: {} });

    if (qs("absolute") === "1") V.run(101, { type: "init", detail: {} });
    if (qs("minimal") === "1" || qs("particles") === "only") V.run(103, { type: "init", detail: {} });
    if (qs("noir") === "1") V.run(106, { type: "init", detail: {} });
    if (qs("cb") === "1") V.run(115, { type: "init", detail: {} });

    V.run(98, { type: "init", detail: { city: qs("city") } });

    const mq = window.matchMedia?.("(prefers-reduced-motion: reduce)");
    V.run(109, { type: "init", detail: { reducedMotion: !!mq?.matches } });
    mq?.addEventListener?.("change", () => {
      V.run(109, { type: "motion:change", detail: { reducedMotion: !!mq.matches } });
    });

    const st = V.state();
    if (st.highContrast || st.contrastMore || qs("contrast") === "2") {
      V.run(110, { type: "init", detail: { on: true } });
    }

    const fontInput = document.getElementById("font-scale");
    if (fontInput) {
      V.run(116, { type: "init", detail: { scale: fontInput.value } });
      fontInput.addEventListener("input", () => {
        V.run(116, { type: "font:input", detail: { scale: fontInput.value } });
      });
    }

    const cv = document.getElementById("face") || document.getElementById("mask");
    if (cv) {
      let holdTimer = null;
      cv.addEventListener("pointerdown", () => {
        holdTimer = window.setTimeout(() => V.run(81, { type: "tap:hold", detail: { accelerate: true } }), 420);
      }, { passive: true });
      const up = () => {
        window.clearTimeout(holdTimer);
        V.run(81, { type: "tap:release", detail: { accelerate: false } });
      };
      cv.addEventListener("pointerup", up, { passive: true });
      cv.addEventListener("pointercancel", up, { passive: true });

      if (qs("dev") === "1" || qs("pinch") === "1") {
        let pinch0 = null;
        cv.addEventListener("touchstart", (e) => {
          if (e.touches.length !== 2) return;
          const dx = e.touches[0].clientX - e.touches[1].clientX;
          const dy = e.touches[0].clientY - e.touches[1].clientY;
          pinch0 = Math.hypot(dx, dy);
        }, { passive: true });
        cv.addEventListener("touchmove", (e) => {
          if (e.touches.length !== 2 || !pinch0) return;
          const dx = e.touches[0].clientX - e.touches[1].clientX;
          const dy = e.touches[0].clientY - e.touches[1].clientY;
          const d = Math.hypot(dx, dy);
          const zoom = (V.state().mouthZoom || 1) * (d / pinch0);
          pinch0 = d;
          V.run(84, { type: "pinch", detail: { zoom } });
        }, { passive: true });
        cv.addEventListener("touchend", () => { pinch0 = null; }, { passive: true });
      }

      let lpTimer = null;
      cv.addEventListener("pointerdown", () => {
        lpTimer = window.setTimeout(() => V.run(85, { type: "felt:inspect", detail: {} }), 1400);
      }, { passive: true });
      const lpUp = () => window.clearTimeout(lpTimer);
      cv.addEventListener("pointerup", lpUp, { passive: true });
      cv.addEventListener("pointercancel", lpUp, { passive: true });

      let lastTap = 0;
      cv.addEventListener("pointerup", () => {
        const now = performance.now();
        if (now - lastTap < 320) V.run(91, { type: "double-tap", detail: { active: true } });
        lastTap = now;
      }, { passive: true });
    }

    const bindGyro = () => {
      window.addEventListener("deviceorientation", (e) => {
        V.run(82, { type: "gyro", detail: { beta: e.beta, gamma: e.gamma } });
      }, { passive: true });
      root.dataset.gyroGravity = "bound";
    };
    if (typeof DeviceOrientationEvent !== "undefined"
        && typeof DeviceOrientationEvent.requestPermission === "function") {
      window.addEventListener("primer:ready", async () => {
        try {
          if ((await DeviceOrientationEvent.requestPermission()) === "granted") bindGyro();
        } catch (err) { window.MASTER_LOG?.warn?.("face_vision_c:gyro_permission", err); }
      }, { once: true });
    } else if (window.DeviceOrientationEvent) {
      bindGyro();
    }

    const log = document.getElementById("chat-log");
    log?.addEventListener("scroll", () => {
      V.run(83, { type: "chat:scroll", detail: { scrollTop: log.scrollTop } });
    }, { passive: true });

    const zin = document.getElementById("zin") || document.getElementById("input");
    zin?.addEventListener("focus", () => V.run(88, { type: "zin:focus", detail: { focused: true } }));
    zin?.addEventListener("blur", () => V.run(88, { type: "zin:blur", detail: { focused: false } }));

    window.addEventListener("tts:viseme", (ev) => {
      V.run(89, { type: "tts:viseme", detail: ev.detail || {} });
      V.run(113, { type: "tts:viseme", detail: ev.detail || {} });
    });

    if ("getGamepads" in navigator) {
      const poll = () => {
        const pad = (navigator.getGamepads() || []).find((p) => p?.buttons?.[0]?.pressed);
        if (pad && !window._primerFired) V.run(90, { type: "gamepad", detail: {} });
        requestAnimationFrame(poll);
      };
      requestAnimationFrame(poll);
    }

    window.addEventListener("keydown", (e) => {
      if (e.code === "Space" && !e.repeat
          && !document.activeElement?.matches?.("input,textarea,[contenteditable]")
          && (window._primerFired || window.MASTER_FACE?.primerFired)) {
        e.preventDefault();
        V.run(86, { type: "space", detail: {} });
      }
    });

    let konamiPos = 0;
    window.addEventListener("keydown", (e) => {
      const key = e.key.length === 1 ? e.key.toLowerCase() : e.key;
      if (key === KONAMI[konamiPos]) {
        konamiPos++;
        if (konamiPos >= KONAMI.length) {
          konamiPos = 0;
          V.run(95, { type: "konami", detail: {} });
        }
      } else {
        konamiPos = key === KONAMI[0] ? 1 : 0;
      }
    });

    window.addEventListener("master:visual", (ev) => {
      const d = ev.detail || {};
      const name = String(d.name || d.mode || "");
      V.run(104, { type: name, detail: d });
      V.run(111, { type: name, detail: { mode: d.mode || name } });
      if (/nav|palette|route/i.test(name)) V.run(99, { type: name, detail: d });
      if (/photo:ready|photo:capture/i.test(name)) V.run(87, { type: name, detail: d });
      if (/error|veto|violation/i.test(name)) V.run(105, { type: name, detail: d });
    });

    document.getElementById("describe-face-btn")?.addEventListener("click", () => {
      V.run(94, { type: "describe", detail: {} });
    });

    fetch(`/canvas/topology?season=${root.dataset.season || "summer"}`, { credentials: "same-origin" })
      .then((r) => (r.ok ? r.json() : null))
      .then((json) => {
        if (json) V.run(102, { type: "topology:seasonal", detail: { topology: json.id || json.topology } });
      })
      .catch(() => V.run(102, { type: "topology:seasonal", detail: {} }));

    let hue = 0;
    window.setInterval(() => {
      hue = (hue + 0.15) % 360;
      V.run(107, { type: "aurora", detail: { hue } });
      if (root.dataset.colorBlindShapes === "1") V.run(115, { type: "shape:tick", detail: {} });
    }, 50);

    window.addEventListener("master:face-error", (ev) => {
      V.run(118, { type: "face:error", detail: ev.detail || {} });
    });
    window.addEventListener("webglcontextlost", () => {
      V.run(118, { type: "webgl:lost", detail: { reason: "WebGL context lost — text mode" } });
    }, { passive: true });

    window.MASTER_FACE_VISION.shareCard = (p) => V.run(93, { type: "share", detail: p || {} });
    window.MASTER_FACE_VISION.exportSvg = () => V.run(108, { type: "export:svg", detail: {} });
    window.MASTER_FACE_VISION.describeTts = () => V.run(94, { type: "describe:api", detail: {} });
  })();
})();
