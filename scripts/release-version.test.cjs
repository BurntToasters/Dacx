const assert = require('node:assert/strict');
const test = require('node:test');

const { isPrereleaseVersion, toMsiVersion } = require('./release-version.cjs');

test('every semver prerelease counts as a prerelease, stable does not', () => {
  for (const version of ['1.0.0-beta.1', '1.0.0-rc.1', '1.0.0-alpha.2', '2.1.0-rc.10']) {
    assert.equal(isPrereleaseVersion(version), true, version);
  }
  for (const version of ['1.0.0', '0.9.5', '10.20.30']) {
    assert.equal(isPrereleaseVersion(version), false, version);
  }
});

test('existing beta MSI encodings do not change', () => {
  assert.equal(toMsiVersion('1.0.0-beta.1'), '1.0.1');
  assert.equal(toMsiVersion('1.0.0-beta.2'), '1.0.2');
  assert.equal(toMsiVersion('0.9.5'), '0.9.599');
  assert.equal(toMsiVersion('1.0.0'), '1.0.99');
  assert.equal(toMsiVersion('1.0.1'), '1.0.199');
});

test('rc sorts after every beta and before stable', () => {
  const field = (v) => Number(toMsiVersion(v).split('.')[2]);
  assert.ok(field('1.0.0-rc.1') > field('1.0.0-beta.59'));
  assert.ok(field('1.0.0-rc.38') < field('1.0.0'));
  assert.ok(field('1.0.0-rc.2') > field('1.0.0-rc.1'));
});

test('unsupported or out-of-range prereleases fail loudly', () => {
  assert.throws(() => toMsiVersion('1.0.0-beta.60'), /out of range/);
  assert.throws(() => toMsiVersion('1.0.0-rc.39'), /out of range/);
  assert.throws(() => toMsiVersion('1.0.0-alpha.1'), /beta\.N or rc\.N/);
  assert.throws(() => toMsiVersion('1.0.655'), /exceeds 654/);
});
