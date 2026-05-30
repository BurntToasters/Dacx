function parseSemver(version) {
  const match = version.match(/^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/);
  if (!match) return null;
  return {
    major: Number(match[1]),
    minor: Number(match[2]),
    patch: Number(match[3]),
    prerelease: match[4] ? match[4].split(".") : [],
  };
}

function comparePrerelease(aParts, bParts) {
  for (let i = 0; i < Math.max(aParts.length, bParts.length); i++) {
    const a = aParts[i];
    const b = bParts[i];
    if (a === undefined) return -1;
    if (b === undefined) return 1;
    if (a === b) continue;

    const aNumeric = /^\d+$/.test(a);
    const bNumeric = /^\d+$/.test(b);
    if (aNumeric && bNumeric) return Number(a) - Number(b);
    if (aNumeric) return -1;
    if (bNumeric) return 1;
    return a.localeCompare(b);
  }
  return 0;
}

function compareSemverDescending(a, b) {
  const va = parseSemver(a);
  const vb = parseSemver(b);
  if (!va || !vb) return b.localeCompare(a);

  for (const key of ["major", "minor", "patch"]) {
    if (va[key] !== vb[key]) return vb[key] - va[key];
  }

  const aPrerelease = va.prerelease.length > 0;
  const bPrerelease = vb.prerelease.length > 0;
  if (!aPrerelease && bPrerelease) return -1;
  if (aPrerelease && !bPrerelease) return 1;
  if (!aPrerelease && !bPrerelease) return 0;
  return -comparePrerelease(va.prerelease, vb.prerelease);
}

export { compareSemverDescending };
