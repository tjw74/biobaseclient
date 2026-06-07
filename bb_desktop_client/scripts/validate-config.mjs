import fs from 'node:fs';

const pkg = JSON.parse(fs.readFileSync(new URL('../package.json', import.meta.url), 'utf8'));
const requiredScripts = ['dev', 'build', 'dist:win', 'dist:win:installer:unsigned', 'typecheck', 'test'];
const missing = requiredScripts.filter((name) => !pkg.scripts?.[name]);
if (missing.length) {
  console.error(`Missing scripts: ${missing.join(', ')}`);
  process.exit(1);
}

const build = pkg.build ?? {};
const winTargets = build.win?.target ?? [];
if (!Array.isArray(winTargets) || winTargets.length !== 1 || winTargets[0] !== 'nsis') {
  console.error('Windows build must target exactly one NSIS installer');
  process.exit(1);
}
if (build.win?.artifactName) {
  console.error('Use top-level build.artifactName only; win.artifactName can override the setup filename');
  process.exit(1);
}
if (build.artifactName !== 'Biobase-Client-Setup-${version}-${arch}.${ext}') {
  console.error('Unexpected installer artifactName');
  process.exit(1);
}

const workflow = fs.readFileSync(new URL('../.github/workflows/windows_build.yml', import.meta.url), 'utf8');
for (const expected of [
  'contents: write',
  "node-version: '22'",
  'gh release create latest',
  'gh release upload latest',
  'Biobase-Client-Setup.exe',
]) {
  if (!workflow.includes(expected)) {
    console.error(`Windows workflow missing: ${expected}`);
    process.exit(1);
  }
}

console.log('Biobase desktop client config OK');
