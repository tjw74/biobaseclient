import assert from 'node:assert/strict';
import test from 'node:test';
import {
  canInitiateOverlay,
  clampOverlaySize,
  isOverlayEnvForceEnabled,
  isOverlayFeatureDisabled,
  isOverlayKillSwitchActive,
  overlayBoundsForWorkArea,
  OVERLAY_MAX_HEIGHT,
  OVERLAY_MAX_WIDTH,
  setOverlayUserOptedIn,
} from '../dist/main/overlaySafety.js';

test('isOverlayKillSwitchActive respects BIOBASE_DISABLE_OVERLAY', () => {
  const prev = process.env.BIOBASE_DISABLE_OVERLAY;
  try {
    delete process.env.BIOBASE_DISABLE_OVERLAY;
    assert.equal(isOverlayKillSwitchActive(), false);
    process.env.BIOBASE_DISABLE_OVERLAY = '1';
    assert.equal(isOverlayKillSwitchActive(), true);
  } finally {
    if (prev === undefined) delete process.env.BIOBASE_DISABLE_OVERLAY;
    else process.env.BIOBASE_DISABLE_OVERLAY = prev;
  }
});

test('isOverlayFeatureDisabled is true by default until opt-in', () => {
  const prevDisable = process.env.BIOBASE_DISABLE_OVERLAY;
  const prevEnable = process.env.BIOBASE_ENABLE_OVERLAY;
  try {
    delete process.env.BIOBASE_DISABLE_OVERLAY;
    delete process.env.BIOBASE_ENABLE_OVERLAY;
    setOverlayUserOptedIn(false);
    assert.equal(isOverlayFeatureDisabled(), true);
    setOverlayUserOptedIn(true);
    assert.equal(isOverlayFeatureDisabled(), false);
    process.env.BIOBASE_ENABLE_OVERLAY = '1';
    setOverlayUserOptedIn(false);
    assert.equal(isOverlayFeatureDisabled(), false);
    assert.equal(isOverlayEnvForceEnabled(), true);
    assert.equal(canInitiateOverlay(), true);
    process.env.BIOBASE_DISABLE_OVERLAY = '1';
    assert.equal(canInitiateOverlay(), false);
  } finally {
    if (prevDisable === undefined) delete process.env.BIOBASE_DISABLE_OVERLAY;
    else process.env.BIOBASE_DISABLE_OVERLAY = prevDisable;
    if (prevEnable === undefined) delete process.env.BIOBASE_ENABLE_OVERLAY;
    else process.env.BIOBASE_ENABLE_OVERLAY = prevEnable;
    setOverlayUserOptedIn(false);
  }
});

test('clampOverlaySize enforces max dimensions', () => {
  assert.deepEqual(clampOverlaySize(999, 999), { width: OVERLAY_MAX_WIDTH, height: OVERLAY_MAX_HEIGHT });
  assert.deepEqual(clampOverlaySize(420, 220), { width: 420, height: 220 });
});

test('overlayBoundsForWorkArea stays inside workArea and below max size', () => {
  const workArea = { x: 0, y: 0, width: 1920, height: 1040 };
  const bounds = overlayBoundsForWorkArea(workArea);
  assert.ok(bounds.width <= OVERLAY_MAX_WIDTH);
  assert.ok(bounds.height <= OVERLAY_MAX_HEIGHT);
  assert.ok(bounds.width < workArea.width);
  assert.ok(bounds.height < workArea.height);
  assert.ok(bounds.x >= workArea.x);
  assert.ok(bounds.y >= workArea.y);
  assert.ok(bounds.x + bounds.width <= workArea.x + workArea.width);
  assert.ok(bounds.y + bounds.height <= workArea.y + workArea.height);
});

test('isWindowOnCurrentVirtualDesktop is permissive off Windows', async () => {
  const { isWindowOnCurrentVirtualDesktop } = await import('../dist/main/windowsDesktopIsolation.js');
  assert.equal(isWindowOnCurrentVirtualDesktop(0), true);
  assert.equal(isWindowOnCurrentVirtualDesktop(12345), true);
});
