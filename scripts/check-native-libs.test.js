import assert from "node:assert/strict";
import crypto from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { checkWindowsLibmpvArchives, PINNED_LIBMPV_ARCHIVES } from "./check-native-libs.js";

function tempBuild(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dacx-native-"));
  for (const [name, contents] of Object.entries(files)) {
    fs.writeFileSync(path.join(dir, name), contents);
  }
  return dir;
}

test("pinned archive list names the refreshed official build", () => {
  assert.ok(PINNED_LIBMPV_ARCHIVES["mpv-dev-x86_64-20241021-git-0f78584.7z"]);
});

test("an unpinned or stale archive fails the check", () => {
  const dir = tempBuild({ "mpv-dev-x86_64-20230924-git-652a1dd.7z": "old" });
  try {
    const result = checkWindowsLibmpvArchives(dir);
    assert.equal(result.passed, false);
    assert.match(result.failures.join("\n"), /not pinned/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("a pinned name with the wrong bytes fails the check", () => {
  const dir = tempBuild({ "mpv-dev-x86_64-20241021-git-0f78584.7z": "tampered" });
  try {
    const result = checkWindowsLibmpvArchives(dir);
    assert.equal(result.passed, false);
    assert.match(result.failures.join("\n"), /SHA-256 mismatch/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test("matching bytes pass, and a missing archive fails", () => {
  const contents = "pinned-for-test";
  const name = "mpv-dev-x86_64-test.7z";
  const sha = crypto.createHash("sha256").update(contents).digest("hex");
  const dir = tempBuild({ [name]: contents });
  try {
    assert.equal(checkWindowsLibmpvArchives(dir, { [name]: sha }).passed, true);
    fs.rmSync(path.join(dir, name));
    assert.equal(checkWindowsLibmpvArchives(dir, { [name]: sha }).passed, false);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});
