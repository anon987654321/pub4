// Print the completed BPLANS HTMLs to PDF with the Playwright Chromium
// headless shell (invoked as a binary; no Python). The @page rule in each
// document (156mm 234mm) determines the page size, as in the pub4 anlage.
// Usage: node scripts/bp_print.mjs
import { spawnSync } from 'node:child_process';
import { existsSync, statSync } from 'node:fs';
import { OUTPUT_DIR as OUT } from './paths.mjs';

const ORDER = ['syre', 'speis', 'ragnhild', 'nato', 'norwegianhedge', 'pubhealthcare', 'govt_bergen'];
const CHROME_CANDIDATES = [
  process.env.BPLANS_CHROME_BIN,
  process.env.CHROME_BIN,
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
  '/Applications/Chromium.app/Contents/MacOS/Chromium',
  'chrome-headless-shell',
  'chromium',
  'chromium-browser',
  'google-chrome',
  'google-chrome-stable',
].filter(Boolean);

function available(command) {
  if (command.includes('/') || command.includes('\\')) return existsSync(command);
  return spawnSync('which', [command], { stdio: 'ignore' }).status === 0;
}

const CHROME = CHROME_CANDIDATES.find(available);
if (!CHROME) {
  throw new Error('Chromium/Chrome not found; set BPLANS_CHROME_BIN to its executable path.');
}

for (const name of ORDER) {
  const src = `file://${OUT}/${name}.html`;
  const pdf = `${OUT}/${name}.pdf`;
  const r = spawnSync(CHROME, [
    '--headless', '--disable-gpu', '--no-sandbox',
    '--no-pdf-header-footer', '--virtual-time-budget=20000',
    `--print-to-pdf=${pdf}`, src,
  ], { encoding: 'utf8' });
  if (r.status !== 0) throw new Error(`${name}: chromium exited ${r.status}\n${r.stderr}`);
  const pdfinfo = process.env.PDFINFO_BIN || 'pdfinfo';
  const infoResult = spawnSync(pdfinfo, [pdf], { encoding: 'utf8' });
  if (infoResult.error || infoResult.status !== 0) {
    throw new Error(`pdfinfo failed for ${pdf}: ${infoResult.error?.message || infoResult.stderr}`);
  }
  const info = infoResult.stdout || '';
  const size = (info.match(/Page size:\s*([\d.]+ x [\d.]+) pts/) || [])[1];
  const pages = (info.match(/Pages:\s*(\d+)/) || [])[1];
  const bytes = statSync(pdf).size;
  console.log(`${name}: ${bytes} bytes, ${pages} pages, ${size} pts`);
  if (size !== '442.08 x 663.12') throw new Error(`${name}: unexpected page size ${size}`);
}
console.log('done');
