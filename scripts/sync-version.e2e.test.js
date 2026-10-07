import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import test from "node:test";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const script = path.join(root, "scripts", "sync-version.js");
const artifactDir = path.join(root, "test-results", "sync-version");
const version = "1.0.0-beta.1";

const fixtureFiles = {
  "package.json": JSON.stringify({ name: "fixture", version }, null, 2) + "\n",
  "package-lock.json": JSON.stringify(
    { name: "fixture", version: "0.11.3", lockfileVersion: 3, packages: { "": { version: "0.11.3" } } },
    null,
    2,
  ) + "\n",
  "pubspec.yaml": "name: fixture\nversion: 0.11.3+1103\n",
  "run.rosie.dacx.metainfo.xml":
    "<component>\n  <releases>\n    <release version=\"0.11.3\" date=\"2026-01-01\"/>\n  </releases>\n</component>\n",
  "flatpak/run.rosie.dacx.yaml": "# x-version: 0.11.3\napp-id: run.rosie.dacx\n",
  "linux/packaging/control.template": "Package: dacx\nVersion: 0.11.3\n",
  "CHANGELOG.md": `<!-- > [!NOTE]\n> 🅱️ This is a Beta build. -->\n\n# ⬇️ Downloads\n\n| Windows | macOS | Linux |\n| :--- | :--- | :--- |\n| [old](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Windows-x64.msi) | [old](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-macOS.dmg) | [old](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Linux-x86_64.AppImage) |\n\nHistorical link: https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/old.zip\n\n## Changes in \`v0.11.3:\`\n- Existing note.\n`,
};

function writeFixture(fixtureRoot) {
  for (const [relative, contents] of Object.entries(fixtureFiles)) {
    const target = path.join(fixtureRoot, relative);
    fs.mkdirSync(path.dirname(target), { recursive: true });
    fs.writeFileSync(target, contents, "utf8");
  }
}

function snapshot(fixtureRoot) {
  return Object.fromEntries(
    Object.keys(fixtureFiles).map((relative) => [
      relative,
      fs.readFileSync(path.join(fixtureRoot, relative), "utf8"),
    ]),
  );
}

function diff(before, after) {
  return Object.keys(before)
    .map((file) => {
      if (before[file] === after[file]) return "";
      return `--- ${file} (before)\n+++ ${file} (after)\n${after[file]}`;
    })
    .filter(Boolean)
    .join("\n");
}

function runSync(fixtureRoot) {
  return spawnSync(process.execPath, [script, "--root", fixtureRoot], {
    cwd: root,
    encoding: "utf8",
  });
}

test("sync-version updates complete fixture workflow safely and idempotently", () => {
  fs.rmSync(artifactDir, { recursive: true, force: true });
  fs.mkdirSync(artifactDir, { recursive: true });
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dacx-sync-version-"));
  const report = {
    version,
    fixtureRoot,
    checks: [],
    stdout: [],
    stderr: [],
    passed: false,
  };

  try {
    writeFixture(fixtureRoot);
    const before = snapshot(fixtureRoot);
    const first = runSync(fixtureRoot);
    report.stdout.push(first.stdout);
    report.stderr.push(first.stderr);
    assert.equal(first.status, 0, first.stderr || first.stdout);
    const afterFirst = snapshot(fixtureRoot);
    const firstDiff = diff(before, afterFirst);
    fs.writeFileSync(path.join(artifactDir, "first.diff"), firstDiff, "utf8");

    const changelog = afterFirst["CHANGELOG.md"];
    assert.match(changelog, /releases\/download\/v1\.0\.0-beta\.1\//);
    assert.match(changelog, /## Changes in `v1\.0\.0-beta\.1:`\n\n## Changes in `v0\.11\.3:`/);
    assert.match(changelog, /^> \[!NOTE\]\n> 🅱️ This is a Beta build\./);
    assert.match(changelog, /Historical link: .*v0\.11\.3\/old\.zip/);
    assert.equal((changelog.match(/## Changes in `v1\.0\.0-beta\.1:`/g) || []).length, 1);
    assert.equal(afterFirst["package-lock.json"].includes('"version": "1.0.0-beta.1"'), true);
    assert.match(afterFirst["pubspec.yaml"], /version: 1\.0\.0-beta\.1\+10000/);
    report.checks.push("all version files and changelog updated");

    const second = runSync(fixtureRoot);
    report.stdout.push(second.stdout);
    report.stderr.push(second.stderr);
    assert.equal(second.status, 0, second.stderr || second.stdout);
    const afterSecond = snapshot(fixtureRoot);
    assert.deepEqual(afterSecond, afterFirst);
    report.checks.push("second run is byte-for-byte idempotent");
    report.passed = true;
  } finally {
    fs.writeFileSync(path.join(artifactDir, "run.log"), report.stdout.join("\n"), "utf8");
    fs.writeFileSync(path.join(artifactDir, "error.log"), report.stderr.join("\n"), "utf8");
    fs.writeFileSync(path.join(artifactDir, "report.json"), JSON.stringify(report, null, 2) + "\n", "utf8");
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
});

test("sync-version preserves CRLF, stable notice state, and current notes", () => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dacx-sync-stable-"));
  try {
    writeFixture(fixtureRoot);
    const packageJson = JSON.parse(fs.readFileSync(path.join(fixtureRoot, "package.json"), "utf8"));
    packageJson.version = "1.0.0";
    fs.writeFileSync(
      path.join(fixtureRoot, "package.json"),
      (JSON.stringify(packageJson, null, 2) + "\n").replace(/\n/g, "\r\n"),
    );
    for (const relative of Object.keys(fixtureFiles)) {
      if (relative === "package.json") continue;
      const target = path.join(fixtureRoot, relative);
      const original = fs.readFileSync(target, "utf8");
      fs.writeFileSync(target, original.replace(/\r?\n/g, "\r\n"), "utf8");
    }

    const result = runSync(fixtureRoot);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const changelog = fs.readFileSync(path.join(fixtureRoot, "CHANGELOG.md"), "utf8");
    assert.match(changelog, /^<!-- > \[!NOTE\]\r\n> 🅱️ This is a Beta build\. -->\r\n\r\n/);
    assert.match(changelog, /## Changes in `v1\.0\.0:`\r\n\r\n## Changes in `v0\.11\.3:`\r\n- Existing note\./);
    for (const relative of Object.keys(fixtureFiles)) {
      const contents = fs.readFileSync(path.join(fixtureRoot, relative), "utf8");
      assert.equal(contents.replace(/\r\n/g, "").includes("\n"), false, `${relative} changed EOL`);
    }
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
});

test("sync-version moves duplicate current section without losing its notes", () => {
  const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), "dacx-sync-current-"));
  try {
    writeFixture(fixtureRoot);
    const changelogPath = path.join(fixtureRoot, "CHANGELOG.md");
    const changelog = fs.readFileSync(changelogPath, "utf8").replace(
      "## Changes in `v0.11.3:`\n- Existing note.\n",
      "## Changes in `v0.11.3:`\n- Existing note.\n\n## Changes in `v1.0.0-beta.1:`\n- Preserve this note.\n",
    );
    fs.writeFileSync(changelogPath, changelog);
    const result = runSync(fixtureRoot);
    assert.equal(result.status, 0, result.stderr || result.stdout);
    const updated = fs.readFileSync(changelogPath, "utf8");
    assert.equal((updated.match(/## Changes in `v1\.0\.0-beta\.1:`/g) || []).length, 1);
    assert.match(updated, /## Changes in `v1\.0\.0-beta\.1:`\n- Preserve this note\.\n\n## Changes in `v0\.11\.3:`/);
  } finally {
    fs.rmSync(fixtureRoot, { recursive: true, force: true });
  }
});

test("sync-version writes nothing when lockfile or notice marker is malformed", () => {
  for (const malformed of ["lock", "notice"]) {
    const fixtureRoot = fs.mkdtempSync(path.join(os.tmpdir(), `dacx-sync-malformed-${malformed}-`));
    try {
      writeFixture(fixtureRoot);
      const target = malformed === "lock"
        ? path.join(fixtureRoot, "package-lock.json")
        : path.join(fixtureRoot, "CHANGELOG.md");
      const original = fs.readFileSync(target, "utf8");
      fs.writeFileSync(
        target,
        malformed === "lock"
          ? "{ invalid lockfile\n"
          : original.replace("-->\n\n#", "\n\n#"),
      );
      const before = snapshot(fixtureRoot);
      const result = runSync(fixtureRoot);
      assert.notEqual(result.status, 0, malformed);
      assert.deepEqual(snapshot(fixtureRoot), before, malformed);
    } finally {
      fs.rmSync(fixtureRoot, { recursive: true, force: true });
    }
  }
});
