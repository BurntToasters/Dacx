#!/usr/bin/env node

/**
 * Generate a JSON file listing all Dart/Flutter dependency licenses.
 *
 * Usage: node scripts/generate-licenses.js
 * Output: build/licenses.json
 *
 * Reads `flutter pub deps --json`, resolves each package's LICENSE file
 * from the pub cache, and writes a JSON array.
 */

import fs from "fs";
import path from "path";
import os from "os";
import { execSync } from "child_process";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

// ── Locate the pub cache ─────────────────────────────────────

function getPubCacheDir() {
  if (process.env.PUB_CACHE) return process.env.PUB_CACHE;
  if (process.platform === "win32") {
    return path.join(os.homedir(), "AppData", "Local", "Pub", "Cache");
  }
  return path.join(os.homedir(), ".pub-cache");
}

// ── Get dependency list ──────────────────────────────────────

function getDependencies() {
  // flutter pub deps --json gives structured output
  const raw = execSync("flutter pub deps --style=list", {
    cwd: root,
    encoding: "utf-8",
    stdio: ["pipe", "pipe", "pipe"],
  });

  // Parse "- <package> <version>" lines
  const deps = [];
  for (const line of raw.split("\n")) {
    const match = line.match(/^- (\S+) (\S+)/);
    if (match) {
      deps.push({ name: match[1], version: match[2] });
    }
  }
  return deps;
}

// ── Find LICENSE file for a package ──────────────────────────

function findLicenseText(name, version, pubCache) {
  const hostedDir = path.join(pubCache, "hosted", "pub.dev");
  const pkgDir = path.join(hostedDir, `${name}-${version}`);

  // Try common license filenames
  const candidates = ["LICENSE", "LICENSE.md", "LICENSE.txt", "LICENCE", "COPYING"];

  for (const candidate of candidates) {
    const filePath = path.join(pkgDir, candidate);
    if (fs.existsSync(filePath)) {
      return fs.readFileSync(filePath, "utf-8").trim();
    }
  }

  // Also check without version suffix (git/path deps)
  const altDir = path.join(hostedDir, name);
  if (fs.existsSync(altDir)) {
    for (const candidate of candidates) {
      const filePath = path.join(altDir, candidate);
      if (fs.existsSync(filePath)) {
        return fs.readFileSync(filePath, "utf-8").trim();
      }
    }
  }

  return null;
}

// ── Detect license type from text ────────────────────────────

function detectLicenseType(text) {
  if (!text) return "Unknown";
  const t = text.toLowerCase();
  if (t.includes("mit license") || t.includes("permission is hereby granted, free of charge")) return "MIT";
  if (t.includes("apache license") && t.includes("version 2.0")) return "Apache-2.0";
  if (t.includes("bsd 3-clause") || (t.includes("redistribution") && t.includes("3."))) return "BSD-3-Clause";
  if (t.includes("bsd 2-clause")) return "BSD-2-Clause";
  if (t.includes("mozilla public license")) return "MPL-2.0";
  if (t.includes("gnu lesser general public license")) return "LGPL";
  if (t.includes("gnu general public license")) return "GPL";
  if (t.includes("the unlicense")) return "Unlicense";
  if (t.includes("isc license")) return "ISC";
  return "Other";
}

// ── Main ─────────────────────────────────────────────────────

function main() {
  console.log("Collecting Dart/Flutter package licenses...\n");

  const pubCache = getPubCacheDir();
  console.log(`Pub cache: ${pubCache}`);

  const deps = getDependencies();
  console.log(`Found ${deps.length} dependencies.\n`);

  // Skip the project itself and SDK packages
  const sdkPackages = new Set(["flutter", "flutter_test", "flutter_web_plugins", "sky_engine", "flutter_driver"]);

  const licenses = [];
  let found = 0;
  let missing = 0;

  for (const { name, version } of deps) {
    if (sdkPackages.has(name) || name === "dacx") continue;

    const text = findLicenseText(name, version, pubCache);
    const type = detectLicenseType(text);

    if (text) {
      found++;
      licenses.push({ name, version, license: type, text });
    } else {
      missing++;
      console.warn(`  ⚠ No LICENSE found for ${name}@${version}`);
      licenses.push({ name, version, license: "Unknown", text: null });
    }
  }

  // Sort alphabetically
  licenses.sort((a, b) => a.name.localeCompare(b.name));

  // Write output
  const outDir = path.join(root, "build");
  fs.mkdirSync(outDir, { recursive: true });
  const outPath = path.join(outDir, "licenses.json");
  fs.writeFileSync(outPath, JSON.stringify(licenses, null, 2));

  console.log(`\n✔ ${found} licenses found, ${missing} missing.`);
  console.log(`  Output: ${path.relative(root, outPath)}`);

  // Also print a summary table
  console.log("\n  Package                          License");
  console.log("  " + "─".repeat(50));
  for (const entry of licenses) {
    const pkg = `${entry.name}@${entry.version}`.padEnd(35);
    console.log(`  ${pkg}${entry.license}`);
  }
}

main();
