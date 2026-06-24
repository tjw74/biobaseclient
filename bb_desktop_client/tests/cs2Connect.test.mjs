import test from 'node:test';
import assert from 'node:assert/strict';
import {
  BIOBASE_CS2_HOST,
  DEFAULT_CONNECT,
  DEFAULT_CS2_GAME_PORT,
  buildSteamConnectUrl,
  connectInfoFromHostPort,
} from '../dist/shared/biobaseEndpoints.js';

const EXPECTED_STEAM_URL = 'steam://run/730/-windowed%20-noborder//+connect%20cs2.clarionlab.dev:27015';

test('buildSteamConnectUrl uses steam run protocol with windowed connect launch option', () => {
  assert.equal(buildSteamConnectUrl(BIOBASE_CS2_HOST, DEFAULT_CS2_GAME_PORT), EXPECTED_STEAM_URL);
});

test('connectInfoFromHostPort builds console and steamUrl', () => {
  assert.deepEqual(connectInfoFromHostPort('example.test', 27016), {
    host: 'example.test',
    port: 27016,
    console: 'connect example.test:27016',
    steamUrl: 'steam://run/730/-windowed%20-noborder//+connect%20example.test:27016',
  });
});

test('DEFAULT_CONNECT matches Biobase server endpoint', () => {
  assert.equal(DEFAULT_CONNECT.console, 'connect cs2.clarionlab.dev:27015');
  assert.equal(DEFAULT_CONNECT.steamUrl, EXPECTED_STEAM_URL);
});

test('buildSteamConnectUrl rejects invalid targets', () => {
  assert.throws(() => buildSteamConnectUrl('', 27015), /invalid_connect_target/);
  assert.throws(() => buildSteamConnectUrl('host', 0), /invalid_connect_target/);
});
