// Independent verification of the built BPLANS HTMLs. Re-reads the OUTPUT
// files (does not trust the build) and executes the law checks the tree is
// held to, from MASTER/data/laws.yml:
//   HTML_LANG, META_CHARSET, SINGLE_H1, HTML_HEADING_HIERARCHY,
//   FINAL_NEWLINE, TAB_CHARACTER, TRAILING_WHITESPACE, TODO_FIXME,
//   NO_ASCII_LINE_ART, NO_TRAILING_ARROW, NO_CONSECUTIVE_BLANK_LINES,
//   STRUNK_WHITE (norwegian leeches), TYPOGRAPHY_DISCIPLINE (char audit),
//   EVIDENCE_SCORING (arithmetic re-verified here), NO_INLINE_SCRIPT_BLOCK
//   is accepted by reviewed exemption: standalone print sources carry
//   inline style and inline fonts because no asset pipeline exists here.
// Usage: node scripts/bp_check.mjs
import { readFileSync } from 'node:fs';
import { OUTPUT_DIR as OUT } from './paths.mjs';
const ORDER = ['syre', 'speis', 'ragnhild', 'nato', 'norwegianhedge', 'pubhealthcare', 'govt_bergen'];

const LEECHES = ['veldig', 'svært', 'ganske', 'nokså', 'temmelig', 'virkelig', 'simpelthen'];
const ALLOWED_NONASCII = new Set('æøåÆØÅÄäÖöÜüúÚ–—‐‑‘’“”…·™²₂₃³×°éÉè§«»−');

function parseNum(s) {
  return parseFloat(s
    .replaceAll('−', '-').replaceAll(' ', '').replaceAll('\u202f', '')
    .replaceAll('%', '').replace(',', '.'));
}

const fails = [];
const notes = [];

const ROW4 = /<tr><td>([^<]+)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><\/tr>/g;
const ROW4_ONE = new RegExp(ROW4.source);

// tfoot values for a 4-cell budget table: returns [v2026, v2027, v2028]
// (the row's label is dropped), or null when the table cannot be parsed —
// an inconclusive check must fail loudly, never pass.
function footVals(tableHtml) {
  const inner = tableHtml.match(/<tfoot>([\s\S]*?)<\/tfoot>/);
  if (!inner) return null;
  const cap = ROW4_ONE.exec(inner[1]);
  return cap ? [cap[2], cap[3], cap[4]] : null;
}

for (const plan of ORDER) {
  const file = `${OUT}/${plan}.html`;
  const src = readFileSync(file, 'utf8');
  const body = src.replace(/base64,[^"']+/g, '');
  const add = (m) => fails.push(`${plan}: ${m}`);

  // HTML_LANG + META_CHARSET + SINGLE_H1
  if (!/<html lang="n[bo]">/.test(src)) add('HTML_LANG: no lang="nb"/"no"');
  if (!/<meta charset="utf-8"/i.test(src)) add('META_CHARSET: missing');
  const h1s = [...src.matchAll(/<h1[\s>]/g)].length;
  if (h1s !== 1) add(`SINGLE_H1: found ${h1s}`);

  // heading hierarchy: h2 before h3, h3 before h4 (no skips downward)
  const levels = [...src.matchAll(/<h([1-4])[\s>]/g)].map(m => Number(m[1]));
  let prev = 0;
  for (const l of levels) {
    if (l > prev + 1) { add(`HTML_HEADING_HIERARCHY: h${l} follows h${prev}`); break; }
    prev = l;
  }

  // whitespace / final newline / tabs
  if (!src.endsWith('\n')) add('FINAL_NEWLINE: file does not end with newline');
  if (src.includes('\t')) add('TAB_CHARACTER: tab found');
  if (/ +$/m.test(src)) add('TRAILING_WHITESPACE: found');
  if (/\n{3,}/.test(src)) add('NO_CONSECUTIVE_BLANK_LINES: found');

  // unfinished work / placeholders / debug leftovers
  for (const bad of ['TODO', 'FIXME', 'undefined', 'NaN', 'XXX', '【']) {
    if (body.includes(bad)) add(`unfinished: ${bad} found in text`);
  }

  // ASCII line art and trailing arrows in links
  if (/^[\s]*[\-*_=~]{4,}[\s]*$/m.test(body)) add('NO_ASCII_LINE_ART: separator line found');
  for (const m of src.matchAll(/<a [^>]*>([^<]*)<\/a>/g)) {
    if (/[→←↔↗⇒»]$/.test(m[1].trim())) add(`NO_TRAILING_ARROW: link text ${JSON.stringify(m[1])}`);
  }

  // Norwegian prose leeches (STRUNK_WHITE, nb)
  for (const leech of LEECHES) {
    const re = new RegExp(`\\b${leech}\\b`, 'i');
    if (re.test(body)) add(`STRUNK_WHITE: leech "${leech}" found`);
  }

  // character audit
  const bad = new Map();
  for (const ch of body) {
    if (ch.charCodeAt(0) > 127 && !ALLOWED_NONASCII.has(ch)) bad.set(ch, (bad.get(ch) || 0) + 1);
  }
  for (const [c, n] of bad) add(`char: U+${c.charCodeAt(0).toString(16).toUpperCase()} ×${n}`);

  // structure: 8 sections, inline font discipline
  const sections = [...src.matchAll(/<section id="([^"]+)"/g)].length;
  if (sections !== 8) add(`sections: ${sections} (expected 8)`);
  const fonts = [...src.matchAll(/@font-face\{/g)].length;
  if (plan === 'ragnhild') {
    if (fonts !== 3) add(`font-face: ${fonts} (expected 3: EB Garamond ×2 + Nosifer)`);
    if (!/class="mark-brand">Ragnhilds</.test(body)) add('mark-brand: wordmark missing');
    // wordmark must not be reused as a heading font (checked on body so the
    // base64 payload cannot create phantom matches)
    if (/(?:^|\})\s*h[1-4][^{]*\{[^}]*Nosifer/.test(body)) add('wordmark: Nosifer used on a semantic heading');
  } else if (fonts !== 2) {
    add(`font-face: ${fonts} (expected 2)`);
  }

  // cover revision (November 2026): Bringhurst title page, mechanical side —
  // kicker omitted, poise v2 stylesheet and title-page print rules present,
  // govt_bergen's wordmark plain in the anlage's own EB Garamond
  if (/class="kicker"/.test(body)) add('cover: kicker still present');
  if (!body.includes('cover revision 2026-11')) add('cover: revision stylesheet missing');
  if (!body.includes('poise v2')) add('cover: poise v2 stylesheet missing');
  if (!body.includes('header{min-height:184mm;page-break-after:always}')) add('cover: title-page print rules missing');
  if (plan === 'govt_bergen') {
    if (!/class="mark mark-plain">Bergens Selvstyreparti</.test(body)) add('cover: plain party mark missing');
    if (/background-clip:text/.test(body)) add('cover: gradient wordmark still present');
  }

  // arithmetic, re-verified from the output file
  const res = body.match(/<caption>Resultatbudsjett[^<]*<\/caption>[\s\S]*?<\/table>/);
  if (res) {
    const tb = res[0].match(/<tbody>([\s\S]*?)<\/tbody>/)[1];
    const foot = footVals(res[0]);
    const rows = [...tb.matchAll(ROW4)].map(r => [r[1], r[2], r[3], r[4]]);
    if (!foot) {
      add('inconclusive: resultatbudsjett tfoot not parsed');
    } else for (let c = 0; c < 3; c++) {
      const inc = parseNum(rows[0][c + 1]);
      const cost = parseNum(rows[1][c + 1]);
      const ebit = parseNum(rows[2][c + 1]);
      const fin = parseNum(rows[3][c + 1]);
      const pre = parseNum(foot[c]);
      if (Math.abs(inc + cost - ebit) > 0.011) add(`resultat col${c}: driftsresultat ${inc + cost} ≠ ${ebit}`);
      if (Math.abs(ebit + fin - pre) > 0.011) add(`resultat col${c}: før skatt ${ebit + fin} ≠ ${pre}`);
    }
  } else add('resultatbudsjett: table missing');

  const liq = body.match(/<caption>Likviditetsbudsjett[^<]*<\/caption>[\s\S]*?<\/table>/);
  if (liq) {
    const tb = liq[0].match(/<tbody>([\s\S]*?)<\/tbody>/)[1];
    const foot = footVals(liq[0]);
    const rows = [...tb.matchAll(ROW4)].map(r => [r[1], r[2], r[3], r[4]]);
    if (!foot) {
      add('inconclusive: likviditetsbudsjett tfoot not parsed');
    } else for (let c = 0; c < 3; c++) {
      const total = rows.reduce((s, r) => s + parseNum(r[c + 1]), 0);
      if (Math.abs(total - parseNum(foot[c])) > 0.011) add(`likviditet col${c}: sum ${total} ≠ ${foot[c]}`);
      if (c < 2 && Math.abs(parseNum(foot[c]) - parseNum(rows[0][c + 2])) > 0.011) {
        add(`likviditet: saldo ${c}→${c + 1} breaks continuity`);
      }
    }
  } else add('likviditetsbudsjett: table missing');

  const fin = body.match(/<caption>Bevegelsens finansiering[^<]*<\/caption>[\s\S]*?<\/table>/);
  if (fin) {
    const tb = fin[0].match(/<tbody>([\s\S]*?)<\/tbody>/)[1];
    const footInner = fin[0].match(/<tfoot>([\s\S]*?)<\/tfoot>/);
    const cap = footInner
      ? /<tr><td>([^<]+)<\/td><td>([^<]*)<\/td><\/tr>/.exec(footInner[1]) : null;
    const rows = [...tb.matchAll(/<tr><td>([^<]+)<\/td><td>([^<]*)<\/td><\/tr>/g)].map(r => r[2]);
    if (!cap) add('inconclusive: finansieringstabell tfoot not parsed');
    else {
      const sum = rows.reduce((s, v) => s + parseNum(v), 0);
      if (Math.abs(sum - parseNum(cap[2])) > 0.011) add(`finansiering: sum ${sum} ≠ ${cap[2]}`);
      notes.push(`${plan}: finansiering sum ${sum} = ${cap[2]}`);
    }
  }

  notes.push(`${plan}: sections ${sections}, fonts ${fonts}, chars ${src.length}`);
}

console.log(notes.join('\n'));
console.log('=== FAILS ===');
console.log(fails.length ? fails.join('\n') : 'NONE');
if (fails.length) process.exitCode = 1;
