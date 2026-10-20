#!/usr/bin/env node
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

export const PINNED_LIBMPV_ARCHIVES = {
  "mpv-dev-x86_64-20241021-git-0f78584.7z":
    "e23701df0adc1fe57c8ede3ff313513b0b80519870058c2d35ff02754284a007",
};

export function checkWindowsLibmpvArchives(
  buildDir,
  pinned = PINNED_LIBMPV_ARCHIVES,
) {
  const failures = [];
  const archives = fs.existsSync(buildDir)
    ? fs.readdirSync(buildDir).filter((name) => /^mpv-dev-.*\.7z$/u.test(name))
    : [];
  if (!archives.length) failures.push(`no libmpv archive found in ${buildDir}`);
  for (const name of archives) {
    const expected = pinned[name];
    if (!expected) {
      failures.push(`${name} is not pinned; delete it or pin its SHA-256`);
      continue;
    }
    const actual = crypto
      .createHash("sha256")
      .update(fs.readFileSync(path.join(buildDir, name)))
      .digest("hex");
    if (actual !== expected) {
      failures.push(`${name} SHA-256 mismatch: expected ${expected}, got ${actual}`);
    }
  }
  return { passed: failures.length === 0, archives, failures };
}

const isMain =
  process.argv[1] &&
  path.resolve(process.argv[1]) === fileURLToPath(import.meta.url);
if (isMain) {
  const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
  const result = checkWindowsLibmpvArchives(
    process.argv[2] ?? path.join(root, "build", "windows", "x64"),
  );
  for (const failure of result.failures) console.error(failure);
  if (!result.passed) process.exit(1);
  console.log(`Native libs OK: ${result.archives.join(", ")}`);
}
