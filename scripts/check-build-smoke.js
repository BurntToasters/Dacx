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
  if (process.env.CI) {
    console.error("flutter not on PATH; refusing to skip build smoke under CI.");
    process.exit(1);
  }
  console.warn("WARN: flutter not on PATH; skipping build smoke.");
  process.exit(0);
}

const start = Date.now();
const r = spawnSync("flutter", ["build", "bundle", "--release"], {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
  windowsHide: true,
  shell: process.platform === "win32",
});
const elapsed = ((Date.now() - start) / 1000).toFixed(1);
const combinedOutput = `${r.stdout ?? ""}${r.stderr ?? ""}`;
process.stdout.write(r.stdout ?? "");
process.stderr.write(r.stderr ?? "");
if (r.status !== 0) {
  // The Flutter native_assets pipeline still resolves the Android target
  // even for `build bundle`, so a missing Android SDK on a developer
  // machine produces a confusing failure that has nothing to do with
  // Dart code health. Treat this as inconclusive locally; in CI we want
  // a real environment, so surface the failure.
  if (/Android SDK could not be found/.test(combinedOutput)) {
    if (process.env.CI) {
      console.error(
        `flutter build bundle failed after ${elapsed}s; Android SDK missing in CI environment.`,
      );
      process.exit(r.status ?? 1);
    }
    console.warn(
      `WARN: skipping build smoke; Android SDK not configured locally (${elapsed}s).`,
    );
    process.exit(0);
  }
  console.error(`flutter build bundle failed after ${elapsed}s.`);
  process.exit(r.status ?? 1);
}
console.log(`Build smoke OK (${elapsed}s).`);
