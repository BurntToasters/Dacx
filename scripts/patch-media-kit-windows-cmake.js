#!/usr/bin/env node

/**
 * Patches media_kit_libs_windows_video CMake for newer CMake/VS toolchains.
 *
 * Why:
 * - Older package versions omit PRE_BUILD/PRE_LINK/POST_BUILD in add_custom_command(TARGET ...).
 * - Some environments need 7-Zip extraction for .7z archives.
 *
 * This script is safe to run repeatedly.
 */

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const cmakePath = path.join(
  root,
  "windows",
  "flutter",
  "ephemeral",
  ".plugin_symlinks",
  "media_kit_libs_windows_video",
  "windows",
  "CMakeLists.txt",
);

function patchCmakeFile(filePath) {
  if (!fs.existsSync(filePath)) {
    console.warn(
      "media_kit_libs_windows_video CMakeLists.txt not found. " +
        "Run `flutter pub get` first, then run this script again.",
    );
    return false;
  }

  const original = fs.readFileSync(filePath, "utf8");
  const eol = original.includes("\r\n") ? "\r\n" : "\n";
  let text = original;

  if (!text.includes("cmake_policy(SET CMP0175")) {
    text = text.replace(
      `cmake_minimum_required(VERSION 3.14)${eol}`,
      `cmake_minimum_required(VERSION 3.14)${eol}cmake_policy(SET CMP0175 NEW)${eol}`,
    );
  }

  text = text.replace(
    /(TARGET\s+"\$\{PROJECT_NAME\}_LIBMPV_EXTRACT"\r?\n)(\s+)(COMMAND)/,
    `$1$2POST_BUILD${eol}$2$3`,
  );
  text = text.replace(
    /(TARGET\s+"\$\{PROJECT_NAME\}_ANGLE_EXTRACT"\r?\n)(\s+)(COMMAND)/,
    `$1$2POST_BUILD${eol}$2$3`,
  );

  const libmpvOld =
    'COMMAND "${CMAKE_COMMAND}" -E tar xzf "\\"${LIBMPV_ARCHIVE}\\""';
  const libmpvNew =
    'COMMAND cmd /c "where 7z >nul 2>nul && (7z x -y \\"${LIBMPV_ARCHIVE}\\") || (\\"${CMAKE_COMMAND}\\" -E tar xzf \\"${LIBMPV_ARCHIVE}\\")"';
  text = text.replace(libmpvOld, libmpvNew);

  const angleOld =
    'COMMAND "${CMAKE_COMMAND}" -E tar xzf "\\"${ANGLE_ARCHIVE}\\""';
  const angleNew =
    'COMMAND cmd /c "where 7z >nul 2>nul && (7z x -y \\"${ANGLE_ARCHIVE}\\") || (\\"${CMAKE_COMMAND}\\" -E tar xzf \\"${ANGLE_ARCHIVE}\\")"';
  text = text.replace(angleOld, angleNew);

  if (text === original) {
    console.log("media_kit CMake patch: already up-to-date.");
    return true;
  }

  fs.writeFileSync(filePath, text, "utf8");
  console.log(`media_kit CMake patch applied: ${path.relative(root, filePath)}`);
  return true;
}

patchCmakeFile(cmakePath);
