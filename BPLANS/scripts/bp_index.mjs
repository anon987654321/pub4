// Generate BPLANS/index.html in the pub4 anlage: reuse the inline EB Garamond
// from syre.html, list the seven pairs, sum the funding. Port of the retired
// bp_index.py, with the ragnhild logo row updated (Nosifer wordmark).
// Usage: node scripts/bp_index.mjs
import { readFileSync, writeFileSync } from 'node:fs';
import { OUTPUT_DIR as OUT } from './paths.mjs';
const syre = readFileSync(`${OUT}/syre.html`, 'utf8');
const fonts = [...syre.matchAll(/@font-face\{[\s\S]*?\}/g)].map(m => m[0]);
if (fonts.length !== 2) throw new Error(`expected 2 font-face in syre.html, got ${fonts.length}`);
const fontcss = fonts.join('\n');

const PLANS = [
  ['syre', 'SYRE™', '3D-printede sko, NOK 250 000', 'Environment & Sustainability'],
  ['ragnhild', 'Ragnhild', 'begravelsesbyrå med Karaokekiste og Diskokiste, NOK 150 000', 'Social Innovation'],
  ['speis', 'SPEIS', 'arktiske dominanseskip og kampfly, NOK 500 000', 'Maritime + Defense'],
  ['nato', 'NATO Aurora', 'nuclear-hybrid isbrytere, NOK 500 000', 'Maritime + Defense'],
  ['norwegianhedge', 'Norwegian Hedge', 'Ruby-drevet bot-swarm og AI³, NOK 300 000', 'Technology + Finance'],
  ['pubhealthcare', 'pub.healthcare', 'autonome parametriske sykehus, NOK 500 000', 'Health'],
  ['govt_bergen', 'Bergen Selvstyreparti', 'blockchain-basert lokalt styresett, NOK 200 000', 'Civic Tech'],
];
const total = PLANS.reduce((s, p) => s + parseInt(p[2].split('NOK ')[1].replaceAll(' ', ''), 10), 0);
if (total !== 2400000) throw new Error(`funding total ${total} ≠ 2400000`);

const rows = PLANS.map(([k, t, d, s]) =>
  `  <li><a href="${k}.html">${t}</a> — ${d} <span class="tag">${s}</span></li>`).join('\n');

const LOGOS = {
  syre: '«SYRE»-fraktalmerket (pub), statisk',
  ragnhild: '«Ragnhilds»-ordmerke i Nosifer (halloween-versjonene i arkivene; gratis dråpefont, SIL OFL)',
  speis: '«SPEIS»-gradientmerke (pub2), statisk',
  nato: 'ingen i arkivene, intet tilføyd',
  norwegianhedge: '«NORWEGIAN HEDGE»-gradientmerke (pub2), statisk',
  pubhealthcare: 'ingen i arkivene, intet tilføyd',
  govt_bergen: '«Bergens Selvstyreparti» satt plant i anleggets EB Garamond, uten gradient (kundens ønske, november 2026; pub2-gradientmerket er erstattet)',
};
const logoRows = PLANS.map(([k, t]) => `  <li>${t} — ${LOGOS[k]}</li>`).join('\n');

const html = `<!DOCTYPE html>
<html lang="no">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>bplans — syv forretningsplaner i pub4-anlegget</title>
<style>
${fontcss}
:root{
  --paper:#F7F2E9;
  --ink:#211C15;
  --ink-2:#5C5344;
  --hair:#D9CFBC;
  --accent:#7A3B2E;
}
body{
  margin:0;background:var(--paper);color:var(--ink);
  font-family:'EB Garamond',Georgia,serif;font-size:19px;line-height:1.5;
  font-kerning:normal;font-variant-numeric:oldstyle-nums proportional-nums;
  text-rendering:optimizeLegibility;
}
main{max-width:min(66ch,100% - 3rem);margin:0 auto;padding:4.5rem 0 3rem}
h1{font-size:2.4em;line-height:1.2;font-weight:600;margin:0 0 .75rem;hyphens:none}
.kicker{font-style:italic;color:var(--ink-2);font-size:.8em;margin:0 0 .5rem}
p{margin:0 0 .75em;text-align:justify;text-wrap:pretty;orphans:3;widows:3;hanging-punctuation:first;hyphens:auto}
ol{margin:0 0 .75em;padding-left:1.25em}
li{margin:.15em 0;text-wrap:pretty}
a{color:var(--ink);text-decoration:none;border-bottom:1px solid var(--hair)}
a:hover,a:focus-visible{color:var(--accent);border-bottom-color:var(--accent)}
.tag{font-style:italic;color:var(--ink-2);font-size:.85em}
h2{font-size:1.3em;font-weight:600;margin:2.5rem 0 .5rem}
footer{margin-top:4rem;padding-top:1.5rem;border-top:1px solid var(--hair);font-size:.8em;color:var(--ink-2)}
footer p{text-align:left;margin:0 0 .5em}
@media print{
  @page{size:156mm 234mm;margin:0}
  html{print-color-adjust:exact;-webkit-print-color-adjust:exact;background:var(--paper)}
  body{font-size:11.5pt;padding:16mm 15mm}
  a{color:inherit;text-decoration:none}
}
</style>
</head>
<body>
<main>
  <p class="kicker">bplans · pub4.anlegget · november 2026</p>
  <h1>Syv forretningsplaner</h1>
  <p>Gjenopprettet fra pub-, pub2- og pub3-arkivene og fullført til
  Innovasjon Norges vurderingskriterier. Søkt finansiering til sammen:
  NOK 2 400 000. Hvert konsept er ett selvbærende HTML-dokument og én PDF
  trykket av det samme dokumentet.</p>
  <ol>
${rows}
  </ol>
  <h2>Merker gjenopprettet</h2>
  <ul>
${logoRows}
  </ul>
  <footer>
    <p>Satt i EB Garamond — variabel skrift, innbakt i dokumentet · mål 66 tegn ·
    linjeavstand 1,5 · oldtall i løpende tekst, tabelltall i tabeller · titler i
    setningscase uten versaler · papir #F7F2E9 — etter Robert Bringhurst,
    The Elements of Typographic Style. EB Garamond utgis under SIL Open Font License.
    Tittelsidene og innholdslistene er redigert for tomrom og poise etter
    Bringhurst (s. 61) og Strunk &amp; White (17. regel), november 2026.</p>
    <p>Kilde: pub4.good/BPLANS · gjenopprettet og fullført november 2026.</p>
  </footer>
</main>
</body>
</html>
`;

writeFileSync(`${OUT}/index.html`, html);
console.log(`index.html written, ${html.length} chars, funding total ${total}`);
