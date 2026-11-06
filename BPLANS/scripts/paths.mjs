// Shared paths for the standalone BPLANS build tools.
// Source stays in the repository; generated HTML/PDF files default to the
// operating system's temporary directory and can be redirected explicitly.
import { dirname, resolve } from 'node:path';
import { tmpdir } from 'node:os';
import { fileURLToPath } from 'node:url';

export const BPLANS_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), '..');
export const SOURCE_DIR = resolve(process.env.BPLANS_SOURCE_DIR || BPLANS_ROOT);
export const OUTPUT_DIR = resolve(
  process.env.BPLANS_OUT_DIR || resolve(tmpdir(), 'pub4-good-BPLANS'),
);
