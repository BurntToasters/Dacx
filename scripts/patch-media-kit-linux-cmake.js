#!/usr/bin/env node

/**
 * Patches media_kit_video Linux CMake for distro pkg-config differences.
 *
 * Why:
 * - Some distros expose libmpv as `libmpv` (not `mpv`) in pkg-config.
 * - Upstream media_kit_video links `PkgConfig::mpv` unconditionally, which
 *   fails when only `libmpv` is available.
 *
 * This script is safe to run repeatedly.
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cmakePath = path.join(
  root,
  "linux",
  "flutter",
  "ephemeral",
  ".plugin_symlinks",
  "media_kit_video",
  "linux",
  "CMakeLists.txt",
);

function patchCmakeFile(filePath) {
  if (!fs.existsSync(filePath)) {
    console.warn(
      "media_kit_video Linux CMakeLists.txt not found. " +
        "Run `flutter pub get` first, then run this script again.",
    );
    return false;
  }

  const original = fs.readFileSync(filePath, "utf8");
  const eol = original.includes("\r\n") ? "\r\n" : "\n";
  let text = original;

  if (!text.includes("pkg_check_modules(mpv IMPORTED_TARGET libmpv)")) {
    const oldLine = `  pkg_check_modules(mpv IMPORTED_TARGET mpv)${eol}`;
    const replacement =
      `  pkg_check_modules(mpv IMPORTED_TARGET mpv)${eol}` +
      `  if(NOT TARGET PkgConfig::mpv)${eol}` +
      `    pkg_check_modules(mpv IMPORTED_TARGET libmpv)${eol}` +
      `  endif()${eol}` +
      `  if(NOT TARGET PkgConfig::mpv)${eol}` +
      `    message(FATAL_ERROR "libmpv pkg-config module not found. Install libmpv-dev.")${eol}` +
      `  endif()${eol}`;
    text = text.replace(oldLine, replacement);
  }

  if (text === original) {
    console.log("media_kit Linux CMake patch: already up-to-date.");
    return true;
  }

  fs.writeFileSync(filePath, text, "utf8");
  console.log(`media_kit Linux CMake patch applied: ${path.relative(root, filePath)}`);
  return true;
}

patchCmakeFile(cmakePath);
