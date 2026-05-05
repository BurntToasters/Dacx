#!/usr/bin/env node
/**
 * Cheap-ish "does the Dart side actually compile in production mode"
 * smoke check. Runs `flutter build bundle` which performs tree-shaking
 * and asset resolution but skips native compilation, so it works on any
 * developer machine without platform toolchains.
 *
 * Skipped automatically when DACX_SKIP_BUILD_SMOKE=1 is set, or when
 * `flutter` is not on PATH (warn only).
 */
import { spawnSync } from "node:child_process";

if (process.env.DACX_SKIP_BUILD_SMOKE === "1") {
  console.log("Build smoke skipped (DACX_SKIP_BUILD_SMOKE=1).");
  process.exit(0);
}

const which = spawnSync(
  process.platform === "win32" ? "where" : "which",
  ["flutter"],
  { encoding: "utf8", windowsHide: true },
);
if (which.status !== 0) {
  console.warn("WARN: flutter not on PATH; skipping build smoke.");
  process.exit(0);
}

const start = Date.now();
const r = spawnSync("flutter", ["build", "bundle", "--release"], {
  encoding: "utf8",
  stdio: "inherit",
  windowsHide: true,
  shell: process.platform === "win32",
});
const elapsed = ((Date.now() - start) / 1000).toFixed(1);
if (r.status !== 0) {
  console.error(`flutter build bundle failed after ${elapsed}s.`);
  process.exit(r.status ?? 1);
}
console.log(`Build smoke OK (${elapsed}s).`);
