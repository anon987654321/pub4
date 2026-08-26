(() => {
  const MAX = 2000;
  const de = document.documentElement;
  const vw = de.clientWidth, vh = de.clientHeight;

  const INTERACTIVE_SEL = [
    'a[href]', 'button', 'input:not([type=hidden])', 'select', 'textarea',
    'summary', '[role=button]', '[role=link]', '[role=tab]', '[role=switch]',
    '[role=menuitem]', '[role=checkbox]', '[onclick]'
  ].join(',');

  // Anything CSS can express, resolved to sRGB by the browser itself.
  //
  // This used to match rgba?() only. Chrome keeps oklch() in computed
  // style rather than converting it, so every oklch colour parsed as null
  // and the caller substituted opaque black — which is how the gate came
  // to report brgen/takeaway as "#000000 on #1a1a1a = 1.21" for text that
  // is actually a legible red. _vertical_takeaway.scss defines its accents
  // in oklch, so every takeaway contrast finding was fictional, and
  // fictional failures are worse than none: they train you to skim past
  // the real ones sitting in the same list.
  const _swatch = document.createElement('canvas');
  _swatch.width = _swatch.height = 1;
  const _swatchCtx = _swatch.getContext('2d', { willReadFrequently: true });
  const parseRgb = (s) => {
    const str = String(s).trim();
    if (!str || str === 'transparent') return null;
    const m = str.match(/rgba?\\(([^)]+)\\)/);
    if (m) {
      const p = m[1].split(/[,\\s\\/]+/).filter(Boolean).map(Number);
      if (p.length >= 3 && !p.some(Number.isNaN)) {
        return { r: p[0], g: p[1], b: p[2], a: p.length > 3 ? p[3] : 1 };
      }
    }
    if (!_swatchCtx) return null;
    try {
      // fillStyle silently ignores a value it cannot parse, so paint over
      // a known sentinel and treat "unchanged" as unsupported rather than
      // reading back the sentinel as if it were the real colour.
      _swatchCtx.clearRect(0, 0, 1, 1);
      _swatchCtx.fillStyle = '#010203';
      _swatchCtx.fillStyle = str;
      if (_swatchCtx.fillStyle === '#010203' && !/^#010203$/i.test(str)) return null;
      _swatchCtx.fillRect(0, 0, 1, 1);
      const d = _swatchCtx.getImageData(0, 0, 1, 1).data;
      return { r: d[0], g: d[1], b: d[2], a: d[3] / 255 };
    } catch (_) {
      return null;
    }
  };
  const over = (fg, bg) => ({
    r: fg.r * fg.a + bg.r * (1 - fg.a),
    g: fg.g * fg.a + bg.g * (1 - fg.a),
    b: fg.b * fg.a + bg.b * (1 - fg.a),
    a: 1
  });
  const hex = (c) => c ? '#' + [c.r, c.g, c.b].map(v =>
    Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, '0')).join('') : null;

  // Composite every ancestor background down to an opaque colour, the
  // way the compositor does. var()/oklch/color-mix all arrive here
  // already resolved, which is exactly what the static hex parser in
  // design_metrics.rb has to give up on.
  const effectiveBg = (el) => {
    let node = el, acc = null;
    while (node?.nodeType === 1) {
      const c = parseRgb(getComputedStyle(node).backgroundColor);
      if (c?.a > 0) acc = acc ? over(acc, c) : c;
      if (acc?.a >= 0.999) return acc;
      node = node.parentElement;
    }
    const page = parseRgb(getComputedStyle(de).backgroundColor);
    const base = (page?.a >= 0.999) ? page : { r: 255, g: 255, b: 255, a: 1 };
    return acc ? over(acc, base) : base;
  };

  // Runtime state classes must never reach a selector key. body carries
  // stimulus-reflex-connected / -disconnected depending on whether the
  // websocket has attached yet, and because keys are ancestor paths that
  // one class flipped the key of every element on the page — which reads
  // as "everything was removed and re-added" on the next comparison.
  //
  // network-/battery-/power- are the same defect one step worse: those are
  // toggled on <html> from the *measured* connection, battery and CPU
  // (network_aware_controller, battery_aware_controller), so they key on
  // the machine and the moment the probe ran rather than on anything in
  // the tree. Missing them put html.network-slow into the ancestor path of
  // every element on every page — 78 of 436 drift lines in one run were
  // the same element reported as both removed and added. -hidden was
  // already covered by the suffix group, which is why page-hidden and
  // chrome-hidden never showed up here.
  // next/prev/duplicate are carousel position, which moves on its own:
  // Swiper writes swiper-slide-next onto whichever slide is currently
  // queued, so one autoplay tick between two runs of the snapshot gate
  // renamed a slide that nothing in the tree had touched. -active was
  // already covered by this group, which is why only its siblings showed.
  const VOLATILE_CLASS = /^(ng-|js-|is-|has-|turbo-|network-|battery-|power-)|(-|^)(connected|disconnected|loading|loaded|ready|active|open|closed|revealed|hidden|visible|scrolled|pending|selected|next|prev|duplicate)$/;
  const classSig = (el) => {
    const cls = (el.getAttribute('class') || '').trim().split(/\\s+/)
      .filter(c => c && !VOLATILE_CLASS.test(c)).slice(0, 3);
    return cls.length ? '.' + cls.join('.') : '';
  };
  const selFor = (el) => {
    if (el.id) return '#' + el.id;
    const parts = [];
    let node = el, depth = 0;
    while (node?.nodeType === 1 && depth < 4) {
      if (node.id) { parts.unshift('#' + node.id); break; }
      parts.unshift(node.tagName.toLowerCase() + classSig(node));
      node = node.parentElement; depth++;
    }
    return parts.join('>');
  };

  const seen = Object.create(null);
  const keyFor = (sel) => {
    seen[sel] = (seen[sel] || 0) + 1;
    return seen[sel] === 1 ? sel : sel + '[' + seen[sel] + ']';
  };

  const out = [];
  const colors = Object.create(null);
  const overflow = [];
  const all = document.querySelectorAll('body *');

  for (let i = 0; i < all.length && out.length < MAX; i++) {
    const el = all[i];
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') continue;
    const r = el.getBoundingClientRect();
    const area = r.width * r.height;
    const opacity = parseFloat(cs.opacity);

    const interactive = el.matches(INTERACTIVE_SEL) ||
      (el.hasAttribute('tabindex') && el.getAttribute('tabindex') !== '-1');
    const ownText = Array.from(el.childNodes)
      .filter(n => n.nodeType === 3).map(n => n.textContent.trim()).join(' ').trim();
    const landmark = /^(header|nav|main|footer|aside|section|form|h1|h2|h3)$/.test(el.tagName.toLowerCase());

    // WCAG 2.5.8 exempts links flowing inline inside a sentence — they
    // are not touch targets and counting them buries the real ones.
    const parentText = el.parentElement
      ? Array.from(el.parentElement.childNodes)
          .filter(n => n.nodeType === 3).map(n => n.textContent.trim()).join('').trim()
      : '';
    const inlineInText = cs.display.startsWith('inline') && !cs.display.startsWith('inline-') &&
      parentText.length > 0;

    if (!interactive && !ownText && !landmark) continue;
    if (area <= 0 || opacity === 0) {
      if (interactive) out.push({
        key: keyFor(selFor(el)), tag: el.tagName.toLowerCase(), interactive: true,
        visible: false, rect: { x: 0, y: 0, w: 0, h: 0 }, text: ownText.slice(0, 60)
      });
      continue;
    }

    // No black default. Substituting a colour we could not read invents a
    // contrast finding out of nothing; leaving fg null makes the caller
    // skip the check, which is the honest answer for a colour the probe
    // genuinely cannot resolve.
    const fg = parseRgb(cs.color);
    const bg = effectiveBg(el);
    const fgOpaque = fg ? (fg.a >= 0.999 ? fg : over(fg, bg)) : null;

    if (ownText && fgOpaque) {
      const ck = hex(fgOpaque);
      if (ck) colors[ck] = (colors[ck] || 0) + 1;
    }

    // Hit test the centre: if something else owns that pixel the control
    // is unclickable no matter how big its box is.
    let hit = 'none';
    const cx = r.left + r.width / 2, cy = r.top + r.height / 2;
    if (interactive && cx >= 0 && cy >= 0 && cx <= vw && cy <= vh) {
      const top = document.elementFromPoint(cx, cy);
      if (!top) hit = 'none';
      else if (top === el) hit = 'self';
      else if (el.contains(top)) hit = 'descendant';
      else if (top.contains(el)) hit = 'ancestor';
      else {
        // Content resting under fixed/sticky chrome at scroll 0 is not
        // unclickable — scrolling moves it out. Only a blocker in normal
        // flow is a real dead zone.
        //
        // The anchor must be one the blocker has and the element does
        // NOT: these apps wrap everything in a fixed .app-shell, so
        // "does the element have a fixed ancestor" is true for the whole
        // page and would classify every real occlusion as chrome.
        const anchorOf = (node) => {
          for (let n = node; n?.nodeType === 1; n = n.parentElement) {
            const p = getComputedStyle(n).position;
            if (p === 'fixed' || p === 'sticky') return n;
          }
          return null;
        };
        const blockerAnchor = anchorOf(top);
        hit = (blockerAnchor && !blockerAnchor.contains(el))
          ? 'under_chrome:' + selFor(top).slice(0, 60)
          : 'blocked:' + selFor(top).slice(0, 80);
      }
    } else if (interactive) {
      hit = 'offscreen';
    }

    // Only right-side spill counts. An element parked at left:-300 is the
    // standard closed-drawer idiom, not a layout break, and the document
    // scrollWidth below is the authoritative signal either way.
    if (r.right > vw + 1 && r.width > 4) {
      overflow.push({ sel: selFor(el), right: Math.round(r.right), width: Math.round(r.width) });
    }

    out.push({
      key: keyFor(selFor(el)),
      tag: el.tagName.toLowerCase(),
      role: el.getAttribute('role') || null,
      aria: el.getAttribute('aria-label') || null,
      text: ownText.slice(0, 60),
      rect: { x: Math.round(r.left), y: Math.round(r.top), w: Math.round(r.width), h: Math.round(r.height) },
      // The rounded rect above is what every existing check reads, and
      // rounding is exactly what hides a subpixel defect: an element at
      // x=12.5 reports 13 and looks aligned. Two decimals is past what a
      // device pixel ratio of 3 can resolve, so anything left here is a
      // real fractional position and not float noise.
      frect: {
        x: Math.round(r.left * 100) / 100,
        y: Math.round(r.top * 100) / 100,
        w: Math.round(r.width * 100) / 100,
        h: Math.round(r.height * 100) / 100
      },
      color: hex(fgOpaque),
      bg: hex(bg),
      font_size: Math.round(parseFloat(cs.fontSize) * 10) / 10,
      font_weight: cs.fontWeight,
      line_height: cs.lineHeight === 'normal' ? null : Math.round(parseFloat(cs.lineHeight) * 10) / 10,
      position: cs.position,
      display: cs.display,
      text_align: cs.textAlign,
      // Needed to tell a text field from a submit button: both are
      // <input>, only one takes a caret, and only one triggers the iOS
      // focus zoom. The selector alone cannot say which.
      input_type: el.tagName === 'INPUT' ? (el.getAttribute('type') || 'text').toLowerCase() : null,
      z: cs.zIndex === 'auto' ? null : cs.zIndex,
      interactive: interactive,
      inline_in_text: inlineInText,
      visible: true,
      // Laid out but parked outside the viewport — a closed drawer or a
      // carousel slide. Still a real element with real styles; just not
      // on the first screen, which callers should say out loud.
      onscreen: r.right > 0 && r.left < vw && r.bottom > 0,
      hit: hit
    });
  }

  // Rendered vertical gaps between consecutive block siblings — the 8px
  // rhythm as laid out, not as declared in a stylesheet that may cascade
  // away or be overridden at this breakpoint.
  const gaps = [];
  const containers = document.querySelectorAll('main, main *, [role=main], .feed, .deal-grid');
  for (let i = 0; i < containers.length && gaps.length < 400; i++) {
    const kids = Array.from(containers[i].children).filter(k => {
      const cs = getComputedStyle(k);
      if (cs.display === 'none' || cs.position === 'absolute' || cs.position === 'fixed') return false;
      if (cs.display.startsWith('inline') && !cs.display.startsWith('inline-')) return false;
      const kr = k.getBoundingClientRect();
      // Major stacked blocks only. Hairlines and inline runs produce
      // sub-4px "gaps" that are borders and leading, not rhythm.
      return kr.height > 24 && kr.width > vw * 0.5;
    });
    for (let j = 0; j + 1 < kids.length; j++) {
      const a = kids[j].getBoundingClientRect(), b = kids[j + 1].getBoundingClientRect();
      const g = Math.round(b.top - a.bottom);
      if (g >= 4 && g <= 128) gaps.push({ gap: g, sel: selFor(kids[j + 1]) });
    }
  }

  // Peer choices per navigation group, for Hick's law and chunking. A
  // count is only meaningful among *siblings* offered at the same moment,
  // so this counts direct interactive children of each menu-ish container
  // rather than every link inside it.
  const groups = [];
  document.querySelectorAll('nav, [role=navigation], [role=menu], [role=tablist], .tab-bar')
    .forEach(container => {
      const cs = getComputedStyle(container);
      if (cs.display === 'none' || cs.visibility === 'hidden') return;
      const r = container.getBoundingClientRect();
      if (r.width < 1 || r.height < 1) return;
      const choices = Array.from(container.querySelectorAll('a[href], button, [role=tab], [role=menuitem]'))
        .filter(k => {
          const kcs = getComputedStyle(k);
          if (kcs.display === 'none' || kcs.visibility === 'hidden') return false;
          const kr = k.getBoundingClientRect();
          return kr.width > 0 && kr.height > 0;
        });
      // Chunking is the other prescribed remedy for Hick, alongside a
      // scrolling rail: a bar that splits its entries into labelled
      // role=group sections asks the reader to choose within a group, not
      // among every link at once. Reported so the gate can judge the
      // largest chunk rather than the container total — brgen groups its
      // eleven verticals as 4 and 7, and counting 11 credited neither.
      const chunks = [...container.querySelectorAll('[role=group]')]
        .map(g => g.querySelectorAll('a[href], button, [role=tab], [role=menuitem]').length)
        .filter(n => n > 0);
      groups.push({ sel: selFor(container), count: choices.length, chunks,
                    scrollable: container.scrollWidth > container.clientWidth + 4 });
    });

  // Gestalt proximity, measured correctly: the space *between an element's
  // own children* against the space between that element and the next one.
  // That is what the eye compares. Summing the element's top and bottom
  // padding — the first version of this — asks a different question and
  // answers it wrongly: a hero with 40px above and below its content and
  // 48px to the next section reported "80 > 48" and was flagged, when its
  // children sit 32px apart inside a 48px separation, which is right.
  const proximity = [];
  const measuredGap = (a, b) => Math.round(b.getBoundingClientRect().top - a.getBoundingClientRect().bottom);
  const laidOut = el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.position === 'absolute' || cs.position === 'fixed') return false;
    return el.getBoundingClientRect().height > 4;
  };
  for (let i = 0; i < containers.length && proximity.length < 200; i++) {
    const kids = Array.from(containers[i].children).filter(k => {
      const kr = k.getBoundingClientRect();
      return laidOut(k) && kr.height > 24 && kr.width > vw * 0.5;
    });
    for (let j = 0; j + 1 < kids.length; j++) {
      const a = kids[j], b = kids[j + 1];
      const external = measuredGap(a, b);
      if (external < 0 || external > 128) continue;
      // The widest gap between a's own consecutive children is its
      // internal spacing — the distance the eye reads as "same group".
      const inner = Array.from(a.children).filter(laidOut);
      let internal = 0;
      for (let k = 0; k + 1 < inner.length; k++) {
        const g = measuredGap(inner[k], inner[k + 1]);
        if (g > internal && g <= 128) internal = g;
      }
      if (internal > 0) proximity.push({ sel: selFor(a), pad: internal, gap: external });
    }
  }

  return {
    vw: vw, vh: vh,
    title: document.title,
    groups: groups,
    proximity: proximity,
    scroll_width: de.scrollWidth,
    client_width: de.clientWidth,
    h1_count: document.querySelectorAll('h1').length,
    landmarks: {
      main: !!document.querySelector('main, [role=main], #main-content'),
      nav: !!document.querySelector('nav, [role=navigation]'),
      skip: !!document.querySelector('a[href="#main-content"], .skip-link')
    },
    elements: out,
    colors: colors,
    overflow: overflow,
    gaps: gaps
  };
})()
