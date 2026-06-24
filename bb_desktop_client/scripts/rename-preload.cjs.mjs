import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const compiled = path.join(root, 'dist/main/preload.js');
const target = path.join(root, 'dist/main/preload.cjs');

if (!fs.existsSync(compiled)) {
  console.error(`preload compile output missing: ${compiled}`);
  process.exit(1);
}

fs.renameSync(compiled, target);
console.log(`preload → ${path.relative(root, target)}`);
