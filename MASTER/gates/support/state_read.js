// The painted state of one marked control, optionally with a state applied first
// and taken off again before returning. `cursor` is left out: a pointer shape is
// invisible on a touch screen and to anyone not hovering, so it cannot be the
// only thing that tells a state apart.
(() => {
  const el = document.querySelector('[data-gate-state="__INDEX__"]');
  if (!el) return null;
  const mutation = '__MUTATION__';
  const holder = el.closest('form') || el;
  const paint = (node) => {
    const cs = getComputedStyle(node);
    return [cs.color, cs.backgroundColor, cs.opacity, cs.borderTopColor, cs.borderTopWidth,
      cs.outlineStyle, cs.outlineColor, cs.outlineWidth, cs.transform, cs.filter, cs.boxShadow,
      cs.textDecorationLine].join('|');
  };
  const hadDisabled = el.disabled;
  if (mutation === 'disabled') {
    if ('disabled' in el) el.disabled = true; else el.setAttribute('aria-disabled', 'true');
  }
  if (mutation === 'busy') holder.setAttribute('aria-busy', 'true');
  const painted = paint(el) + '||' + (holder === el ? '' : paint(holder));
  if (mutation === 'disabled') {
    if ('disabled' in el) el.disabled = hadDisabled; else el.removeAttribute('aria-disabled');
  }
  if (mutation === 'busy') holder.removeAttribute('aria-busy');
  return painted;
})()
