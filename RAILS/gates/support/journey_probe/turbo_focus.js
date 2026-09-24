// Presses the first visible navigation link as a keyboard user would — focus,
// then click — and waits for Turbo Drive's visit to finish. Reports where focus
// landed. Turbo keeps a data-turbo-permanent element across the visit and drops
// focus to the body when the focused element is replaced; either is a place a
// reader can continue from. A focused element that is detached or not painted
// is not.
(async () => {
  const shown = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  const link = [...document.querySelectorAll('nav a[href], .tab-bar a[href]')].find((a) =>
    shown(a) && a.origin === location.origin && !a.hash && a.pathname !== location.pathname &&
    a.getAttribute('data-turbo') !== 'false' && !a.hasAttribute('data-turbo-method') &&
    !a.closest('[data-turbo="false"]') && a.target !== '_blank' && !a.hasAttribute('download'));
  if (!link) return { found: false };
  window.__gateDocument = true;
  const loaded = new Promise((resolve) => {
    document.addEventListener('turbo:load', () => resolve('load'), { once: true });
    setTimeout(() => resolve('timeout'), 8000);
  });
  link.focus();
  link.click();
  const outcome = await loaded;
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  const el = document.activeElement;
  const body = !el || el === document.body || el === document.documentElement;
  const cls = el ? String(el.className || '').split(' ').filter(Boolean).slice(0, 2).join('.') : '';
  return {
    found: true, href: link.getAttribute('href'), outcome, same_document: window.__gateDocument === true,
    body, connected: el?.isConnected === true, painted: !!el && (body || shown(el)),
    sel: el ? el.tagName.toLowerCase() + (el.id ? `#${el.id}` : (cls ? `.${cls}` : '')) : null
  };
})()
