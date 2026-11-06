// The measurements the design-book Laws read (MASTER/law/rendered.rb), installed once per page
// as window.__designLaws. Each phase returns plain data; Deploy::RenderedDesign::Capture calls
// them at 390, 360 and 320 wide before the desktop, and the Laws judge the snapshot in Ruby.
(() => {
  const MAX = 1500;
  const de = document.documentElement;
  const swatch = document.createElement('canvas').getContext('2d', { willReadFrequently: true });
  const px = (value) => parseFloat(value) || 0;

  // Any CSS colour as [r, g, b, a], read back through a 1px canvas so oklch() and color() resolve.
  const paint = (value) => {
    const text = String(value || '').trim();
    if (!text || text === 'transparent') return [0, 0, 0, 0];
    swatch.clearRect(0, 0, 1, 1);
    swatch.fillStyle = '#010203';
    swatch.fillStyle = text;
    swatch.fillRect(0, 0, 1, 1);
    const data = swatch.getImageData(0, 0, 1, 1).data;
    return [data[0], data[1], data[2], data[3] / 255];
  };

  const shown = (el, cs) => {
    if (cs.display === 'none' || cs.visibility === 'hidden' || Number(cs.opacity) === 0) return false;
    const box = el.getBoundingClientRect();
    return box.width > 0 && box.height > 0;
  };

  const ground = (el) => {
    for (let node = el; node?.nodeType === 1; node = node.parentElement) {
      const bg = paint(getComputedStyle(node).backgroundColor);
      if (bg[3] > 0.5) return bg;
    }
    return [255, 255, 255, 1];
  };

  const keyOf = (el) => {
    const cls = String(el.getAttribute('class') || '').split(/\s+/).filter(Boolean).slice(0, 2);
    const id = el.id ? `#${el.id}` : '';
    return el.tagName.toLowerCase() + id + (cls.length ? `.${cls.join('.')}` : '');
  };

  const textNodes = (el) => Array.from(el.childNodes).filter((node) => node.nodeType === 3 && node.textContent.trim());
  const ownText = (el) => textNodes(el).map((node) => node.textContent).join(' ').replace(/\s+/g, ' ').trim();

  const distinctTops = (rects) => {
    const tops = [];
    Array.from(rects).forEach((rect) => {
      if (rect.width > 0 && !tops.some((top) => Math.abs(top - rect.top) <= 2)) tops.push(rect.top);
    });
    return tops.length;
  };

  const lineTops = (el) => textNodes(el).reduce((sum, node) => {
    const range = document.createRange();
    range.selectNodeContents(node);
    return sum + distinctTops(range.getClientRects());
  }, 0);

  const textOf = (ids) => ids.map((id) => document.getElementById(id)?.innerText || '').join(' ').trim();
  const idList = (el, name) => String(el.getAttribute(name) || '').split(/\s+/).filter(Boolean);

  const labelled = (el) => {
    const byId = textOf(idList(el, 'aria-labelledby'));
    if (byId) return byId;
    if (el.getAttribute('aria-label')) return el.getAttribute('aria-label');
    if (el.labels?.length) return Array.from(el.labels).map((label) => label.textContent).join(' ');
    const img = el.querySelector?.('img[alt], svg title');
    const fallback = img ? (img.getAttribute('alt') || img.textContent) : '';
    return (el.innerText || '').trim() || el.getAttribute('title') || fallback;
  };

  const INTERACTIVE = [
    'a[href]', 'button', 'input:not([type=hidden])', 'select', 'textarea', 'summary',
    '[role=button]', '[role=link]', '[role=tab]'
  ].join(', ');
  const ATTRS = [
    'data-action', 'aria-current', 'aria-selected', 'aria-pressed', 'aria-invalid', 'aria-describedby',
    'aria-label', 'aria-labelledby', 'data-state', 'href', 'type', 'role', 'class'
  ];
  const parents = new Map();
  const parentId = (node) => {
    if (!parents.has(node)) parents.set(node, parents.size);
    return parents.get(node);
  };

  const typeOf = (cs) => ({
    font_size: px(cs.fontSize), font_weight: Number(cs.fontWeight) || 400, font_style: cs.fontStyle,
    font_family: cs.fontFamily.split(',')[0].replace(/["']/g, '').trim(),
    line_height: cs.lineHeight === 'normal' ? px(cs.fontSize) * 1.2 : px(cs.lineHeight),
    letter_spacing: cs.letterSpacing === 'normal' ? 0 : px(cs.letterSpacing),
    text_transform: cs.textTransform, decoration: cs.textDecorationLine, text_indent: px(cs.textIndent),
    mono: /mono|courier|menlo|consolas/i.test(cs.fontFamily),
  });

  const sides = (cs, prop) => ['Top', 'Right', 'Bottom', 'Left'].map((side) => px(cs[`border${side}${prop}`]));

  const paintOf = (el, cs) => ({
    color: paint(cs.color), bg: paint(cs.backgroundColor), own_ground: ground(el),
    ground: ground(el.parentElement || el),
    border_width: Math.max(...sides(cs, 'Width')), border_color: paint(cs.borderTopColor),
    outline_width: cs.outlineStyle === 'none' ? 0 : px(cs.outlineWidth), outline_color: paint(cs.outlineColor),
    box_shadow: cs.boxShadow === 'none' ? '' : cs.boxShadow, stroke_width: px(cs.strokeWidth),
    stroke_opacity: Number(cs.strokeOpacity) || 1,
    parent_color: paint(el.parentElement ? getComputedStyle(el.parentElement).color : cs.color),
  });

  const boxOf = (el, cs) => {
    const box = el.getBoundingClientRect();
    return {
      rect: { x: box.left, y: box.top, w: box.width, h: box.height }, display: cs.display, position: cs.position,
      content_x: box.left + px(cs.borderLeftWidth) + px(cs.paddingLeft),
      margin_block: [px(cs.marginBlockStart), px(cs.marginBlockEnd)],
      transform: cs.transform, perspective: cs.perspective,
    };
  };

  const amidText = (el) => el.tagName === 'A' && textNodes(el.parentElement || el).length > 0;

  // The surface an action answers for: the nearest card or form ancestor, named
  // by its own data-design-law index. Ancestors walk before descendants in
  // document order, so every described card already carries its number.
  const SURFACE = '[class*=card], [data-card], form';
  const hostOf = (el) =>
    (el.parentElement && el.parentElement.closest(SURFACE))?.getAttribute('data-design-law') ?? null;

  const roleOf = (el) => ({
    parent: (el.parentElement?.tagName || '').toLowerCase(),
    prev_tag: (el.previousElementSibling?.tagName || '').toLowerCase(),
    pid: parentId(el.parentElement), path: el.tagName === 'A' ? el.pathname : '', in_link: !!el.closest('a'),
    in_nav: !!el.closest('nav, [role=navigation]'), in_main: !!el.closest('main, [role=main]'),
    interactive: el.matches(INTERACTIVE), in_text: amidText(el), icon: !!el.querySelector('svg, img, i'),
    primary: el.matches('.button-primary, [data-primary]'), canvas: el.tagName === 'CANVAS',
    submit: el.matches('main form [type=submit], main form button:not([type])'),
    host: hostOf(el),
  });

  const describe = (el, index) => {
    const cs = getComputedStyle(el);
    const attrs = {};
    ATTRS.forEach((name) => {
      if (el.hasAttribute(name)) attrs[name] = el.getAttribute(name);
    });
    el.setAttribute('data-design-law', String(index));
    const name = String(labelled(el) || '').replace(/\s+/g, ' ').trim();
    return {
      index, key: keyOf(el), tag: el.tagName.toLowerCase(), attrs, text: ownText(el).slice(0, 200),
      visible_text: (el.innerText || '').trim().slice(0, 200), name: name.slice(0, 200),
      described: textOf(idList(el, 'aria-describedby')).slice(0, 200), lines: lineTops(el),
      ...typeOf(cs), ...paintOf(el, cs), ...boxOf(el, cs), ...roleOf(el),
    };
  };

  const SKIP = ['SCRIPT', 'STYLE', 'TEMPLATE', 'NOSCRIPT', 'BR'];

  const elements = () => {
    const out = [];
    const all = document.body ? document.body.querySelectorAll('*') : [];
    for (let i = 0; i < all.length && out.length < MAX; i++) {
      const el = all[i];
      if (!SKIP.includes(el.tagName) && shown(el, getComputedStyle(el))) out.push(describe(el, out.length));
    }
    return out;
  };

  // The style a forced :hover or :focus-visible leaves on one measured element.
  const styleOf = (index) => {
    const el = document.querySelector(`[data-design-law="${Number(index)}"]`);
    if (!el) return null;
    const cs = getComputedStyle(el);
    return {
      decoration: cs.textDecorationLine, border_width: px(cs.borderTopWidth), font_weight: Number(cs.fontWeight),
      box_shadow: cs.boxShadow === 'none' ? '' : cs.boxShadow, outline_color: paint(cs.outlineColor),
      outline_width: cs.outlineStyle === 'none' ? 0 : px(cs.outlineWidth),
    };
  };

  // Each element that paints its own text, with the face it asks for.
  const measured = () => Array.from(document.querySelectorAll('[data-design-law]'));
  const fontRequests = () => measured().filter((el) => ownText(el)).map((el) => {
    const cs = getComputedStyle(el);
    return {
      index: el.getAttribute('data-design-law'), family: cs.fontFamily.split(',')[0].replace(/["']/g, '').trim(),
      weight: Number(cs.fontWeight), style: cs.fontStyle, caps: cs.fontVariantCaps,
      synthesis: cs.fontSynthesis || 'weight style',
    };
  });

  // A number and its unit (or its digit groups) as a Range: one line top or it broke.
  const NUMBER_UNIT = /\d[\d\u00a0\u202f ]*\s?(?:kr|NOK|,-|km|min|kg|stk|%|kl\.|m|t|g)(?![\p{L}])/giu;

  const unitRanges = (node) => Array.from(node.textContent.matchAll(NUMBER_UNIT)).map((match) => {
    const range = document.createRange();
    range.setStart(node, match.index);
    range.setEnd(node, match.index + match[0].trimEnd().length);
    return { text: match[0].trim(), tops: distinctTops(range.getClientRects()), key: keyOf(node.parentElement) };
  });

  const numbers = () => {
    const out = [];
    const walker = document.createTreeWalker(document.body || de, NodeFilter.SHOW_TEXT);
    for (let node = walker.nextNode(); node && out.length < 200; node = walker.nextNode()) {
      const parent = node.parentElement;
      if (parent && shown(parent, getComputedStyle(parent))) out.push(...unitRanges(node));
    }
    return out;
  };

  const CHROME = [
    'header', 'nav', 'footer', '[role=banner]', '[role=navigation]', '.tab-bar', '[data-chrome]', '[role=dialog]',
    '.cookie-notice', '.install-prompt'
  ].join(', ');

  // The outermost fixed or sticky chrome, whether or not it is painted now.
  const chromeRoots = () => {
    const roots = [];
    document.querySelectorAll('body *').forEach((el) => {
      if (!['fixed', 'sticky'].includes(getComputedStyle(el).position) || !el.matches(CHROME)) return;
      if (!roots.some((root) => root.contains(el))) roots.push(el);
    });
    return roots;
  };

  const visibleArea = (box) => {
    const width = Math.max(0, Math.min(box.right, de.clientWidth) - Math.max(box.left, 0));
    const height = Math.max(0, Math.min(box.bottom, window.innerHeight) - Math.max(box.top, 0));
    return width * height;
  };

  const PRIMARY = '.button-primary, [data-primary]';

  const chrome = () => chromeRoots().map((el) => {
    const cs = getComputedStyle(el);
    const area = visibleArea(el.getBoundingClientRect());
    return {
      key: keyOf(el), area, display: cs.display, visibility: cs.visibility, transition: cs.transitionDuration,
      primary: el.matches(PRIMARY) || !!el.querySelector(PRIMARY), on_screen: area > 0 && shown(el, cs),
      nav: el.matches('nav, [role=navigation]') || !!el.querySelector('nav, [role=navigation]'),
    };
  });

  const overlap = (one, two) => {
    const width = Math.max(0, Math.min(one.right, two.right) - Math.max(one.left, two.left));
    const height = Math.max(0, Math.min(one.bottom, two.bottom) - Math.max(one.top, two.top));
    return width * height;
  };

  const covering = (el) => Array.from(document.querySelectorAll('body *')).filter((other) => {
    const cs = getComputedStyle(other);
    return ['fixed', 'sticky'].includes(cs.position) && !other.contains(el) && shown(other, cs);
  });

  const focused = () => {
    const el = document.activeElement;
    if (!el || el === document.body) return null;
    const box = el.getBoundingClientRect();
    const size = box.width * box.height;
    const covers = covering(el).map((other) => {
      const share = size > 0 ? overlap(box, other.getBoundingClientRect()) / size : 0;
      return { key: keyOf(other), share };
    }).filter((cover) => cover.share > 0);
    return { key: keyOf(el), rect: { x: box.left, y: box.top, w: box.width, h: box.height }, covers };
  };

  const SPACING = '* { line-height: 1.5 !important; letter-spacing: .12em !important;' +
    ' word-spacing: .16em !important }' +
    ' p { margin-block-end: 2em !important }';

  const clips = (el) => {
    const cs = getComputedStyle(el);
    if (!shown(el, cs) || !ownText(el)) return false;
    const hides = /hidden|clip/.test(cs.overflowX + cs.overflowY);
    const expands = cs.textOverflow === 'ellipsis' && (el.title || el.getAttribute('aria-expanded'));
    return hides && !expands && (el.scrollHeight > el.clientHeight + 1 || el.scrollWidth > el.clientWidth + 1);
  };

  // Text spacing per WCAG 1.4.12, then whatever clips or scrolls sideways.
  const spacing = () => {
    const style = document.createElement('style');
    style.textContent = SPACING;
    document.head.appendChild(style);
    const clipped = Array.from(document.querySelectorAll('body *')).filter(clips).map(keyOf);
    const sideways = de.scrollWidth > de.clientWidth + 1;
    style.remove();
    return { clipped: clipped.slice(0, 20), sideways };
  };

  const page = () => ({
    root_font: px(getComputedStyle(de).fontSize), scroll_height: de.scrollHeight,
    inner_height: window.innerHeight, width: de.clientWidth, path: location.pathname,
  });

  const helpers = { paint, shown, keyOf };
  window.__designLaws = { elements, numbers, chrome, focused, spacing, page, styleOf, fontRequests, helpers };
  return true;
})()
