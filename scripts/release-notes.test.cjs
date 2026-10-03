const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const { validateReleaseNotes } = require('./release-notes.cjs');
const packageJson = require('../package.json');

function coreVersion(version) {
  return String(version).split('+')[0].split('-')[0];
}

const stable = coreVersion(packageJson.version);
const prerelease = `${stable}-beta.1`;
const stalePrerelease = `${stable}-beta.2`;

function notesFor(version, notice = '> [!NOTE]\n> Release notice') {
  const lines = [];
  if (notice) {
    lines.push(notice, '');
  }
  lines.push(
    'https://github.com/BurntToasters/Dacx/releases/download/v' +
      version +
      '/Dacx-Windows-x64.msi',
    '',
    '## Changes in `v' + version + ':`',
    '',
    '- Fix.',
    '',
    '## Changes in `v0.1.0:`',
  );
  return lines.join('\n');
}

test('accepts notes whose first release and downloads match the package version', () => {
  assert.deepEqual(validateReleaseNotes(notesFor(stable), stable), []);
});

test('stable notes do not require a leading release notice', () => {
  const notes = [
    '<!-- > [!NOTE]',
    '> This is a Beta build. -->',
    notesFor(stable, ''),
  ].join('\n');
  assert.deepEqual(validateReleaseNotes(notes, stable), []);
});

test('prerelease notes require a leading release notice', () => {
  const failures = validateReleaseNotes(notesFor(prerelease, ''), prerelease);
  assert.equal(failures.some((failure) => failure.includes('release notice')), true);
});

test('rejects stale release headings and download links', () => {
  const failures = validateReleaseNotes(notesFor(stalePrerelease), stable);
  assert.equal(failures.some((failure) => failure.includes('first changelog heading')), true);
  assert.equal(failures.some((failure) => failure.includes('download table')), true);
});

test('rejects a beta banner for stable release notes', () => {
  const failures = validateReleaseNotes(
    notesFor(stable, '> [!NOTE]\n> This is a Beta build.'),
    stable,
  );
  assert.equal(failures.some((failure) => failure.includes('beta-build banner')), true);
});

test('ignores a historical beta banner inside an HTML comment', () => {
  const notes = [
    '<!-- > [!NOTE]',
    '> This is a Beta build. -->',
    notesFor(stable, '> [!IMPORTANT]\n> Stable release'),
  ].join('\n');
  assert.deepEqual(validateReleaseNotes(notes, stable), []);
});

test('requires the one-time v0.11.0 recovery advisory in v0.11.1 notes', () => {
  const failures = validateReleaseNotes(notesFor('0.11.1'), '0.11.1');
  assert.equal(failures.some((failure) => failure.includes('manual-upgrade advisory')), true);
});

test('current CHANGELOG.md matches the package version', () => {
  const notes = fs.readFileSync(
    path.join(__dirname, '..', 'CHANGELOG.md'),
    'utf8',
  );
  assert.deepEqual(validateReleaseNotes(notes, packageJson.version, { allowEmpty: true }), []);
});
