import fs from 'node:fs';

const pkg = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const requiredScripts = ['dev', 'build', 'dist:win'];
const missing = requiredScripts.filter((name) => !pkg.scripts?.[name]);
if (missing.length) {
  console.error(`Missing scripts: ${missing.join(', ')}`);
  process.exit(1);
}
console.log('Biobase desktop client config OK');
