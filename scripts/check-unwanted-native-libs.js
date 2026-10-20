import fs from "node:fs";
import path from "node:path";

// `dartjni` is the JNI bridge that the jni plugin builds on desktop when a JDK
// is present. Dacx never uses JNI on desktop, so it must not ship.
export const UNWANTED_NATIVE_LIB_PATTERN = /dartjni/iu;

function listEntriesRecursive(baseDir) {
  const out = [];

  function walk(currentDir, relDir) {
    for (const entry of fs.readdirSync(currentDir, { withFileTypes: true })) {
      const rel = relDir ? `${relDir}/${entry.name}` : entry.name;
      out.push(rel);
      // Symlinked directories are not followed, so the scan stays inside the bundle.
      if (entry.isDirectory()) walk(path.join(currentDir, entry.name), rel);
    }
  }

  walk(baseDir, "");
  return out;
}

export function checkUnwantedNativeLibs(bundleDir) {
  if (!fs.existsSync(bundleDir) || !fs.statSync(bundleDir).isDirectory()) {
    return {
      passed: false,
      found: [],
      failures: [`bundle directory not found: ${bundleDir}`],
    };
  }

  const found = listEntriesRecursive(bundleDir)
    .filter((rel) => UNWANTED_NATIVE_LIB_PATTERN.test(path.posix.basename(rel)))
    .sort();
  const failures = found.map(
    (rel) =>
      `unwanted native library in bundle: ${rel} (dartjni is the JNI bridge; Dacx does not use JNI on desktop)`,
  );
  return { passed: failures.length === 0, found, failures };
}
