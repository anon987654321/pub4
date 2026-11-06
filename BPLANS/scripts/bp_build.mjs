// Build the completed pub4.good BPLANS in Node.
// Port of the retired bp_build.py (same insertion order, same checks), plus:
//  - content merge from content_add.mjs ('+' appends, else replaces;
//    govt_bergen.tech_extra is composed so FETAT facts land inside the
//    Plattformforslag 1 group)
//  - ragnhild brand wordmark in Nosifer (SIL OFL), embedded as woff2 data URL
//    and used ONLY for the wordmark, never for semantic headings
//  - aria-hidden on the decorative SYRE fractal mark
// Usage: node scripts/bp_build.mjs
import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { OUTPUT_DIR as OUT, SOURCE_DIR as SRC } from './paths.mjs';
import { PLANS_A } from './plans_a.mjs';
import { PLANS_B } from './plans_b.mjs';
import { ADDITIONS } from './content_add.mjs';

const PLANS = { ...PLANS_A, ...PLANS_B };

const PUB_SYRE = `${SRC}/syre.html`;
mkdirSync(OUT, { recursive: true });
const ORDER = ['syre', 'speis', 'ragnhild', 'nato', 'norwegianhedge', 'pubhealthcare', 'govt_bergen'];
const TITLES = {
  syre: 'SYRE™ — forretningsplan', speis: 'SPEIS — forretningsplan',
  ragnhild: 'Ragnhild — forretningsplan', nato: 'NATO Aurora — forretningsplan',
  norwegianhedge: 'Norwegian Hedge — forretningsplan',
  pubhealthcare: 'pub.healthcare — forretningsplan',
  govt_bergen: 'Bergen Selvstyreparti — forretningsplan',
};

// ---- merge additions -------------------------------------------------------
function mergeAdditions() {
  for (const [plan, fields] of Object.entries(ADDITIONS)) {
    for (const [field, value] of Object.entries(fields)) {
      if (field === 'tech_extra_fetat' || field === 'tech_extra_forslag3') continue;
      if (typeof value === 'string' && value.startsWith('+')) {
        PLANS[plan][field] = PLANS[plan][field] + value.slice(1);
      } else {
        PLANS[plan][field] = value;
      }
    }
  }
  const g = PLANS.govt_bergen;
  const anchor = '</p>\n<h3>Plattformforslag 2';
  if (!g.tech_extra.includes(anchor)) {
    throw new Error('govt_bergen: FETAT anchor not found in tech_extra');
  }
  g.tech_extra = g.tech_extra.replace(
    anchor,
    '</p>\n' + ADDITIONS.govt_bergen.tech_extra_fetat.trim() + '\n<h3>Plattformforslag 2',
  ) + ADDITIONS.govt_bergen.tech_extra_forslag3;
}
mergeAdditions();

// ---- logos -----------------------------------------------------------------
function staticFractal() {
  const src = readFileSync(PUB_SYRE, 'utf8');
  const m = src.match(/<svg id="(?:fractalText|syreMark)"[\s\S]*?<\/svg>/);
  if (!m) throw new Error('SYRE source has no recoverable fractal SVG');
  let svg = m[0]
    .replace(/<animate[^>]*?\/>/g, '')
    .replace(/<animateTransform[^>]*?\/>/g, '')
    .replace(/<animate\b[^>]*>/g, '')
    .replace('id="fractalText"', 'id="syreMark" aria-hidden="true" focusable="false"')
    .replace(/font-family="Roboto, sans-serif"/g,
      'font-family="Roboto, DejaVu Sans, sans-serif"');
  svg = svg.replace("font-family=\"'Roboto', sans-serif\"",
    "font-family=\"'Roboto', 'DejaVu Sans', sans-serif\"");
  return svg;
}

function gradientMark(text, gradient) {
  const style = ('margin:0 0 .8rem;font-size:1.5em;line-height:1.15;font-weight:800;'
    + 'letter-spacing:.02em;width:max-content;background:%s;'
    + '-webkit-background-clip:text;background-clip:text;color:transparent;'
    + 'print-color-adjust:exact;-webkit-print-color-adjust:exact;').replace('%s', gradient);
  return '<p class="mark" style="%s">%s</p>'
    .replace('%s', style).replace('%s', escapeHtml(text));
}

function fontMark(text) {
  return '<p class="mark-brand">%s</p>'.replace('%s', escapeHtml(text));
}

function plainMark(text) {
  // Plain wordmark in the anlage's own EB Garamond — no gradient, no display
  // font. Introduced November 2026 for govt_bergen at the customer's request.
  return '<p class="mark mark-plain">%s</p>'.replace('%s', escapeHtml(text));
}

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function logoHtml(plan) {
  const lg = PLANS[plan].logo;
  if (!lg) return '';
  if (lg.kind === 'gradient') return gradientMark(lg.text, lg.gradient);
  if (lg.kind === 'font') return fontMark(lg.text);
  if (lg.kind === 'plain') return plainMark(lg.text);
  return '<div class="mark" style="width:44mm;margin:0 0 .9rem;">'
    + staticFractal() + '</div>';
}

function fontCss() {
  const ragnhild = readFileSync(`${SRC}/ragnhild.html`, 'utf8');
  const match = ragnhild.match(/@font-face\{[^}]*font-family:'Nosifer'[^}]*src:url\(data:font\/woff2;base64,([A-Za-z0-9+/=]+)\)/s);
  if (!match) throw new Error('Nosifer font is not embedded in BPLANS/ragnhild.html');
  const b64 = match[1];
  return ("@font-face{font-family:'Nosifer';font-style:normal;font-weight:400;"
    + "src:url(data:font/woff2;base64," + b64 + ") format('woff2');}"
    + "\n.mark-brand{font-family:'Nosifer','EB Garamond',Georgia,serif;font-weight:400;"
    + 'font-size:2.35em;line-height:1.45;margin:0 0 1.1rem;color:inherit;}');
}

// ---- insertion -------------------------------------------------------------
const SECTION_KEYS = [
  ['sammen', 'why_now'],
  ['marked', 'kundeinnsikt_gomarket'],
  ['teknologi', 'tech_extra'],
  ['modell', 'unit'],
  ['veikart', 'milestones'],
  ['finansiering', 'finance'],
  ['team', 'ekstern'],
];

function blocksFor(plan, key) {
  const p = PLANS[plan];
  if (key === 'why_now') return p.why_now.trim();
  if (key === 'kundeinnsikt_gomarket') {
    return (p.kundeinnsikt.trim() + '\n' + p.gomarket.trim()).trim();
  }
  if (key === 'finance') {
    return (p.resultat.trim() + '\n' + p.likviditet.trim() + '\n' + p.risiko.trim()).trim();
  }
  return p[key].trim();
}

// ---- arithmetic ------------------------------------------------------------
function parseNum(s) {
  return parseFloat(s
    .replaceAll('−', '-')
    .replaceAll(' ', '')
    .replaceAll('\u202f', '')
    .replaceAll('%', '')
    .replace(',', '.'));
}

const ROW4 = /<tr><td>([^<]+)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><td>([^<]*)<\/td><\/tr>/g;
const ROW4_ONE = new RegExp(ROW4.source);

function cellRows(table) {
  const tb = table.match(/<tbody>([\s\S]*?)<\/tbody>/);
  const footInner = table.match(/<tfoot>([\s\S]*?)<\/tfoot>/);
  const rows = tb
    ? [...tb[1].matchAll(ROW4)].map(r => [r[1], r[2], r[3], r[4]])
    : [];
  const fm = footInner ? ROW4_ONE.exec(footInner[1]) : null;
  const footRow = fm ? [fm[1], fm[2], fm[3], fm[4]] : null;
  return { rows, footRow };
}

function checkTables(plan, content) {
  const errs = [];
  const twoCol = (caption, sumCheck) => {
    const m = content.match(new RegExp('<caption>' + caption + '[^<]*</caption>[\\s\\S]*?</table>'));
    if (!m) return;
    const tb = m[0].match(/<tbody>([\s\S]*?)<\/tbody>/);
    const foot = m[0].match(/<tfoot>[\s\S]*?<\/tfoot>/);
    const cells = (s) => [...s.matchAll(/<tr><td>([^<]+)<\/td><td>([^<]*)<\/td><\/tr>/g)].map(r => [r[1], r[2]]);
    const rows = cells(tb ? tb[1] : '');
    const footRow = foot ? cells(/<tr><td>[\s\S]*?<\/tfoot>/.exec(foot[0])[0]) : [];
    if (rows.length && footRow.length) sumCheck(rows, footRow[0]);
  };

  const res = content.match(/<caption>Resultatbudsjett[^<]*<\/caption>[\s\S]*?<\/table>/);
  if (res) {
    const { rows, footRow } = cellRows(res[0]);
    if (rows.length >= 3 && footRow) {
      for (let c = 0; c < 3; c++) {
        const inc = parseNum(rows[0][c + 1]);
        const cost = parseNum(rows[1][c + 1]);
        const ebit = parseNum(rows[2][c + 1]);
        const fin = parseNum(rows[3][c + 1]);
        const pre = parseNum(footRow[c + 1]);
        if (Math.abs(inc + cost - ebit) > 0.011) errs.push(`resultat driftsresultat col${c}: ${inc + cost} vs ${ebit}`);
        if (Math.abs(ebit + fin - pre) > 0.011) errs.push(`resultat før skatt col${c}: ${ebit + fin} vs ${pre}`);
      }
    } else {
      errs.push(`inconclusive: resultatbudsjett not parsed (rows ${rows.length}, foot ${footRow ? 'ok' : 'missing'})`);
    }
  }

  const liq = content.match(/<caption>Likviditetsbudsjett[^<]*<\/caption>[\s\S]*?<\/table>/);
  if (liq) {
    const { rows, footRow } = cellRows(liq[0]);
    if (rows.length >= 5 && footRow) {
      for (let c = 0; c < 3; c++) {
        const total = rows.reduce((s, r) => s + parseNum(r[c + 1]), 0);
        if (Math.abs(total - parseNum(footRow[c + 1])) > 0.011) errs.push(`likviditet col${c}: ${total} vs ${footRow[c + 1]}`);
      }
      for (let c = 0; c < 2; c++) {
        if (Math.abs(parseNum(footRow[c + 1]) - parseNum(rows[0][c + 2])) > 0.011) {
          errs.push(`likviditet kontinuitet ${c}→${c + 1}: ${footRow[c + 1]} vs ${rows[0][c + 2]}`);
        }
      }
    } else {
      errs.push(`inconclusive: likviditetsbudsjett not parsed (rows ${rows.length}, foot ${footRow ? 'ok' : 'missing'})`);
    }
  }

  twoCol('Bevegelsens finansiering', (rows, footRow) => {
    const sum = rows.reduce((s, r) => s + parseNum(r[1]), 0);
    if (Math.abs(sum - parseNum(footRow[1])) > 0.011) errs.push(`finansiering sum: ${sum} vs ${footRow[1]}`);
  });
  // FINDING_HYGIENE_inconclusive_as_pass: an unparseable finansiering table is
  // a finding, not a pass.
  if (content.includes('Bevegelsens finansiering')
    && !/<caption>Bevegelsens finansiering[^<]*<\/caption>[\s\S]*?<tfoot>/.test(content)) {
    errs.push('inconclusive: finansieringstabellen mangler tfoot-sum');
  }

  return errs;
}

// ---- character audit -------------------------------------------------------
const ALLOWED_NONASCII = new Set('æøåÆØÅÄäÖöÜüúÚ–—‐‑‘’“”…·™²₂₃³×°éÉè§«»−');

function charCheck(txt, plan, where) {
  const bad = new Map();
  for (const ch of txt) {
    if (ch.charCodeAt(0) > 127 && !ALLOWED_NONASCII.has(ch)) {
      bad.set(ch, (bad.get(ch) || 0) + 1);
    }
  }
  return [...bad.entries()].map(([c, n]) =>
    `${plan}/${where}: U+${c.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')} ${JSON.stringify(c)} ×${n}`);
}

// ---- main ------------------------------------------------------------------
const report = [];
const fails = [];

for (const plan of ORDER) {
  let src = readFileSync(`${SRC}/${plan}.html`, 'utf8');
  const origTitle = (src.match(/<title>([^<]+)<\/title>/) || [])[1];
  if (origTitle !== TITLES[plan]) report.push(`${plan}: title mismatch ${JSON.stringify(origTitle)}`);

  const starts = [...src.matchAll(/<section id="([^"]+)"/g)].map(m => [m.index, m[1]]);
  if (starts.length !== 8) {
    fails.push(`${plan}: expected 8 sections, found ${starts.length} (${starts.map(s => s[1])})`);
    continue;
  }
  const usedKeys = new Set();
  const todo = [];
  for (const [pos, sid] of starts) {
    let key = null;
    for (const [frag, k] of SECTION_KEYS) {
      if (sid.includes(frag)) { key = k; break; }
    }
    if (key === null) {
      if (sid.includes('rekraft') || sid.includes('baerekraft')) continue;
      report.push(`${plan}: no mapping for section id ${JSON.stringify(sid)}`);
      continue;
    }
    const content = blocksFor(plan, key);
    if (!content) continue;
    todo.push([pos, key, content]);
  }
  for (const [pos, key, content] of [...todo].reverse()) {
    const endpos = src.indexOf('</section>', pos);
    if (endpos <= pos) throw new Error(`${plan}: section end not found`);
    src = src.slice(0, endpos) + '\n' + content + '\n' + src.slice(endpos);
    for (const e of checkTables(plan, content)) fails.push(`${plan}: ${e}`);
    for (const e of charCheck(content, plan, key)) fails.push(e);
    usedKeys.add(key);
  }
  const missing = ['why_now', 'kundeinnsikt_gomarket', 'unit', 'milestones', 'finance', 'ekstern']
    .filter(k => !usedKeys.has(k));
  if (missing.length) fails.push(`${plan}: missing insertions ${missing.join(', ')}`);

  if (plan === 'ragnhild') {
    src = src.replace('</style>', fontCss() + '\n</style>');
  }
  const lg = logoHtml(plan);
  if (lg) {
    const h1pos = src.indexOf('<h1');
    src = src.slice(0, h1pos) + lg + '\n' + src.slice(h1pos);
  }

  // Cosmetic normalisation of restored archive markup (TRAILING_WHITESPACE,
  // CONSECUTIVE rules): CRLF and line-end spaces inside the archived SVG carry
  // no rendering meaning. Documented in the restoration report.
  src = src.replace(/\r\n/g, '\n').replace(/[ \t]+$/gm, '').replace(/\n{3,}/g, '\n\n');
  if (plan === 'ragnhild') {
    // STRUNK_WHITE nb leech, found by review in the preserved anlage prose:
    // the qualifier changes no meaning and is removed.
    src = src.replace('som virkelig gjenspeiler', 'som gjenspeiler');
  }

  const lgd = PLANS[plan].logo;
  const note = lgd ? lgd.note : 'Ingen egen merkegrafikk fantes i arkivene (pub–pub3); intet er tilføyd.';
  const colo = '<p>Gjenopprettet fra pub-, pub2- og pub3-arkivene og fullført med kundeinnsikt, '
    + 'salgsspor, enhetsøkonomi, milepæler, risikomatrise og tre-års budsjetter etter '
    + 'Innovasjon Norges vurderingskriterier · november 2026.</p>\n'
    + '<p>' + note + '</p>\n';
  src = src.replace('</footer>', colo + '</footer>');
  if (!src.endsWith('\n')) src += '\n';

  const body = src.replace(/base64,[^"']+/g, '');
  for (const e of charCheck(body, plan, 'full')) fails.push(e);

  writeFileSync(`${OUT}/${plan}.html`, src);
  report.push(`${plan}: ok (${src.length} chars, logo=${lgd ? lgd.kind : 'none'})`);
}

console.log(report.join('\n'));
console.log('=== FAILS ===');
console.log(fails.length ? fails.join('\n') : 'NONE');
if (fails.length) process.exitCode = 1;
