(async () => {
  // Which face paints Norwegian letters in each font stack the page wears.
  //
  // document.fonts.check cannot say: it answers true when no face in the
  // stack claims the characters at all, which is the fallback case itself.
  // Width can. Text set in "Family", monospace and in "Family", serif measures
  // the same only when Family draws every glyph; a glyph it lacks falls
  // through to two different generics and the two widths part.
  const NORWEGIAN = 'æøåÆØÅ';
  const LATIN = 'abcdefghijklmnopqrstuvwxyz';
  const GENERIC = new Set([
    'serif', 'sans-serif', 'monospace', 'cursive', 'fantasy', 'system-ui', 'ui-serif',
    'ui-sans-serif', 'ui-monospace', 'ui-rounded', 'emoji', 'math', 'fangsong'
  ]);
  const ctx = document.createElement('canvas').getContext('2d');
  const width = (stack, text) => { ctx.font = `32px ${stack}`; return ctx.measureText(text).width; };
  const drawsAll = (family, text) => width(`${family}, monospace`, text) === width(`${family}, serif`, text);

  const stacks = new Set();
  const all = document.querySelectorAll('body *');
  for (let i = 0; i < all.length && i < 2000; i++) {
    if ([...all[i].childNodes].some(n => n.nodeType === 3 && n.textContent.trim())) {
      stacks.add(getComputedStyle(all[i]).fontFamily);
    }
  }

  // The face that renders is the first named family the browser has; a
  // family it lacks for Latin too is skipped, as the browser skips it.
  const rows = [];
  for (const stack of stacks) {
    const named = stack.split(',').map(f => f.trim().replace(/^["']|["']$/g, ''))
      .filter(f => f && !GENERIC.has(f)).map(f => `"${f}"`);
    for (const family of named) {
      await document.fonts.load(`32px ${family}`, LATIN + NORWEGIAN).catch(() => []);
      if (!drawsAll(family, LATIN)) continue;
      rows.push({ stack: stack, family: family.slice(1, -1), covered: drawsAll(family, NORWEGIAN) });
      break;
    }
  }
  return { glyphs: rows.slice(0, 20) };
})()
