const SEMVER = /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/;

const PRERELEASE_SLOTS = {
  beta: { offset: 0, max: 59 },
  rc: { offset: 60, max: 38 },
};

function isPrereleaseVersion(version) {
  const match = String(version ?? '').match(SEMVER);
  return Boolean(match && match[4]);
}

function toMsiVersion(version) {
  const match = String(version).match(SEMVER);
  if (!match) {
    throw new Error(
      `Cannot convert version "${version}" to MSI version. Expected semver like 1.2.3, 1.2.3-beta.4 or 1.2.3-rc.1`,
    );
  }
  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = Number(match[3]);
  const prerelease = match[4];

  if (patch > 654) {
    throw new Error(
      `Patch ${patch} exceeds 654; MSI build field would overflow (max 65535).`,
    );
  }

  if (!prerelease) {
    return `${major}.${minor}.${patch * 100 + 99}`;
  }

  const tagMatch = prerelease.match(/^(beta|rc)\.(\d+)$/);
  if (!tagMatch) {
    throw new Error(
      `Cannot encode prerelease "${prerelease}"; only beta.N or rc.N is supported (e.g. beta.5, rc.1).`,
    );
  }
  const slot = PRERELEASE_SLOTS[tagMatch[1]];
  const n = Number(tagMatch[2]);
  if (n < 1 || n > slot.max) {
    throw new Error(
      `${tagMatch[1]} counter ${n} out of range (1..${slot.max}). Bump patch and reset.`,
    );
  }
  return `${major}.${minor}.${patch * 100 + slot.offset + n}`;
}

module.exports = { isPrereleaseVersion, toMsiVersion };
