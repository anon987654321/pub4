(() => {
  const de = document.documentElement;
  const vw = de.clientWidth, vh = de.clientHeight;

  const selFor = (el) => {
    if (el.id) return `#${el.id}`;
    const parts = [];
    let node = el, depth = 0;
    while (node?.nodeType === 1 && depth < 4) {
      if (node.id) { parts.unshift(`#${node.id}`); break; }
      const cls = (el === node ? (node.getAttribute('class') || '') : (node.getAttribute('class') || ''))
        .trim().split(/\s+/).filter(Boolean).slice(0, 2);
      parts.unshift(node.tagName.toLowerCase() + (cls.length ? '.' + cls.join('.') : ''));
      node = node.parentElement; depth++;
    }
    return parts.join('>');
  };

  const firstLineChars = (el) => {
    const textNode = Array.from(el.childNodes).find(n => n.nodeType === 3 && n.textContent.trim());
    if (!textNode) return null;
    const raw = textNode.textContent.replace(/\s+/g, ' ');
    const start = raw.search(/\S/);
    if (start < 0) return null;
    const range = document.createRange();
    try { range.setStart(textNode, start); range.setEnd(textNode, start + 1); }
    catch (_) { return null; }
    const y0 = range.getBoundingClientRect().top;
    let lo = start + 1, hi = Math.min(raw.length, start + 120), best = lo;
    while (lo <= hi) {
      const mid = (lo + hi) >> 1;
      try { range.setEnd(textNode, mid); } catch (_) { break; }
      const top = range.getBoundingClientRect().top;
      if (Math.abs(top - y0) < 2) { best = mid; lo = mid + 1; }
      else hi = mid - 1;
    }
    const slice = raw.slice(start, best).trim();
    return slice.length >= 20 ? [...slice].length : null;
  };

  const prose = [];
  document.querySelectorAll('p, .feed-card-text, .legal-prose p, .legal-prose li, article p').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.visibility === 'hidden') return;
    const ch = firstLineChars(el);
    if (!ch) return;
    prose.push({ sel: selFor(el), ch: ch, size: Math.round(parseFloat(cs.fontSize) * 10) / 10 });
  });

  const sizes = Object.create(null);
  document.querySelectorAll('body *').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return;
    const own = Array.from(el.childNodes).some(n => n.nodeType === 3 && n.textContent.trim());
    if (!own) return;
    const px = Math.round(parseFloat(cs.fontSize) * 10) / 10;
    if (px > 0) sizes[px] = (sizes[px] || 0) + 1;
  });

  const QUANTITY = '[data-money], .deal-price, .listing-price, .listing-buy-bar-amount, .item-subtotal, .feed-action-count';
  const tabular = [];
  document.querySelectorAll(QUANTITY).forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return;
    tabular.push({
      sel: selFor(el),
      numeric: String(cs.fontVariantNumeric || ''),
      text: (el.textContent || '').trim().slice(0, 40)
    });
  });

  const hslHue = (r, g, b) => {
    r /= 255; g /= 255; b /= 255;
    const max = Math.max(r, g, b), min = Math.min(r, g, b);
    const d = max - min;
    const l = (max + min) / 2;
    const s = d === 0 ? 0 : d / (1 - Math.abs(2 * l - 1));
    if (s < 0.18 || l < 0.12 || l > 0.92) return null;
    let h = 0;
    if (d !== 0) {
      if (max === r) h = ((g - b) / d) % 6;
      else if (max === g) h = (b - r) / d + 2;
      else h = (r - g) / d + 4;
      h *= 60;
      if (h < 0) h += 360;
    }
    return Math.round(h);
  };
  const parseRgb = (s) => {
    const m = String(s).match(/rgba?\(([^)]+)\)/);
    if (!m) return null;
    const p = m[1].split(/[,\s\/]+/).filter(Boolean).map(Number);
    return p.length >= 3 ? p : null;
  };
  const accents = Object.create(null);
  document.querySelectorAll('body *').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return;
    const rgb = parseRgb(cs.color);
    if (!rgb) return;
    const h = hslHue(rgb[0], rgb[1], rgb[2]);
    if (h == null) return;
    const bucket = Math.round(h / 15) * 15;
    accents[bucket] = (accents[bucket] || 0) + 1;
  });

  const pageBg = parseRgb(getComputedStyle(de).backgroundColor) || [255, 255, 255];
  let empty = 0, samples = 0;
  const cols = 16, rows = 10;
  for (let y = 0; y < rows; y++) {
    for (let x = 0; x < cols; x++) {
      const px = (x + 0.5) * vw / cols;
      const py = (y + 0.5) * vh / rows;
      samples++;
      const top = document.elementFromPoint(px, py);
      if (!top || top === de || top === document.body) { empty++; continue; }
      const tbg = parseRgb(getComputedStyle(top).backgroundColor);
      if (!tbg || tbg.length < 3) { empty++; continue; }
      const d = Math.abs(tbg[0] - pageBg[0]) + Math.abs(tbg[1] - pageBg[1]) + Math.abs(tbg[2] - pageBg[2]);
      if (d < 30) empty++;
    }
  }

  const baselines = [];
  document.querySelectorAll('p, .feed-card-text, li, h1, h2, h3').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none') return;
    const r = el.getBoundingClientRect();
    if (r.height < 8 || r.width < 40) return;
    const lh = cs.lineHeight === 'normal' ? parseFloat(cs.fontSize) * 1.2 : parseFloat(cs.lineHeight);
    if (!lh) return;
    baselines.push({ sel: selFor(el), y: Math.round((r.top + lh * 0.8) * 10) / 10, lh: Math.round(lh * 10) / 10 });
  });

  const hanging = [];
  document.querySelectorAll('li').forEach(el => {
    const cs = getComputedStyle(el);
    if (cs.display === 'none' || cs.listStyleType === 'none') return;
    const textNode = Array.from(el.childNodes).find(n => n.nodeType === 3 && n.textContent.trim() || n.nodeType === 1);
    if (!textNode) return;
    const range = document.createRange();
    try {
      if (textNode.nodeType === 3) range.setStart(textNode, 0);
      else range.selectNodeContents(textNode);
      range.collapse(true);
    } catch (_) { return; }
    const tr = range.getBoundingClientRect();
    const box = el.getBoundingClientRect();
    if (tr.width === 0 && tr.height === 0) return;
    hanging.push({ sel: selFor(el), marker_x: Math.round(box.left * 10) / 10, text_x: Math.round(tr.left * 10) / 10 });
  });

  const main = document.querySelector('main, [role=main], #main-content');
  const aside = document.querySelector('aside, [role=complementary]');
  let split = null;
  if (main && aside) {
    const mr = main.getBoundingClientRect(), ar = aside.getBoundingClientRect();
    if (mr.width > 80 && ar.width > 80 && mr.height > 80 && ar.height > 80) {
      const total = mr.width + ar.width;
      split = { main: Math.round(mr.width), aside: Math.round(ar.width), ratio: Math.round((mr.width / total) * 1000) / 1000 };
    }
  }

  return {
    prose: prose.slice(0, 40),
    type_sizes: sizes,
    tabular: tabular.slice(0, 40),
    accent_hues: accents,
    empty_ratio: samples ? Math.round((empty / samples) * 1000) / 1000 : null,
    baselines: baselines.slice(0, 80),
    hanging: hanging.slice(0, 30),
    split: split
  };
})()
