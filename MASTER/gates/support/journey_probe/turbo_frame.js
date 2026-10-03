// Follows the first visible link that targets a <turbo-frame> and reports what
// the frame did with the answer. Lazy frames (a src on the frame) are read
// first, because a frame that loaded "Content missing" on arrival is the same
// defect without a click. window.__gateDocument survives only if the click did
// not become a whole-page load.
(async () => {
  const shown = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const missing = (frame) => /content missing/i.test(frame.textContent || '');
  const lazy = [...document.querySelectorAll('turbo-frame[src]')]
    .map((frame) => ({ id: frame.id, complete: frame.hasAttribute('complete'), missing: missing(frame) }));
  const targetOf = (a) => {
    const named = a.getAttribute('data-turbo-frame');
    if (named === '_top') return null;
    if (named) return document.getElementById(named);
    const frame = a.closest('turbo-frame[id]');
    return frame?.getAttribute('target') !== '_top' ? frame : null;
  };
  const link = [...document.querySelectorAll('a[href]')].find((a) =>
    shown(a) && a.origin === location.origin && !a.hash && a.getAttribute('data-turbo') !== 'false' &&
    !a.hasAttribute('data-turbo-method') && a.target !== '_blank' && targetOf(a) &&
    a.pathname !== location.pathname);
  if (!link) return { found: false, lazy };
  const frame = targetOf(link);
  window.__gateDocument = true;
  const before = location.href;
  const outcome = await new Promise((resolve) => {
    frame.addEventListener('turbo:frame-load', () => resolve('load'), { once: true });
    document.addEventListener('turbo:frame-missing', () => resolve('missing'), { once: true });
    setTimeout(() => resolve('timeout'), 6000);
    link.click();
  });
  await new Promise((resolve) => requestAnimationFrame(() => setTimeout(resolve, 50)));
  const advance = (link.getAttribute('data-turbo-action') || frame.getAttribute('data-turbo-action')) === 'advance';
  return {
    found: true, lazy, href: link.getAttribute('href'), frame: frame.id, outcome,
    same_document: window.__gateDocument === true, connected: frame.isConnected,
    missing: missing(frame), advance, url_changed: location.href !== before
  };
})()
