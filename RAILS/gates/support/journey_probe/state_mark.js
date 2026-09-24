// Marks up to six visible, enabled controls with data-gate-state so the gate can
// address each one again, over CDP and from script. Returns their selectors.
(() => {
  // Measured unfocused, so a focus ring left by the tab walk is not read as a state.
  if (document.activeElement && document.activeElement !== document.body) document.activeElement.blur();
  document.querySelectorAll('[data-gate-state]').forEach((el) => el.removeAttribute('data-gate-state'));
  const shown = (el) => {
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return r.width > 0 && r.height > 0 && r.bottom > 0 && r.top < innerHeight &&
      cs.visibility !== 'hidden' && cs.display !== 'none';
  };
  const controls = [...document.querySelectorAll('button, input[type=submit], input[type=button], a.btn, .btn')]
    .filter((el) => shown(el) && !el.disabled && el.getAttribute('aria-disabled') !== 'true')
    .slice(0, 6);
  return controls.map((el, index) => {
    el.setAttribute('data-gate-state', String(index));
    const cls = String(el.className || '').split(' ').filter(Boolean).slice(0, 2).join('.');
    return el.tagName.toLowerCase() + (el.id ? `#${el.id}` : (cls ? `.${cls}` : ''));
  });
})()
