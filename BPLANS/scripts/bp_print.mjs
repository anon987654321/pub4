// Print the completed BPLANS HTMLs to PDF with the Playwright Chromium
// headless shell (invoked as a binary; no Python). The @page rule in each
// document (156mm 234mm) determines the page size, as in the pub4 anlage.
// Usage: node scripts/bp_print.mjs
import { spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';

const OUT = '/home/z/my-project/download/pub4.good/BPLANS';
const ORDER = ['syre', 'speis', 'ragnhild', 'nato', 'norwegianhedge', 'pubhealthcare', 'govt_bergen'];
const CHROME = '/home/z/.cache/ms-playwright/chromium_headless_shell-1200/chrome-headless-shell-linux64/chrome-headless-shell';

if (!existsSync(CHROME)) throw new Error('chromium headless shell not found at ' + CHROME);

for (const name of ORDER) {
  const src = `file://${OUT}/${name}.html`;
  const pdf = `${OUT}/${name}.pdf`;
  const r = spawnSync(CHROME, [
    '--headless', '--disable-gpu', '--no-sandbox',
    '--no-pdf-header-footer', '--virtual-time-budget=20000',
    `--print-to-pdf=${pdf}`, src,
  ], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`${name}: chromium exited ${r.status}\n${r.stderr}`);
  const info = spawnSync('pdfinfo', [pdf], { encoding: 'utf8' }).stdout;
  const size = (info.match(/Page size:\s*([\d.]+ x [\d.]+) pts/) || [])[1];
  const pages = (info.match(/Pages:\s*(\d+)/) || [])[1];
  const bytes = statSync(pdf).size;
  console.log(`${name}: ${bytes} bytes, ${pages} pages, ${size} pts`);
  if (size !== '442.08 x 663.12') throw new Error(`${name}: unexpected page size ${size}`);
}
console.log('done');
