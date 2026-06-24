import assert from 'node:assert/strict';
import test from 'node:test';
import { formatVersionClickFeedback } from '../dist/shared/updateFeedback.js';

test('version click says explicitly when already latest', () => {
  assert.equal(
    formatVersionClickFeedback({ currentVersion: '0.1.50', state: 'not-available', latestVersion: '0.1.50' }),
    'Latest: v0.1.50 installed'
  );
});

test('version click explains active update states without inference', () => {
  assert.equal(
    formatVersionClickFeedback({ currentVersion: '0.1.50', state: 'checking', message: 'Checking for updates…' }),
    'Checking for updates…'
  );
  assert.equal(
    formatVersionClickFeedback({ currentVersion: '0.1.50', state: 'ready', latestVersion: '0.1.51' }),
    'Update ready: v0.1.51 — restart to apply'
  );
});

test('version click keeps error visible', () => {
  assert.equal(
    formatVersionClickFeedback({ currentVersion: '0.1.50', state: 'error', message: 'Could not reach update feed' }),
    'Update check failed: Could not reach update feed'
  );
});
