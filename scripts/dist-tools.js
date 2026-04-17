#!/usr/bin/env node

import fs from "fs";
import path from "path";

const FLATPAK_BUILD_DIR_PREFIX = "flatpak-build";

const CLEAN_TARGETS = {
  clean: ["dist", "build"],
  "clean-flatpak": ["flatpak-repo"],
  "clean-all": ["dist", "build", "release", "flatpak-repo"],
};

function listFlatpakBuildDirs(cwd) {
  try {
    return fs
      .readdirSync(cwd, { withFileTypes: true })
      .filter((entry) => {
        if (!entry.isDirectory()) return false;
        return (
          entry.name === FLATPAK_BUILD_DIR_PREFIX ||
          entry.name.startsWith(`${FLATPAK_BUILD_DIR_PREFIX}-`)
        );
      })
      .map((entry) => entry.name);
  } catch {
    return [];
  }
}

function getCleanTargets(mode, cwd) {
  const baseTargets = CLEAN_TARGETS[mode];
  if (!baseTargets) {
    throw new Error(`Unknown clean mode "${mode}"`);
  }

  if (mode === "clean-flatpak" || mode === "clean-all") {
    return Array.from(new Set([...baseTargets, ...listFlatpakBuildDirs(cwd)]));
  }

  return baseTargets;
}

function cleanDirs(mode) {
  const cwd = process.cwd();
  const dirs = getCleanTargets(mode, cwd);

  for (const relativeDir of dirs) {
    const dir = path.resolve(cwd, relativeDir);
    try {
      fs.rmSync(dir, {
        recursive: true,
        force: true,
        maxRetries: 8,
        retryDelay: 100,
      });
    } catch (error) {
      if (
        error &&
        typeof error === "object" &&
        "code" in error &&
        error.code === "ENOENT"
      ) {
        continue;
      }

      const message =
        error && typeof error === "object" && "message" in error
          ? String(error.message)
          : String(error);
      throw new Error(`Failed to clean "${relativeDir}": ${message}`);
    }
  }
}

const mode = process.argv[2];

if (mode === "clean" || mode === "clean-flatpak" || mode === "clean-all") {
  cleanDirs(mode);
  process.exit(0);
}

console.error(
  "Usage: node scripts/dist-tools.js <clean|clean-flatpak|clean-all>",
);
process.exit(1);
