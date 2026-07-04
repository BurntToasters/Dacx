#!/usr/bin/env node
/**
 * Verifies that package.json, pubspec.yaml, and the AppStream metainfo
 * agree on the current version. Run as part of `npm run test:all` so a
 * forgotten `npm run sync-version` cannot ship.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

function readText(rel) {
  return fs.readFileSync(path.join(root, rel), "utf8");
}

const failures = [];

const pkg = JSON.parse(readText("package.json"));
const pkgVersion = pkg.version;
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(pkgVersion ?? "")) {
  failures.push(`package.json version invalid: "${pkgVersion}"`);
}

function semverToDebianVersion(semver) {
  return semver.split("+")[0].replace("-", "~");
}

const pubspec = readText("pubspec.yaml");
const pubMatch = pubspec.match(
  /^version:\s*(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)\+(\d+)\s*$/m,
);
if (!pubMatch) {
  failures.push("pubspec.yaml version line not found or malformed");
} else {
  const [, pubVersion, buildNumber] = pubMatch;
  if (pubVersion !== pkgVersion) {
    failures.push(
      `version drift: package.json=${pkgVersion} pubspec.yaml=${pubVersion}`,
    );
  }
  const [maj, min, pat] = pkgVersion
    .replace(/-.*$/, "")
    .split(".")
    .map(Number);
  const expectedBuild = String(maj * 10_000 + min * 100 + pat);
  if (buildNumber !== expectedBuild) {
    failures.push(
      `pubspec build number ${buildNumber} != expected ${expectedBuild}`,
    );
  }
}

const metainfoPath = "run.rosie.dacx.metainfo.xml";
if (fs.existsSync(path.join(root, metainfoPath))) {
  const meta = readText(metainfoPath);
  if (!meta.includes(`version="${pkgVersion}"`)) {
    failures.push(
      `${metainfoPath} has no <release version="${pkgVersion}"> entry`,
    );
  }
}

function checkLinuxPackageTemplate(rel) {
  if (!fs.existsSync(path.join(root, rel))) return;
  const text = readText(rel);
  const match = text.match(
    /^Version:\s*(\d+\.\d+\.\d+(?:[-~][0-9A-Za-z.-]+)?)\s*$/m,
  );
  if (!match) {
    failures.push(`${rel} Version line not found or malformed`);
    return;
  }
  const [, templateVersion] = match;
  const expectedVersion = semverToDebianVersion(pkgVersion);
  if (templateVersion !== expectedVersion) {
    failures.push(
      `version drift: package.json=${pkgVersion} ${rel}=${templateVersion} expected ${expectedVersion}`,
    );
  }
}

checkLinuxPackageTemplate("linux/packaging/control.template");

if (failures.length) {
  console.error("Version sync FAILED:");
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`Version sync OK (${pkgVersion}).`);
