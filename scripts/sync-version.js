#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { compareSemverDescending, semverToDebianVersion } from "./semver-sort.js";

const defaultRoot = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const REQUIRED_FILES = [
  "package-lock.json",
  "pubspec.yaml",
  "run.rosie.dacx.metainfo.xml",
  "flatpak/run.rosie.dacx.yaml",
  "linux/packaging/control.template",
  "CHANGELOG.md",
];
const BETA_NOTICE = "> [!NOTE]\n> 🅱️ This is a Beta build.";
const COMMENTED_BETA_NOTICE = `<!-- ${BETA_NOTICE} -->`;
const BETA_NOTICE_PATTERN =
  /^(?:<!--\s*> \[!NOTE\]\r?\n> 🅱️ This is a Beta build\.\s*-->|> \[!NOTE\]\r?\n> 🅱️ This is a Beta build\.)\s*/u;

function parseArgs(argv) {
  const rootIndex = argv.indexOf("--root");
  if (rootIndex < 0) return defaultRoot;
  const supplied = argv[rootIndex + 1];
  if (!supplied || supplied.startsWith("--")) {
    throw new Error("--root requires a directory path");
  }
  return path.resolve(supplied);
}

function isPrerelease(version) {
  return /-(?:alpha|beta)(?:[.-]?\d+)?$/iu.test(version);
}

function lineEnding(text) {
  return text.includes("\r\n") ? "\r\n" : "\n";
}

function updatePackageLock(text, version, failures, label) {
  let lock;
  try {
    lock = JSON.parse(text);
  } catch (error) {
    failures.push(`${label}: invalid JSON (${error.message})`);
    return null;
  }
  if (!lock || typeof lock !== "object" || !lock.packages || !lock.packages[""]) {
    failures.push(`${label}: root package entry not found`);
    return null;
  }
  lock.version = version;
  lock.packages[""].version = version;
  const eol = lineEnding(text);
  return `${JSON.stringify(lock, null, 2).replaceAll("\n", eol)}${eol}`;
}

function updatePubspec(text, version, failures) {
  const versionPattern = /^(version:\s*)(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+(\d+))?/mu;
  const match = text.match(versionPattern);
  if (!match) {
    failures.push("pubspec.yaml: version line not found");
    return null;
  }
  const [major, minor, patch] = version.replace(/-.*$/u, "").split(".").map(Number);
  const buildNumber = String(major * 10_000 + minor * 100 + patch);
  return text.replace(versionPattern, `${match[1]}${version}+${buildNumber}`);
}

function updateMetainfo(text, version, failures) {
  const metaVersion = semverToDebianVersion(version);
  const eol = lineEnding(text);
  const releasesLineMatch = text.match(/^([ \t]*)<releases>[ \t]*$/mu);
  if (!releasesLineMatch) {
    failures.push("run.rosie.dacx.metainfo.xml: <releases> block not found");
    return null;
  }
  const releasesSectionRegex = /<releases>[\s\S]*?<\/releases>/u;
  const releasesSectionMatch = text.match(releasesSectionRegex);
  if (!releasesSectionMatch) {
    failures.push("run.rosie.dacx.metainfo.xml: malformed <releases> block");
    return null;
  }
  const baseIndent = releasesLineMatch[1] || "";
  const releaseIndent = `${baseIndent}  `;
  const today = new Date().toISOString().slice(0, 10);
  const releaseTagRegex = /<release\b[^>]*\/>|<release\b[^>]*>[\s\S]*?<\/release>/gu;
  const releaseVersionRegex = /version="([^"]+)"/u;
  const existingReleaseTags = releasesSectionMatch[0].match(releaseTagRegex) || [];
  const rebuiltEntries = [];
  let replacedCurrentVersion = false;

  for (const rawTag of existingReleaseTags) {
    const tag = rawTag.trim().replace(
      /version="([^"]+)"/u,
      (_, tagVersion) => `version="${semverToDebianVersion(tagVersion)}"`,
    );
    const tagVersion = tag.match(releaseVersionRegex)?.[1] || "";
    if (semverToDebianVersion(tagVersion) === metaVersion) {
      if (!replacedCurrentVersion) {
        const refreshed = tag.includes("</release>")
          ? tag.replace(/\bdate="[^"]*"/u, `date="${today}"`)
          : `<release version="${metaVersion}" date="${today}"/>`;
        rebuiltEntries.push(refreshed);
        replacedCurrentVersion = true;
      }
      continue;
    }
    rebuiltEntries.push(tag);
  }

  if (!replacedCurrentVersion) {
    rebuiltEntries.unshift(`<release version="${metaVersion}" date="${today}"/>`);
  }
  rebuiltEntries.sort((a, b) => {
    const aVersion = a.match(releaseVersionRegex)?.[1] || "";
    const bVersion = b.match(releaseVersionRegex)?.[1] || "";
    return compareSemverDescending(aVersion, bVersion);
  });
  const updatedSection = `<releases>${eol}${rebuiltEntries
    .map((tag) => `${releaseIndent}${tag}`)
    .join(eol)}${eol}${baseIndent}</releases>`;
  return text.replace(releasesSectionRegex, updatedSection);
}

function updateFlatpak(text, version, failures) {
  const tag = `# x-version: ${version}`;
  if (/^# x-version:/mu.test(text)) {
    return text.replace(/^# x-version:.*$/mu, tag);
  }
  if (!text) {
    failures.push("flatpak/run.rosie.dacx.yaml: manifest is empty");
    return null;
  }
  return `${tag}${lineEnding(text)}${text}`;
}

function updateLinuxPackageTemplate(text, version, failures) {
  const versionPattern =
    /^(Version:\s*)(?:\{\{VERSION\}\}|\d+\.\d+\.\d+(?:[-~][0-9A-Za-z.-]+)?)\s*$/mu;
  if (!versionPattern.test(text)) {
    failures.push("linux/packaging/control.template: Version line not found");
    return null;
  }
  return text.replace(versionPattern, `$1${semverToDebianVersion(version)}`);
}

function replaceDownloadTableUrls(text, version, failures) {
  const eol = lineEnding(text);
  const lines = text.split(/\r?\n/u);
  const firstReleaseHeading = lines.findIndex((line) => /^## Changes in `v/iu.test(line));
  const preambleEnd = firstReleaseHeading < 0 ? lines.length : firstReleaseHeading;
  const downloadHeading = lines.findIndex(
    (line, index) => index < preambleEnd && /^# .*downloads\s*$/iu.test(line.trim()),
  );
  if (downloadHeading < 0) {
    failures.push("CHANGELOG.md: download heading not found");
    return null;
  }

  let tableStart = downloadHeading + 1;
  while (tableStart < preambleEnd && lines[tableStart].trim() === "") tableStart += 1;
  if (tableStart >= preambleEnd || !lines[tableStart].trim().startsWith("|")) {
    failures.push("CHANGELOG.md: download table not found");
    return null;
  }

  let tableEnd = tableStart;
  let releaseUrlCount = 0;
  for (; tableEnd < preambleEnd; tableEnd += 1) {
    if (!lines[tableEnd].trim().startsWith("|")) break;
    const original = lines[tableEnd];
    releaseUrlCount += (original.match(/\/releases\/download\/v[^/\s)]+(?=\/)/giu) || []).length;
    lines[tableEnd] = original.replace(
      /(\/releases\/download\/)v[^/\s)]+(?=\/)/giu,
      `$1v${version}`,
    );
  }
  if (tableEnd === tableStart || releaseUrlCount === 0) {
    failures.push("CHANGELOG.md: download table contains no release URLs");
    return null;
  }
  return lines.join(eol);
}

function toggleBetaNotice(text, version, failures) {
  const eol = lineEnding(text);
  const firstReleaseHeading = text.search(/^## Changes in `v[^`]+:`\s*$/mu);
  const preamble = text.slice(0, firstReleaseHeading < 0 ? text.length : firstReleaseHeading);
  const betaPhraseCount = (preamble.match(/This is a Beta build\./giu) || []).length;
  if (betaPhraseCount > 0 && !BETA_NOTICE_PATTERN.test(preamble)) {
    failures.push("CHANGELOG.md: malformed beta notice marker");
    return null;
  }
  if (betaPhraseCount > 1) {
    failures.push("CHANGELOG.md: duplicate beta notice marker");
    return null;
  }
  const withoutCanonicalNotice = text.replace(BETA_NOTICE_PATTERN, "");
  const notice = isPrerelease(version) ? BETA_NOTICE : COMMENTED_BETA_NOTICE;
  return `${notice.replaceAll("\n", eol)}${eol}${eol}${withoutCanonicalNotice.replace(/^\s+/u, "")}`;
}

function ensureCurrentReleaseHeading(text, version, failures) {
  const eol = lineEnding(text);
  const expectedHeading = `## Changes in \`v${version}:\``;
  const headingPattern = /^## Changes in `v[^`]+:`\s*$/gmu;
  const headings = [...text.matchAll(headingPattern)];
  const current = headings.filter((match) => match[0].trim() === expectedHeading);
  if (current.length > 1) {
    failures.push(`CHANGELOG.md: duplicate current heading ${expectedHeading}`);
    return null;
  }

  if (current.length === 1 && headings[0]?.index === current[0].index) {
    return text;
  }

  if (current.length === 1) {
    const currentIndex = current[0].index;
    const currentEnd = headings.find((heading) => heading.index > currentIndex)?.index ?? text.length;
    const currentSection = text.slice(currentIndex, currentEnd).replace(/\s+$/u, "");
    const withoutCurrent = `${text.slice(0, currentIndex)}${text.slice(currentEnd)}`;
    const firstHeading = withoutCurrent.search(/^## Changes in `v[^`]+:`\s*$/mu);
    if (firstHeading < 0) {
      failures.push("CHANGELOG.md: release heading not found");
      return null;
    }
    return `${withoutCurrent.slice(0, firstHeading)}${currentSection}${eol}${eol}${withoutCurrent.slice(firstHeading)}`;
  }

  const firstHeading = text.search(/^## Changes in `v[^`]+:`\s*$/mu);
  if (firstHeading < 0) {
    failures.push("CHANGELOG.md: release heading not found");
    return null;
  }
  return `${text.slice(0, firstHeading)}${expectedHeading}${eol}${eol}${text.slice(firstHeading)}`;
}

function updateChangelog(text, version, failures) {
  const withUrls = replaceDownloadTableUrls(text, version, failures);
  if (withUrls == null) return null;
  const withNotice = toggleBetaNotice(withUrls, version, failures);
  if (withNotice == null) return null;
  return ensureCurrentReleaseHeading(withNotice, version, failures);
}

function prepareSync(root) {
  const packagePath = path.join(root, "package.json");
  if (!fs.existsSync(packagePath)) throw new Error(`package.json not found: ${packagePath}`);
  let pkg;
  try {
    pkg = JSON.parse(fs.readFileSync(packagePath, "utf8"));
  } catch (error) {
    throw new Error(`Invalid package.json: ${error.message}`);
  }
  const version = pkg.version;
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(version || "")) {
    throw new Error(`Invalid package.json version: "${version}"`);
  }

  const failures = [];
  const updates = [];
  for (const relative of REQUIRED_FILES) {
    const filePath = path.join(root, relative);
    if (!fs.existsSync(filePath)) {
      failures.push(`${relative}: file not found`);
      continue;
    }
    const original = fs.readFileSync(filePath, "utf8");
    let updated = original;
    if (relative === "package-lock.json") updated = updatePackageLock(original, version, failures, relative);
    if (relative === "pubspec.yaml") updated = updatePubspec(original, version, failures);
    if (relative === "run.rosie.dacx.metainfo.xml") updated = updateMetainfo(original, version, failures);
    if (relative === "flatpak/run.rosie.dacx.yaml") updated = updateFlatpak(original, version, failures);
    if (relative === "linux/packaging/control.template") {
      updated = updateLinuxPackageTemplate(original, version, failures);
    }
    if (relative === "CHANGELOG.md") updated = updateChangelog(original, version, failures);
    if (updated != null && updated !== original) updates.push({ relative, filePath, updated });
  }

  if (failures.length) {
    throw new Error(`sync-version validation failed:\n  ${failures.join("\n  ")}`);
  }
  return { version, updates };
}

function syncVersion(root = defaultRoot) {
  const prepared = prepareSync(root);
  writeUpdatesTransactionally(prepared.updates);
  for (const { relative } of prepared.updates) console.log(`${relative} -> updated`);
  if (prepared.updates.length === 0) console.log(`Version ${prepared.version} already synchronized.`);
  return prepared;
}

function writeDurable(filePath, contents) {
  const descriptor = fs.openSync(filePath, "w");
  try {
    fs.writeFileSync(descriptor, contents, "utf8");
    fs.fsyncSync(descriptor);
  } finally {
    fs.closeSync(descriptor);
  }
}

function writeUpdatesTransactionally(updates) {
  if (updates.length === 0) return;
  const token = `${process.pid}-${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const staged = [];
  try {
    for (const update of updates) {
      const temporary = `${update.filePath}.sync-version-${token}.tmp`;
      const backup = `${update.filePath}.sync-version-${token}.bak`;
      staged.push({ ...update, temporary, backup });
      writeDurable(temporary, update.updated);
      fs.copyFileSync(update.filePath, backup);
    }
    for (const update of staged) {
      try {
        fs.renameSync(update.temporary, update.filePath);
      } catch (error) {
        if (error.code !== "EEXIST" && error.code !== "EPERM" && error.code !== "ENOTEMPTY") throw error;
        fs.copyFileSync(update.temporary, update.filePath);
        fs.rmSync(update.temporary, { force: true });
      }
    }
  } catch (error) {
    for (const update of [...staged].reverse()) {
      if (!fs.existsSync(update.backup)) continue;
      try {
        fs.copyFileSync(update.backup, update.filePath);
      } catch {
        // Preserve original failure. The report still names the affected file.
      }
    }
    throw new Error(`sync-version write transaction rolled back: ${error.message}`);
  } finally {
    for (const update of staged) {
      fs.rmSync(update.temporary, { force: true });
      fs.rmSync(update.backup, { force: true });
    }
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  try {
    syncVersion(parseArgs(process.argv.slice(2)));
  } catch (error) {
    console.error(error.message || String(error));
    process.exitCode = 1;
  }
}

export {
  ensureCurrentReleaseHeading,
  prepareSync,
  syncVersion,
  updateChangelog,
  writeUpdatesTransactionally,
};
