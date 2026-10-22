(() => {
  // Picks the text-owning elements whose painted face is worth asking Chrome
  // about and tags each with a temporary attribute so the CDP side can find
  // it. One element per distinct computed stack comes first: the stacks are
  // where a fallback hides, and a page repeats few of them. Keys are the ones
  // the geometry walk stored on the element, so a font names the same
  // element the payload does.
  const LIMIT = __LIMIT__;
  const owns = (el) => [...el.childNodes].some(n => n.nodeType === 3 && n.textContent.trim());
  const all = [...document.querySelectorAll('body *')].filter(el => el.__gpKey && owns(el));
  const firsts = new Map();
  for (const el of all) {
    const stack = getComputedStyle(el).fontFamily;
    if (!firsts.has(stack)) firsts.set(stack, el);
  }
  const chosen = new Set([...firsts.values()].slice(0, LIMIT));
  for (const el of all) { if (chosen.size >= LIMIT) break; chosen.add(el); }
  const keys = [];
  for (const el of chosen) {
    el.setAttribute('data-gp-font', String(keys.length));
    keys.push(el.__gpKey);
  }
  return keys;
})()
