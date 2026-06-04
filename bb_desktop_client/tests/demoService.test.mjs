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
