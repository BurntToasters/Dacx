import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { fileURLToPath } from "node:url";

import { checkUnwantedNativeLibs } from "./check-unwanted-native-libs.js";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));

function tempBundle(files) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "dacx-unwanted-libs-"));
  for (const [rel, contents] of Object.entries(files)) {
    const full = path.join(dir, rel);
    fs.mkdirSync(path.dirname(full), { recursive: true });
    fs.writeFileSync(full, contents);
  }
  return dir;
}

function withBundle(files, assertions) {
  const dir = tempBundle(files);
  try {
    assertions(dir);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

const SETUP_FLAG = /^\s*set\(\s*CMAKE_DISABLE_FIND_PACKAGE_JNI\s+ON\s*\)/m;
const PLUGIN_INCLUDE = /^\s*include\(\s*flutter\/generated_plugins\.cmake\s*\)/m;

function disablesJniBeforePluginInclude(cmakeText) {
  const flag = SETUP_FLAG.exec(cmakeText);
  const include = PLUGIN_INCLUDE.exec(cmakeText);
  return Boolean(flag && include && flag.index < include.index);
}

test("a clean Windows bundle with unrelated DLLs passes", () => {
  withBundle(
    {
      "dacx.exe": "exe",
      "flutter_windows.dll": "dll",
      "libmpv-2.dll": "dll",
      "data/icudtl.dat": "icu",
    },
    (dir) => {
      const result = checkUnwantedNativeLibs(dir);
      assert.equal(result.passed, true);
      assert.deepEqual(result.found, []);
      assert.deepEqual(result.failures, []);
    },
  );
});

test("dartjni.dll at the top level of the Windows bundle fails", () => {
  withBundle({ "dacx.exe": "exe", "dartjni.dll": "dll" }, (dir) => {
    const result = checkUnwantedNativeLibs(dir);
    assert.equal(result.passed, false);
    assert.deepEqual(result.found, ["dartjni.dll"]);
    assert.match(result.failures.join("\n"), /dartjni\.dll/);
  });
});

test("libdartjni.so at the top level of the Linux bundle fails", () => {
  withBundle({ dacx: "elf", "libdartjni.so": "so" }, (dir) => {
    const result = checkUnwantedNativeLibs(dir);
    assert.equal(result.passed, false);
    assert.deepEqual(result.found, ["libdartjni.so"]);
  });
});

test("a dartjni library in the nested Linux lib directory fails with its relative path", () => {
  withBundle(
    { dacx: "elf", "lib/libmpv.so.2": "so", "lib/libdartjni.so": "so" },
    (dir) => {
      const result = checkUnwantedNativeLibs(dir);
      assert.equal(result.passed, false);
      assert.deepEqual(result.found, ["lib/libdartjni.so"]);
    },
  );
});

test("a dartjni name that differs only in case fails on Windows", () => {
  withBundle({ "DartJni.dll": "dll" }, (dir) => {
    const result = checkUnwantedNativeLibs(dir);
    assert.equal(result.passed, false);
    assert.deepEqual(result.found, ["DartJni.dll"]);
  });
});

test("unrelated libmpv libraries are not rejected", () => {
  withBundle(
    { "libmpv-2.dll": "dll", "lib/libmpv.so.2": "so" },
    (dir) => {
      const result = checkUnwantedNativeLibs(dir);
      assert.equal(result.passed, true);
      assert.deepEqual(result.found, []);
    },
  );
});

test("a missing bundle directory fails closed", () => {
  const missing = path.join(
    fs.mkdtempSync(path.join(os.tmpdir(), "dacx-unwanted-libs-")),
    "absent",
  );
  try {
    const result = checkUnwantedNativeLibs(missing);
    assert.equal(result.passed, false);
    assert.match(result.failures.join("\n"), /bundle directory not found/);
  } finally {
    fs.rmSync(path.dirname(missing), { recursive: true, force: true });
  }
});

test("the desktop CMake shells disable JNI discovery before including plugins", () => {
  for (const shell of ["windows", "linux"]) {
    const text = fs.readFileSync(
      path.join(root, shell, "CMakeLists.txt"),
      "utf-8",
    );
    assert.equal(
      disablesJniBeforePluginInclude(text),
      true,
      `${shell}/CMakeLists.txt must set CMAKE_DISABLE_FIND_PACKAGE_JNI before include(flutter/generated_plugins.cmake)`,
    );
  }
});

test("a CMake disable flag placed after the plugin include is rejected", () => {
  const misplaced = [
    "include(flutter/generated_plugins.cmake)",
    "set(CMAKE_DISABLE_FIND_PACKAGE_JNI ON)",
  ].join("\n");
  assert.equal(disablesJniBeforePluginInclude(misplaced), false);
  const missing = "include(flutter/generated_plugins.cmake)\n";
  assert.equal(disablesJniBeforePluginInclude(missing), false);
});
