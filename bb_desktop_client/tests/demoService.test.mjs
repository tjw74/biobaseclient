import test from 'node:test';
import assert from 'node:assert/strict';
import { isLikelyDemoPath, safeDemoStem } from '../dist/main/demoService.js';

test('isLikelyDemoPath accepts case-insensitive .dem paths only', () => {
  assert.equal(isLikelyDemoPath('C:/Steam/match.DEM'), true);
  assert.equal(isLikelyDemoPath('C:/Steam/match.dem'), true);
  assert.equal(isLikelyDemoPath('C:/Steam/match.dem.exe'), false);
});

test('safeDemoStem sanitizes imported demo names', () => {
  assert.equal(safeDemoStem('C:/tmp/../awful name!!.dem'), 'awful_name__');
});

import { scanRootsForPlatform } from '../dist/main/scanRoots.js';

test('scanRootsForPlatform includes macOS Steam CS2 paths', () => {
  const roots = scanRootsForPlatform('darwin', '/Users/tester');
  assert.ok(roots.some((p) => p.includes('Library/Application Support/Steam')));
  assert.ok(roots.some((p) => p.endsWith('Counter-Strike Global Offensive/game/csgo')));
  assert.ok(roots.some((p) => p.endsWith('replays')));
});

test('scanRootsForPlatform includes Windows Steam CS2 paths', () => {
  const roots = scanRootsForPlatform('win32', 'C:/Users/tester', {
    'PROGRAMFILES(X86)': 'D:/Steam86',
    PROGRAMFILES: 'D:/Steam',
  });
  assert.ok(roots.some((p) => p.includes('D:/Steam86')));
});
