/*
 * Bevegelseslag — statisk snitt av motion.tsx, uten avhengigheter.
 * "fully immersive, still honest": innganger, ordmasker, parallaks, tellere,
 * magnetiske knapper og markør. Alt avslår seg selv ved prefers-reduced-motion,
 * og alt er progressivt: uten JS vises siden flat og fullstendig.
 */
(function () {
  "use strict";

  var reduced = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var finePointer = window.matchMedia("(pointer: fine)").matches;
  if (reduced) return; // ingen bevegelse — CSS fallback viser alt

  var EASE = function (t) {
    // tilnærming av cubic-bezier(0.2, 0.6, 0.2, 1)
    return 1 - Math.pow(1 - t, 3);
  };

  /* — Innganger og ordmasker: én observer, én klasse — */
  var revealEls = [].slice.call(document.querySelectorAll("[data-reveal]"));
  var wordEls = [].slice.call(document.querySelectorAll(".wr"));

  [].slice.call(document.querySelectorAll("[data-reveal][data-reveal-delay]")).forEach(function (el) {
    el.style.setProperty("--reveal-delay", el.getAttribute("data-reveal-delay") + "s");
  });

  if ("IntersectionObserver" in window) {
    var io = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          entry.target.classList.add("is-in");
          io.unobserve(entry.target);
        });
      },
      { once: true, rootMargin: "0px 0px -8% 0px" }
    );
    revealEls.forEach(function (el) { io.observe(el); });
    wordEls.forEach(function (el) { io.observe(el); });
  } else {
    revealEls.concat(wordEls).forEach(function (el) { el.classList.add("is-in"); });
  }

  /* — Parallaks: bildet puster i sin ramme — */
  var frames = [].slice.call(document.querySelectorAll("[data-parallax]")).map(function (frame) {
    return {
      frame: frame,
      inner: frame.querySelector(".pl-inner"),
      amount: parseFloat(frame.getAttribute("data-amount")) || 10,
      progress: 0,
    };
  });

  function parallax() {
    var vh = window.innerHeight;
    frames.forEach(function (f) {
      var rect = f.frame.getBoundingClientRect();
      if (rect.bottom < 0 || rect.top > vh) return;
      // 0 når rammen treffer bunnen av vinduet, 1 når den forlater toppen
      f.progress = (vh - rect.top) / (vh + rect.height);
      var y = (f.progress - 0.5) * 2 * f.amount;
      f.inner.style.transform = "translateY(" + y.toFixed(2) + "%)";
    });
  }

  /* — Tellere: tallet som vokser når det ses — */
  var counters = [].slice.call(document.querySelectorAll("[data-counter]")).map(function (el) {
    return { el: el, to: parseInt(el.getAttribute("data-to"), 10), done: false };
  });

  function runCounter(c) {
    if (c.done) return;
    c.done = true;
    var start = null;
    var dur = 1600;
    function tick(now) {
      if (start === null) start = now;
      var t = Math.min((now - start) / dur, 1);
      c.el.textContent = String(Math.round(EASE(t) * c.to));
      if (t < 1) requestAnimationFrame(tick);
    }
    requestAnimationFrame(tick);
  }

  if ("IntersectionObserver" in window) {
    var cio = new IntersectionObserver(
      function (entries) {
        entries.forEach(function (entry) {
          if (!entry.isIntersecting) return;
          counters.forEach(function (c) {
            if (c.el === entry.target) runCounter(c);
          });
          cio.unobserve(entry.target);
        });
      },
      { once: true, rootMargin: "0px 0px -10% 0px" }
    );
    counters.forEach(function (c) { cio.observe(c.el); });
  }

  /* — Markør: liten prikk med myk hale — */
  var dot = document.querySelector(".cur-dot");
  var ring = document.querySelector(".cur-ring");

  if (dot && ring && finePointer) {
    var mx = -100, my = -100, rx = -100, ry = -100, cursorRaf = 0;
    document.addEventListener(
      "mousemove",
      function (e) {
        mx = e.clientX;
        my = e.clientY;
        var hot = !!(e.target && e.target.closest && e.target.closest("a, button, [data-cursor]"));
        dot.classList.toggle("cur-hot", hot);
        ring.classList.toggle("cur-hot", hot);
      },
      { passive: true }
    );
    (function loopCursor() {
      rx += (mx - rx) * 0.16;
      ry += (my - ry) * 0.16;
      dot.style.transform = "translate(" + mx + "px, " + my + "px)";
      ring.style.transform = "translate(" + rx + "px, " + ry + "px)";
      cursorRaf = requestAnimationFrame(loopCursor);
    })();
  }

  /* — Magnetiske knapper: følger hånden en stund, finner hjem — */
  if (finePointer) {
    [].slice.call(document.querySelectorAll("[data-magnetic]")).forEach(function (el) {
      var tx = 0, ty = 0, cx = 0, cy = 0, raf = 0, live = false;
      function loop() {
        cx += (tx - cx) * 0.18;
        cy += (ty - cy) * 0.18;
        el.style.transform = "translate(" + cx.toFixed(2) + "px, " + cy.toFixed(2) + "px)";
        if (Math.abs(tx - cx) + Math.abs(ty - cy) > 0.1) {
          raf = requestAnimationFrame(loop);
        } else {
          live = false;
        }
      }
      function kick() {
        if (!live) {
          live = true;
          raf = requestAnimationFrame(loop);
        }
      }
      el.addEventListener(
        "mousemove",
        function (e) {
          var r = el.getBoundingClientRect();
          tx = (e.clientX - (r.left + r.width / 2)) * 0.28;
          ty = (e.clientY - (r.top + r.height / 2)) * 0.28;
          kick();
        },
        { passive: true }
      );
      el.addEventListener("mouseleave", function () {
        tx = 0;
        ty = 0;
        kick();
      });
    });
  }

  /* — Én rAF-lytt for parallaksen — */
  var ticking = false;
  function onScroll() {
    if (ticking) return;
    ticking = true;
    requestAnimationFrame(function () {
      parallax();
      ticking = false;
    });
  }
  window.addEventListener("scroll", onScroll, { passive: true });
  window.addEventListener("resize", onScroll, { passive: true });
  parallax();
})();
