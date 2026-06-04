import test from 'node:test';
import assert from 'node:assert/strict';
import { buildApiUrl, createAuthHeaders, sanitizeDeviceName } from '../dist/shared/apiClient.js';

test('buildApiUrl normalizes base URL and joins endpoint', () => {
  assert.equal(buildApiUrl('https://biobase.live/', '/api/client/device/pair'), 'https://biobase.live/api/client/device/pair');
});

test('buildApiUrl rejects malformed and non-http API URLs', () => {
  assert.throws(() => buildApiUrl('file:///tmp/x', '/api/client/sessions'), /invalid_api_base_url/);
  assert.throws(() => buildApiUrl('not a url', '/api/client/sessions'), /invalid_api_base_url/);
});

test('createAuthHeaders omits empty device credentials', () => {
  assert.deepEqual(createAuthHeaders({ deviceId: 'dev_123', deviceToken: 'tok_abc' }), {
    'X-Biobase-Device-Id': 'dev_123',
    'X-Biobase-Device-Token': 'tok_abc',
  });
  assert.deepEqual(createAuthHeaders({ deviceId: '', deviceToken: '' }), {});
});

test('sanitizeDeviceName strips unsupported characters', () => {
  assert.equal(sanitizeDeviceName('  My Gaming PC 🚀  '), 'My Gaming PC');
  assert.equal(sanitizeDeviceName(''), 'Biobase Client');
});
