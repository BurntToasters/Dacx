import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { afterEach, test } from "node:test";
import { fileURLToPath } from "node:url";

import { isDirectExecution as isModuleDirectExecution } from "./direct-execution.js";
import {
  CLI_FLAG,
  copyReleaseAssets,
  isDirectExecution,
  pathsEqual,
  run,
} from "./post-release-assets.js";

test("module entrypoint comparison tolerates Windows path casing", () => {
  const scriptUrl = new URL("./post-release-assets.js", import.meta.url);

  assert.equal(
    isModuleDirectExecution(
      scriptUrl.href,
      ["node", fileURLToPath(scriptUrl).toUpperCase()],
      "win32",
    ),
    true,
  );
});

const temporaryDirectories = [];

function makeTemporaryDirectory() {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), "dacx-finalize-"));
  temporaryDirectories.push(directory);
  return directory;
}

afterEach(() => {
  for (const directory of temporaryDirectories.splice(0)) {
    fs.rmSync(directory, { recursive: true, force: true });
  }
});

test("recognizes Windows paths without case sensitivity", () => {
  assert.equal(
    pathsEqual(
      "C:/Users/Main/Dacx/release",
      "c:/users/main/dacx/release",
      "win32",
    ),
    true,
  );
});

test("explicit finalizer flag does not depend on path identity", () => {
  assert.equal(
    isDirectExecution(["node", "unrelated.js", CLI_FLAG], "win32"),
    true,
  );
});

test("mirrors, verifies, and removes conflicting destination artifacts", () => {
  const root = makeTemporaryDirectory();
  const releaseDir = path.join(root, "release");
  const destination = path.join(root, "mirror");
  fs.mkdirSync(releaseDir);
  fs.mkdirSync(destination);
  fs.writeFileSync(path.join(releaseDir, "Dacx-Windows-x64.msi"), "installer");
  fs.writeFileSync(path.join(destination, "old-conflict.msi"), "stale");

  assert.deepEqual(run({ releaseDir, env: { AFTER_PACK_LOC: destination } }), {
    mirrored: true,
    destination,
    copiedEntries: 1,
  });
  assert.equal(
    fs.existsSync(path.join(destination, "old-conflict.msi")),
    false,
  );
  assert.equal(
    fs.readFileSync(path.join(destination, "Dacx-Windows-x64.msi"), "utf8"),
    "installer",
  );
});

test("fails instead of claiming success when release directory is missing", () => {
  const root = makeTemporaryDirectory();
  assert.throws(
    () =>
      copyReleaseAssets(path.join(root, "missing"), path.join(root, "mirror")),
    /release directory does not exist/,
  );
});

test("rejects a mirror inside the release directory", () => {
  const root = makeTemporaryDirectory();
  const releaseDir = path.join(root, "release");
  fs.mkdirSync(releaseDir);
  fs.writeFileSync(path.join(releaseDir, "artifact.msi"), "artifact");
  assert.throws(
    () => copyReleaseAssets(releaseDir, path.join(releaseDir, "mirror")),
    /cannot be inside the release directory/,
  );
});
