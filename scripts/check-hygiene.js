#!/usr/bin/env node
/**
 * Repository hygiene checks. Catches sloppy commits that pass linters
 * but signal half-finished work shipped to a release branch:
 *
 *  - Stray TODO/FIXME/XXX/HACK markers in lib/ (warns, not fails)
 *  - `print(` calls left in lib/ (fails — use DebugLogService)
 *  - `debugPrint(` outside test/ (warns — Flutter's intended diagnostic
 *    helper is allowed in lib/, but call sites are surfaced so they can
 *    be migrated to DebugLogService when they accumulate)
 *  - .orig / .bak / .rej merge debris anywhere
 *  - Files larger than 500 KB outside well-known asset dirs
 *
 * Configure the print-fail behaviour with DACX_HYGIENE_STRICT=0 to
 * downgrade everything to warnings.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const strict = process.env.DACX_HYGIENE_STRICT !== "0";
const failures = [];
const warnings = [];

function walk(dir, ignore = new Set()) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    if (ignore.has(entry.name)) continue;
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full, ignore));
    else out.push(full);
  }
  return out;
}

const libDir = path.join(root, "lib");
if (fs.existsSync(libDir)) {
  const dartFiles = walk(libDir).filter((f) => f.endsWith(".dart"));
  const printRe = /(?<![a-zA-Z0-9_.])print\s*\(/;
  const debugPrintRe = /\bdebugPrint\s*\(/;
  const todoRe = /\b(?:TODO|FIXME|XXX|HACK)\b/;

  for (const file of dartFiles) {
    const text = fs.readFileSync(file, "utf8");
    const lines = text.split("\n");
    lines.forEach((line, idx) => {
      // Honour explicit opt-outs.
      const prev = lines[idx - 1] ?? "";
      const optedOut =
        /\/\/\s*ignore:\s*avoid_print/.test(prev) ||
        /\/\/\s*ignore:\s*avoid_print/.test(line);
      // Skip line comments — TODOs in comments are warn-only anyway.
      const code = line.split("//")[0];
      if (!optedOut && printRe.test(code)) {
        const msg = `${path.relative(root, file)}:${idx + 1}: stray print() — use DebugLogService`;
        (strict ? failures : warnings).push(msg);
      }
      if (!optedOut && debugPrintRe.test(code)) {
        const msg = `${path.relative(root, file)}:${idx + 1}: stray debugPrint()`;
        // debugPrint is the Flutter-blessed diagnostic helper and is fine
        // in lib/ for now. Surface as a warning so we can track call sites,
        // but do not block CI.
        warnings.push(msg);
      }
      if (todoRe.test(line)) {
        warnings.push(
          `${path.relative(root, file)}:${idx + 1}: ${line.trim().slice(0, 100)}`,
        );
      }
    });
  }
}

// Merge debris anywhere
const debrisRoots = ["lib", "test", "scripts", "macos/Runner", "windows/runner", "linux/runner"]
  .map((p) => path.join(root, p))
  .filter((p) => fs.existsSync(p));
for (const dir of debrisRoots) {
  for (const file of walk(dir)) {
    if (/\.(?:orig|bak|rej)$/.test(file)) {
      failures.push(`merge debris file: ${path.relative(root, file)}`);
    }
  }
}

// Oversized non-asset files
const sizeLimit = 500 * 1024;
const sizeOk = new Set(["assets", "build", "macos/Pods", "linux/flutter/ephemeral"]);
function isAsset(rel) {
  for (const prefix of sizeOk) if (rel.startsWith(prefix + path.sep)) return true;
  return false;
}
for (const dir of debrisRoots) {
  for (const file of walk(dir)) {
    const rel = path.relative(root, file);
    if (isAsset(rel)) continue;
    try {
      const size = fs.statSync(file).size;
      if (size > sizeLimit) {
        warnings.push(`large file (${(size / 1024).toFixed(0)} KB): ${rel}`);
      }
    } catch {}
  }
}

if (warnings.length > 50) {
  console.warn(`WARN: ${warnings.length} hygiene notes (showing first 20):`);
  for (const w of warnings.slice(0, 20)) console.warn(`  - ${w}`);
} else {
  for (const w of warnings) console.warn(`WARN: ${w}`);
}

if (failures.length) {
  console.error("Hygiene check FAILED:");
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(`Hygiene OK (${warnings.length} advisory note${warnings.length === 1 ? "" : "s"}).`);
