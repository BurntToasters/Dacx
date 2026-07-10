#!/usr/bin/env node
/**
 * Advisory: surface any direct Dart dependencies that have a newer
 * resolvable version available. Never fails the suite — purely a
 * heads-up for the maintainer between releases.
 *
 * Skipped silently if FVM is not on PATH.
 */
import { spawnSync } from "node:child_process";
import crossSpawn from "cross-spawn";

const which = spawnSync(
  process.platform === "win32" ? "where" : "which",
  ["fvm"],
  { encoding: "utf8", windowsHide: true },
);
if (which.status !== 0) {
  console.log("fvm not on PATH; skipping outdated advisory.");
  process.exit(0);
}

const r = crossSpawn.sync(
  "fvm",
  ["flutter", "pub", "outdated", "--no-dev-dependencies", "--up-to-date"],
  {
    encoding: "utf8",
    windowsHide: true,
  },
);

const out = (r.stdout || "") + (r.stderr || "");
// `fvm flutter pub outdated` exits 65 when newer versions exist; treat as
// informational, not failing.
const trimmed = out.trim();
if (!trimmed) {
  console.log("Outdated check: no output.");
  process.exit(0);
}

const lines = trimmed.split("\n");
const tail = lines.length > 30 ? lines.slice(-30).join("\n") : trimmed;
console.log(tail);
console.log("\nOutdated check is advisory; not failing the suite.");
process.exit(0);
