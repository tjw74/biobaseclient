import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const source = path.join(root, 'src/main/watchdog.cjs');
const target = path.join(root, 'dist/main/watchdog.cjs');

if (!fs.existsSync(source)) {
  console.error(`watchdog source missing: ${source}`);
  process.exit(1);
}

fs.mkdirSync(path.dirname(target), { recursive: true });
fs.copyFileSync(source, target);
console.log(`watchdog → ${path.relative(root, target)}`);
