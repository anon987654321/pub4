// Convert the retired bp_content_a.py / bp_content_b.py content files to
// ES modules. The .py files are parsed as TEXT (no Python is run), which
// keeps laws.yml REACH_non_native_tool satisfied: python is on the banned
// list and this tree must not invoke it, only preserve its data.
// Usage: node scripts/convert_content.mjs
import { existsSync, readFileSync, writeFileSync } from 'node:fs';
import { basename, resolve } from 'node:path';
import { BPLANS_ROOT } from './paths.mjs';

const LEGACY_DIR = resolve(
  process.env.BPLANS_LEGACY_SOURCE_DIR || resolve(BPLANS_ROOT, 'scripts', 'legacy'),
);
const OUTPUT_DIR = resolve(BPLANS_ROOT, 'scripts');
const SRC = [
  [resolve(LEGACY_DIR, 'bp_content_a.py'), 'PLANS_A'],
  [resolve(LEGACY_DIR, 'bp_content_b.py'), 'PLANS_B'],
];

for (const [path, name] of SRC) {
  if (!existsSync(path)) {
    throw new Error(`archived content source not found: ${path}; set BPLANS_LEGACY_SOURCE_DIR or skip this one-time conversion (plans_a.mjs and plans_b.mjs are already committed)`);
  }
  const text = readFileSync(path, 'utf8');
  const starts = [];
  const headRe = new RegExp(`^${name}\\['(\\w+)'\\]\\s*=\\s*\\{`, 'gm');
  let m;
  while ((m = headRe.exec(text)) !== null) starts.push({ key: m[1], at: m.index + m[0].length });
  if (starts.length === 0) throw new Error(`no plans found in ${path}`);

  const plans = {};
  starts.forEach((s, i) => {
    const end = i + 1 < starts.length
      ? text.lastIndexOf('}', starts[i + 1].at)
      : text.length;
    const body = text.slice(s.at, end);
    const fields = {};
    // block fields written as 'field': """ ... """
    const blockRe = /'(\w+)':\s*"""(.*?)"""/gs;
    for (const bm of body.matchAll(blockRe)) fields[bm[1]] = bm[2];
    // logo: None
    if (/'logo':\s*None/.test(body)) fields.logo = null;
    // logo dict: 'logo': { 'kind': '...', ... }
    const logoM = body.match(/'logo':\s*\{([^}]*)\}/s);
    if (logoM && !/'logo':\s*None/.test(body)) {
      const logo = {};
      for (const lm of logoM[1].matchAll(/'(\w+)':\s*'([^']*)'/g)) logo[lm[1]] = lm[2];
      fields.logo = logo;
    }
    // empty tech_extra
    if (fields.tech_extra === undefined && /'tech_extra':\s*''/.test(body)) fields.tech_extra = '';
    for (const req of ['why_now', 'kundeinnsikt', 'gomarket', 'unit', 'milestones',
      'resultat', 'likviditet', 'risiko', 'ekstern']) {
      if (fields[req] === undefined) throw new Error(`${name}.${s.key}: missing ${req}`);
    }
    if (fields.tech_extra === undefined) throw new Error(`${name}.${s.key}: missing tech_extra`);
    plans[s.key] = fields;
  });

  // JS-literal safety: the port emits template literals.
  for (const [key, fields] of Object.entries(plans)) {
    for (const [f, v] of Object.entries(fields)) {
      const s = typeof v === 'string' ? v : JSON.stringify(v);
      if (s.includes('`') || s.includes('${')) {
        throw new Error(`${name}.${key}.${f}: backtick or template marker in content`);
      }
    }
  }

  const emit = (obj, varName) => {
    const body = Object.entries(obj).map(([k, v]) => {
      const inner = Object.entries(v).map(([f, val]) => {
        if (val === null) return `    ${f}: null,`;
        if (typeof val === 'string') return `    ${f}: \`\n${val}\`,`;
        const json = JSON.stringify(val).replace(/"(\w+)":/g, '$1: ').replace(/,/g, ', ');
        return `    ${f}: ${json},`;
      }).join('\n');
      return `  ${k}: {\n${inner}\n  },`;
    }).join('\n');
    return `// Ported from ${basename(path)} (data only, parsed as text).\n` +
      `export const ${varName} = {\n${body}\n};\n`;
  };

  const out = resolve(OUTPUT_DIR, `${name.toLowerCase()}.mjs`);
  writeFileSync(out, emit(plans, name));
  console.log(`${out}: ${Object.keys(plans).length} plans (${Object.keys(plans).join(', ')})`);
}
