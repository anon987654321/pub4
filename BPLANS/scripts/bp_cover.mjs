// Poise v2 of the BPLANS front matter (November 2026), applied to the BUILT
// output files — never to the anlage (PRESERVE_FIRST). Basis:
//   Bringhurst, Elements of Typographic Style, p. 61 — "poise consists
//   primarily of emptiness… a modest line or two near the top, and a line or
//   two near the bottom, with nothing more than taut, balanced white space in
//   between"; p. 35 — list spacing that separates and binds, no dot leaders;
//   p. 72–73 — no wads of blank leaves; Strunk & White, rule 17 — omit
//   needless words.
// v2 (this revision) deepens the v1 pass:
//   1. the vertical rhythm steps move onto larger multiples of the 1.5 rem
//      leading unit (sections 4 units screen / 5 units print, footer 4, nav
//      padding 3, header 5, h3 lead-in 1.5) — more void, one grid
//   2. print margins widen 16/15 mm → 18/17 mm around the unchanged 66 ch
//      measure (the measure binds at max-width:min(66ch,…), so the added
//      margin is all void, no re-flow of the measure)
//   3. govt_bergen's gradient wordmark is replaced by a plain mark in the
//      anlage's own EB Garamond, at the customer's request ("use plain, same
//      font as the rest for now") — the artwork is withdrawn, not re-set;
//      its colophon note is rewritten to record the replacement
//   4. the v1 stylesheet is migrated in place to the v2 stylesheet, so the
//      pass stays idempotent on files that already carry v1
//   5. v2.1: main's 3 rem print padding-bottom is dropped — on plans whose
//      last page ends flush (syre) it spilled an entirely blank page before
//      the colophon, the "wad of blank leaves" Bringhurst p. 72–73 condemns
// Transforms, all idempotent (re-running is a no-op):
//   - kicker omitted (fresh files only; v1 files already had it)
//   - wordmark setting per logo kind (fresh files only)
//   - stylesheet: append (fresh) or migrate v1 → v2 (marker-guarded)
//   - govt_bergen: gradient mark → plain mark, colophon note rewritten
// Expected transforms are enforced: a plan that lacks its expected transform
// fails the run (FINDING_HYGIENE: inconclusive is never silent pass).
// Usage: node scripts/bp_cover.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { OUTPUT_DIR as OUT } from './paths.mjs';
const ORDER = ['syre', 'speis', 'ragnhild', 'nato', 'norwegianhedge', 'pubhealthcare', 'govt_bergen'];
const GRADIENT = ['speis', 'norwegianhedge'];

const MARKER = 'cover revision 2026-11';
const V2TAG = 'poise v2.1';

const COVER_CSS = `/* ${MARKER} — ${V2TAG} (Bringhurst p. 61; Strunk & White 17) */
header{border-bottom:0;display:flex;flex-direction:column;text-align:center;padding:7.5rem 0 0;min-height:62vh}
header h1{font-weight:400;font-size:2.05em;line-height:1.18;margin:auto 0 0;text-wrap:balance}
header .byline{margin-top:1.5rem}
header .mark{margin-left:auto;margin-right:auto}
header .mark-brand{margin:0 auto}
.mark-plain{font-weight:400;font-size:1.3em;letter-spacing:.05em;line-height:1.2}
nav{border-bottom:0;padding:4.5rem 0 0}
nav h2{font-size:1.15em}
nav li{margin:.45em 0}
section{margin-top:6rem}
h3{margin-top:2.25rem}
footer{margin-top:6rem}
@media print{
  body{padding:18mm 17mm}
  main{padding-bottom:0}
  header{min-height:184mm;page-break-after:always}
  nav{page-break-after:page}
  section{margin-top:7.5rem}
}`;

const PLAIN_MARK = '<p class="mark mark-plain">Bergens Selvstyreparti</p>';
const PLAIN_NOTE = '<p>Logo: «Bergens Selvstyreparti» satt som tekstmerke i anleggets '
  + 'EB Garamond uten gradient, etter kundens ønske (november 2026); '
  + 'pub2-gradientmerket er erstattet.</p>';

const fails = [];

for (const plan of ORDER) {
  const file = `${OUT}/${plan}.html`;
  const before = readFileSync(file, 'utf8');
  let src = before;
  const acts = [];
  // fresh = never revised; v1 = carries the marker but not the v2 tag;
  // v2 = nothing to do (idempotent).
  const isV2 = src.includes(V2TAG);
  const isV1 = !isV2 && src.includes(MARKER);
  const fresh = !isV2 && !isV1;

  // 1. omit the kicker (fresh files only)
  if (fresh && /class="kicker"/.test(src)) {
    src = src.replace(/<p class="kicker">[^<]*<\/p>\n/, '');
    acts.push('kicker omitted');
  }

  // 2. wordmark setting, per kind (fresh files only; v1 already re-set them)
  if (fresh) {
    if (plan === 'syre' && src.includes('style="width:44mm;margin:0 0 .9rem;"')) {
      src = src.replace('style="width:44mm;margin:0 0 .9rem;"', 'style="width:40mm;margin:0 auto;"');
      acts.push('fractal mark centered, 44→40 mm');
    }
    if (GRADIENT.includes(plan) && src.includes('margin:0 0 .8rem;font-size:1.5em;')) {
      src = src.replace('margin:0 0 .8rem;font-size:1.5em;', 'margin:0 auto;font-size:1.3em;');
      acts.push('gradient mark centered, 1.5→1.3 em');
    }
    if (plan === 'ragnhild' && src.includes('font-size:2.35em;line-height:1.45;margin:0 0 1.1rem;')) {
      src = src.replace('font-size:2.35em;line-height:1.45;margin:0 0 1.1rem;', 'font-size:2.1em;line-height:1.45;margin:0 auto;');
      acts.push('Nosifer mark centered, 2.35→2.1 em');
    }
  }

  // 3. stylesheet: append (fresh) or migrate v1 → v2 in place
  if (fresh && !src.includes(MARKER)) {
    src = src.replace('</style>', COVER_CSS + '\n</style>');
    acts.push('cover stylesheet appended (poise v2)');
  } else if (isV1 && /\/\* cover revision 2026-11[\s\S]*?<\/style>/.test(src)) {
    src = src.replace(/\/\* cover revision 2026-11[\s\S]*?<\/style>/, COVER_CSS + '\n</style>');
    acts.push('cover stylesheet migrated v1→poise v2');
  }

  // 4. govt_bergen: plain wordmark at the customer's request
  if (plan === 'govt_bergen' && /<p class="mark" style="[^"]*background:linear-gradient[^"]*">Bergens Selvstyreparti<\/p>/.test(src)) {
    src = src.replace(/<p class="mark" style="[^"]*background:linear-gradient[^"]*">Bergens Selvstyreparti<\/p>/, PLAIN_MARK);
    acts.push('gradient wordmark → plain EB Garamond mark');
  }
  if (plan === 'govt_bergen' && /<p>Logo: «Bergens Selvstyreparti»-ordmerket i pub2-gradienten[^<]*<\/p>/.test(src)) {
    src = src.replace(/<p>Logo: «Bergens Selvstyreparti»-ordmerket i pub2-gradienten[^<]*<\/p>/, PLAIN_NOTE);
    acts.push('colophon logo note rewritten');
  }

  // expected transforms, enforced
  if (fresh) {
    if (!acts.includes('kicker omitted')) fails.push(`${plan}: kicker not omitted (expected on fresh run)`);
    if (!acts.some(a => a.startsWith('cover stylesheet'))) fails.push(`${plan}: cover stylesheet not appended`);
    if (plan === 'syre' && !acts.some(a => a.startsWith('fractal'))) fails.push('syre: fractal mark not re-set');
    if (GRADIENT.includes(plan) && !acts.some(a => a.startsWith('gradient mark'))) fails.push(`${plan}: gradient mark not re-set`);
    if (plan === 'ragnhild' && !acts.some(a => a.startsWith('Nosifer'))) fails.push('ragnhild: Nosifer mark not re-set');
  }
  if (isV1 && !acts.includes('cover stylesheet migrated v1→poise v2')) {
    fails.push(`${plan}: v1 stylesheet not migrated to poise v2`);
  }
  if (plan === 'govt_bergen') {
    if (!src.includes('class="mark mark-plain"')) fails.push('govt_bergen: plain mark missing after pass');
    if (/background:linear-gradient[^"]*">Bergens Selvstyreparti</.test(src)) fails.push('govt_bergen: gradient wordmark still present');
    if (!src.includes('pub2-gradientmerket er erstattet')) fails.push('govt_bergen: colophon logo note not rewritten');
  }

  if (src === before) acts.push('no change');
  writeFileSync(file, src);
  console.log(`${plan}: ${acts.join('; ')}`);
}

console.log('=== FAILS ===');
console.log(fails.length ? fails.join('\n') : 'NONE');
if (fails.length) process.exitCode = 1;
