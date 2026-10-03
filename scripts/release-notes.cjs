const fs = require('fs');
const path = require('path');

function readChangelog(root = path.resolve(__dirname, '..')) {
  return fs.readFileSync(path.join(root, 'CHANGELOG.md'), 'utf8');
}

function extractReleaseNotes(notes, version) {
  const firstHeadingPattern = /^## Changes in `v[^`]+:`\s*$/mu;
  const firstHeading = notes.search(firstHeadingPattern);
  if (firstHeading < 0) {
    throw new Error('CHANGELOG.md has no release heading');
  }
  const currentHeading = `## Changes in \`v${version}:\``;
  const currentStart = notes.indexOf(currentHeading, firstHeading);
  if (currentStart < 0 || currentStart !== firstHeading) {
    throw new Error('CHANGELOG.md first release heading is not ' + currentHeading);
  }
  const afterCurrent = notes.slice(currentStart + currentHeading.length);
  const nextHeadingRelative = afterCurrent.search(/^## Changes in `v[^`]+:`\s*$/mu);
  const sectionEnd =
    nextHeadingRelative < 0
      ? notes.length
      : currentStart + currentHeading.length + nextHeadingRelative;
  const preamble = notes.slice(0, firstHeading).replace(/<!--[\s\S]*?-->/gu, '').trim();
  const currentSection = notes.slice(currentStart, sectionEnd).trim();
  return `${preamble}\n\n${currentSection}`.trim();
}

function readReleaseNotes(root = path.resolve(__dirname, '..'), version) {
  const changelog = readChangelog(root);
  if (!version) {
    try {
      version = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8')).version;
    } catch {
      version = undefined;
    }
  }
  return version ? extractReleaseNotes(changelog, version) : changelog.trim();
}

function validateReleaseNotes(notes, version, options = {}) {
  const visibleNotes = notes.replace(/<!--[\s\S]*?-->/g, '').trim();
  const failures = [];
  const expectedHeading = '## Changes in `v' + version + ':`';
  const firstHeadingIndex = visibleNotes.indexOf('## Changes in `v');
  const firstHeadingEnd =
    firstHeadingIndex < 0
      ? visibleNotes.length
      : visibleNotes.indexOf('\n## Changes in `v', firstHeadingIndex + 1);
  const currentRelease =
    firstHeadingIndex < 0
      ? ''
      : visibleNotes.slice(
          firstHeadingIndex,
          firstHeadingEnd < 0 ? visibleNotes.length : firstHeadingEnd,
        );
  const preamble = visibleNotes.slice(
    0,
    firstHeadingIndex < 0 ? visibleNotes.length : firstHeadingIndex,
  );
  const isPrerelease = version.includes('beta') || version.includes('alpha');

  if (isPrerelease && !visibleNotes.startsWith('> [!')) {
    failures.push('CHANGELOG.md must begin with a release notice');
  }
  if (!currentRelease.startsWith(expectedHeading)) {
    failures.push('first changelog heading must be ' + expectedHeading);
  }
  const currentBody = currentRelease
    .slice(expectedHeading.length)
    .replace(/<!--[\s\S]*?-->/gu, '')
    .trim();
  if (currentRelease.startsWith(expectedHeading) && !currentBody && !options.allowEmpty) {
    failures.push('current release notes must contain at least one entry');
  }
  if (!preamble.includes('/releases/download/v' + version + '/')) {
    failures.push('download table does not target v' + version);
  }
  if (!isPrerelease && /This is a Beta build/i.test(preamble)) {
    failures.push('stable release notes still contain the beta-build banner');
  }
  if (version === '0.11.1') {
    if (
      !preamble.includes('v0.11.0') ||
      !preamble.includes('Open release page') ||
      !/manually once/i.test(preamble)
    ) {
      failures.push('v0.11.1 notes must preserve the v0.11.0 manual-upgrade advisory');
    }
  }

  return failures;
}

function assertValidReleaseNotes(notes, version, options = {}) {
  const failures = validateReleaseNotes(notes, version, options);
  if (failures.length) {
    throw new Error('Invalid release notes:\n  - ' + failures.join('\n  - '));
  }
}

module.exports = {
  assertValidReleaseNotes,
  extractReleaseNotes,
  readChangelog,
  readReleaseNotes,
  validateReleaseNotes,
};
