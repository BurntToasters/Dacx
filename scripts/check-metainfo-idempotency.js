#!/usr/bin/env node
/**
 * Idempotency + safety regression test for scripts/update-metainfo.js.
 * Guards against the class of bugs where running `npm run u` twice in a
 * row (or running update-metainfo on an already-updated file) would
 * duplicate or scramble <release> entries.
 *
 * Strategy: snapshot the current metainfo, run update-metainfo twice,
 * assert the result is byte-identical between run 1 and run 2 and
 * contains exactly one entry for the current version. Restore on exit.
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const metainfo = path.join(root, "run.rosie.dacx.metainfo.xml");
const script = path.join(root, "scripts", "update-metainfo.js");

if (!fs.existsSync(metainfo) || !fs.existsSync(script)) {
  console.log("update-metainfo idempotency: skipped (files missing).");
  process.exit(0);
}

const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf8"));
const version = pkg.version;

const original = fs.readFileSync(metainfo, "utf8");
let exit = 0;
try {
  // First run
  const r1 = spawnSync(process.execPath, [script], {
    encoding: "utf8",
    cwd: root,
    windowsHide: true,
  });
  if (r1.status !== 0) {
    throw new Error(`first run exit ${r1.status}: ${r1.stderr}`);
  }
  const after1 = fs.readFileSync(metainfo, "utf8");

  // Second run (idempotency)
  const r2 = spawnSync(process.execPath, [script], {
    encoding: "utf8",
    cwd: root,
    windowsHide: true,
  });
  if (r2.status !== 0) {
    throw new Error(`second run exit ${r2.status}: ${r2.stderr}`);
  }
  const after2 = fs.readFileSync(metainfo, "utf8");

  if (after1 !== after2) {
    throw new Error("update-metainfo is NOT idempotent (run 2 differs from run 1)");
  }

  // Exactly-one current-version release entry
  const versionRe = new RegExp(
    `<release\\s+version="${version.replace(/[.+]/g, "\\$&")}"`,
    "g",
  );
  const occurrences = (after1.match(versionRe) || []).length;
  if (occurrences !== 1) {
    throw new Error(
      `expected exactly 1 <release version="${version}"> entry, found ${occurrences}`,
    );
  }
  console.log("update-metainfo idempotency OK.");
} catch (e) {
  console.error(`update-metainfo idempotency FAILED: ${e.message}`);
  exit = 1;
} finally {
  fs.writeFileSync(metainfo, original);
}
process.exit(exit);
