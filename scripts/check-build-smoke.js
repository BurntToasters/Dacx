#!/usr/bin/env node
/**
 * Build smoke gate.
 * - CI: compile host desktop runner to catch native Swift/C++ regressions.
 * - Local: run FVM Flutter build bundle as a cheap Dart-side sanity check.
 */
import { spawnSync } from "node:child_process";
import crossSpawn from "cross-spawn";

if (process.env.DACX_SKIP_BUILD_SMOKE === "1") {
  console.log("Build smoke skipped (DACX_SKIP_BUILD_SMOKE=1).");
  process.exit(0);
}

const which = spawnSync(
  process.platform === "win32" ? "where" : "which",
  ["fvm"],
  { encoding: "utf8", windowsHide: true },
);
if (which.status !== 0) {
  if (process.env.CI) {
    console.error("fvm not on PATH; refusing to skip build smoke under CI.");
    process.exit(1);
  }
  console.warn("WARN: fvm not on PATH; skipping build smoke.");
  process.exit(0);
}

const start = Date.now();
const ci = process.env.CI === "true" || process.env.CI === "1";
const args = ci
  ? [
      "flutter",
      "build",
      process.platform === "darwin"
        ? "macos"
        : process.platform === "win32"
          ? "windows"
          : "linux",
      "--debug",
    ]
  : ["flutter", "build", "bundle", "--release"];
const r = crossSpawn.sync("fvm", args, {
  encoding: "utf8",
  stdio: ["ignore", "pipe", "pipe"],
  windowsHide: true,
});
const elapsed = ((Date.now() - start) / 1000).toFixed(1);
const combinedOutput = `${r.stdout ?? ""}${r.stderr ?? ""}`;
process.stdout.write(r.stdout ?? "");
process.stderr.write(r.stderr ?? "");
if (r.status !== 0) {
  // The Flutter native_assets pipeline can still probe Android SDK while
  // building non-Android targets. Treat this as inconclusive locally.
  if (/Android SDK could not be found/.test(combinedOutput)) {
    if (ci) {
      console.error(
        `fvm flutter build failed after ${elapsed}s; Android SDK missing in CI environment.`,
      );
      process.exit(r.status ?? 1);
    }
    console.warn(
      `WARN: skipping build smoke; Android SDK not configured locally (${elapsed}s).`,
    );
    process.exit(0);
  }
  console.error(`fvm flutter build smoke failed after ${elapsed}s.`);
  process.exit(r.status ?? 1);
}
if (/do not support Swift Package Manager/i.test(combinedOutput)) {
  console.warn(
    "WARN: Flutter used the known CocoaPods fallback for plugins without SwiftPM support.",
  );
}
console.log(`Build smoke OK (${elapsed}s).`);
