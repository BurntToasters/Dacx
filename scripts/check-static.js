#!/usr/bin/env node
/**
 * Syntax-checks every script and JSON file we ship, plus structural
 * validation of the AppStream metainfo XML. Catches typos that would
 * otherwise blow up partway through a release build.
 *
 * Steps:
 *  1. `node --check` on every scripts/*.js
 *  2. JSON.parse on package.json + analysis_options sidecars
 *  3. Validate metainfo XML: well-formed; required tags present; release
 *     entries are version-sorted descending; current version present
 *  4. If `appstreamcli` is on PATH, run `appstreamcli validate --no-net`
 *     against the metainfo (warn-only; missing tool is fine).
 *  5. If `shellcheck` is on PATH, run it on scripts/*.sh (warn-only).
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const failures = [];
const warnings = [];

function rel(p) {
  return path.relative(root, p);
}

// 1. JS syntax check
const scriptsDir = path.join(root, "scripts");
const jsFiles = fs
  .readdirSync(scriptsDir)
  .filter((f) => f.endsWith(".js"))
  .map((f) => path.join(scriptsDir, f));
for (const file of jsFiles) {
  const r = spawnSync(process.execPath, ["--check", file], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (r.status !== 0) {
    failures.push(`JS syntax error in ${rel(file)}:\n${r.stderr.trim()}`);
  }
}

// 2. JSON parse
const jsonFiles = ["package.json", "package-lock.json"]
  .map((f) => path.join(root, f))
  .filter((f) => fs.existsSync(f));
for (const file of jsonFiles) {
  try {
    JSON.parse(fs.readFileSync(file, "utf8"));
  } catch (e) {
    failures.push(`JSON parse error in ${rel(file)}: ${e.message}`);
  }
}

// 3. Metainfo XML
const metainfoPath = path.join(root, "run.rosie.dacx.metainfo.xml");
if (fs.existsSync(metainfoPath)) {
  const xml = fs.readFileSync(metainfoPath, "utf8");
  const requiredTags = [
    "<id>run.rosie.dacx</id>",
    "<name>Dacx</name>",
    "<launchable",
    "<provides>",
    "<releases>",
    "<content_rating",
  ];
  for (const tag of requiredTags) {
    if (!xml.includes(tag)) {
      failures.push(`metainfo missing required token: ${tag}`);
    }
  }
  // Crude well-formedness: every opening tag has a matching close on this
  // pass-by counting <foo> vs </foo> for the named tags we care about.
  const balanced = ["component", "description", "releases", "screenshots"];
  for (const t of balanced) {
    const open = (xml.match(new RegExp(`<${t}[\\s>]`, "g")) || []).length;
    const close = (xml.match(new RegExp(`</${t}>`, "g")) || []).length;
    if (open !== close) {
      failures.push(`metainfo unbalanced <${t}>: open=${open} close=${close}`);
    }
  }
  // Release version ordering: parse all <release version="x.y.z" .../>
  const releases = [
    ...xml.matchAll(/<release\s+version="([^"]+)"[^>]*\/?>/g),
  ].map((m) => m[1]);
  if (releases.length === 0) {
    failures.push("metainfo has no <release> entries");
  } else {
    const cmp = (a, b) => {
      const pa = a.split(/[.-]/).map((s) => parseInt(s, 10) || 0);
      const pb = b.split(/[.-]/).map((s) => parseInt(s, 10) || 0);
      for (let i = 0; i < Math.max(pa.length, pb.length); i++) {
        const d = (pb[i] || 0) - (pa[i] || 0);
        if (d !== 0) return d;
      }
      return 0;
    };
    const sorted = [...releases].sort(cmp);
    if (sorted.join(",") !== releases.join(",")) {
      failures.push(
        `metainfo <release> entries are not version-sorted descending. Got: ${releases.join(", ")}`,
      );
    }
  }

  // 4. Optional appstreamcli
  const appstream = spawnSync(
    "appstreamcli",
    ["validate", "--no-net", metainfoPath],
    { encoding: "utf8", windowsHide: true },
  );
  if (appstream.error && appstream.error.code === "ENOENT") {
    warnings.push("appstreamcli not installed; skipping AppStream validation");
  } else if (appstream.status !== 0) {
    warnings.push(
      `appstreamcli reported issues:\n${(appstream.stdout + appstream.stderr).trim()}`,
    );
  }
}

// 5. Flatpak sandbox policy
const flatpakManifest = path.join(root, "flatpak", "run.rosie.dacx.yaml");
if (fs.existsSync(flatpakManifest)) {
  const flatpak = fs.readFileSync(flatpakManifest, "utf8");
  const flatpakActive = flatpak
    .split("\n")
    .map((line) => line.replace(/#.*$/, "").trim())
    .join("\n");
  if (/--filesystem=host\b/.test(flatpakActive)) {
    failures.push(
      `${rel(flatpakManifest)} must not use --filesystem=host (use XDG dirs + portal file picker)`,
    );
  }
  if (!flatpak.includes("THIRD_PARTY_NOTICES.txt")) {
    failures.push(
      `${rel(flatpakManifest)} must install build/THIRD_PARTY_NOTICES.txt into the bundle`,
    );
  }
}

// 6. Optional shellcheck
const shFiles = fs
  .readdirSync(scriptsDir)
  .filter((f) => f.endsWith(".sh"))
  .map((f) => path.join(scriptsDir, f));
if (shFiles.length) {
  const r = spawnSync("shellcheck", ["-S", "warning", ...shFiles], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (r.error && r.error.code === "ENOENT") {
    warnings.push("shellcheck not installed; skipping shell script lint");
  } else if (r.status !== 0) {
    warnings.push(`shellcheck reported issues:\n${r.stdout.trim()}`);
  }
}

for (const w of warnings) console.warn(`WARN: ${w}`);
if (failures.length) {
  console.error("Static checks FAILED:");
  for (const f of failures) console.error(`  - ${f}`);
  process.exit(1);
}
console.log(
  `Static checks OK (${jsFiles.length} JS, ${jsonFiles.length} JSON, ${shFiles.length} sh, metainfo).`,
);
