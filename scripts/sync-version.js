#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf-8"));
const version = pkg.version;
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(version)) {
  console.error(`Invalid package.json version: "${version}"`);
  process.exit(1);
}

let exitCode = 0;
const failures = [];

function syncFile(label, filePath, mutate) {
  try {
    if (!fs.existsSync(filePath)) return;
    const original = fs.readFileSync(filePath, "utf-8");
    const updated = mutate(original);
    if (updated == null || updated === original) return;
    fs.writeFileSync(filePath, updated);
    console.log(`${label} → updated`);
  } catch (err) {
    failures.push(`${label}: ${err.message}`);
    exitCode = 1;
  }
}

syncFile("pubspec.yaml", path.join(root, "pubspec.yaml"), (text) => {
  const versionPattern = /^(version:\s*)(\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?)(?:\+(\d+))?/m;
  const match = text.match(versionPattern);
  if (!match) {
    failures.push("pubspec.yaml: version line not found");
    exitCode = 1;
    return null;
  }
  const buildNumber = match[3] || "1";
  return text.replace(versionPattern, `${match[1]}${version}+${buildNumber}`);
});

syncFile(
  "run.rosie.dacx.metainfo.xml",
  path.join(root, "run.rosie.dacx.metainfo.xml"),
  (text) => {
    if (text.includes(`version="${version}"`)) return null;
    const today = new Date().toISOString().slice(0, 10);
    const releaseTag = `    <release version="${version}" date="${today}"/>\n`;
    return text.replace(/(<releases>\s*\n)/, `$1${releaseTag}`);
  },
);

syncFile(
  "flatpak/run.rosie.dacx.yaml",
  path.join(root, "flatpak", "run.rosie.dacx.yaml"),
  (text) => {
    const tag = `# x-version: ${version}\n`;
    if (/^# x-version:.*\n/.test(text)) {
      return text.replace(/^# x-version:.*\n/, tag);
    }
    return tag + text;
  },
);

syncFile(
  "linux/packaging/control.template",
  path.join(root, "linux", "packaging", "control.template"),
  (text) => text.replace(/Version:\s*\{\{VERSION\}\}/g, `Version: ${version}`),
);

syncFile(
  "linux/packaging/dacx.spec.template",
  path.join(root, "linux", "packaging", "dacx.spec.template"),
  (text) => text.replace(/Version:\s*\{\{VERSION\}\}/g, `Version: ${version}`),
);

if (failures.length) {
  console.error("sync-version: failures:\n  " + failures.join("\n  "));
}
process.exit(exitCode);
