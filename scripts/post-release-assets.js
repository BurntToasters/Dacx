#!/usr/bin/env node

import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const RELEASE_DIR = path.join(__dirname, "..", "release");

const BUILD_ONLY_DIRECTORIES = [];
const BUILD_ONLY_FILES = [];

function removePath(targetPath) {
  fs.rmSync(targetPath, { recursive: true, force: true, maxRetries: 8, retryDelay: 100 });
}

function cleanReleaseArtifacts(releaseDir = RELEASE_DIR) {
  for (const dir of BUILD_ONLY_DIRECTORIES) {
    removePath(path.join(releaseDir, dir));
  }

  for (const file of BUILD_ONLY_FILES) {
    removePath(path.join(releaseDir, file));
  }
}

function getAfterPackLocation(env = process.env) {
  const value = env.AFTER_PACK_LOC;
  if (typeof value !== "string") {
    return "";
  }
  return value.trim();
}

function copyReleaseAssets(releaseDir = RELEASE_DIR, destination) {
  if (!destination) {
    return;
  }

  if (!fs.existsSync(releaseDir)) {
    return;
  }

  const resolvedReleaseDir = path.resolve(releaseDir);
  const resolvedDestination = path.resolve(destination);

  if (resolvedDestination === resolvedReleaseDir) {
    return;
  }

  if (resolvedDestination.startsWith(`${resolvedReleaseDir}${path.sep}`)) {
    throw new Error("AFTER_PACK_LOC cannot be inside the release directory");
  }

  fs.mkdirSync(resolvedDestination, { recursive: true });
  cleanMirrorDestination(resolvedDestination, releaseDir);
  const entries = fs.readdirSync(releaseDir);

  for (const entry of entries) {
    const sourcePath = path.join(releaseDir, entry);
    const destinationPath = path.join(resolvedDestination, entry);
    fs.cpSync(sourcePath, destinationPath, { recursive: true, force: true, errorOnExist: false });
  }
}

function cleanMirrorDestination(destination, releaseDir) {
  const releaseEntries = new Set(fs.readdirSync(releaseDir));
  const destinationEntries = fs.readdirSync(destination, { withFileTypes: true });

  for (const entry of destinationEntries) {
    const entryPath = path.join(destination, entry.name);
    if (releaseEntries.has(entry.name) || isConflictArtifact(entry.name)) {
      removePath(entryPath);
    }
  }
}

function isConflictArtifact(name) {
  const lower = name.toLowerCase();
  if (!lower.includes('-conflict')) return false;
  return (
    lower.endsWith('.deb') ||
    lower.endsWith('.rpm') ||
    lower.endsWith('.tar') ||
    lower.endsWith('.tar.gz') ||
    lower.endsWith('.zip') ||
    lower.endsWith('.appimage') ||
    lower.endsWith('.flatpak') ||
    lower.endsWith('.dmg') ||
    lower.endsWith('.exe') ||
    lower.endsWith('.msi') ||
    lower.endsWith('.pkg') ||
    lower.endsWith('.asc') ||
    lower.endsWith('.sig')
  );
}

function run({ releaseDir = RELEASE_DIR, env = process.env } = {}) {
  cleanReleaseArtifacts(releaseDir);

  const destination = getAfterPackLocation(env);
  if (!destination) {
    return { mirrored: false, destination: null };
  }

  copyReleaseAssets(releaseDir, destination);
  return { mirrored: true, destination: path.resolve(destination) };
}

if (process.argv[1] && path.resolve(process.argv[1]) === __filename) {
  try {
    const result = run();
    if (result.mirrored) {
      console.log(`Mirrored cleaned release assets to: ${result.destination}`);
    } else {
      console.log("Cleaned release assets; AFTER_PACK_LOC not set, mirror skipped.");
    }
  } catch (error) {
    const message =
      error && typeof error === "object" && "message" in error ? String(error.message) : String(error);
    console.error(`Failed to finalize release assets: ${message}`);
    process.exit(1);
  }
}

export {
  RELEASE_DIR,
  BUILD_ONLY_DIRECTORIES,
  BUILD_ONLY_FILES,
  cleanReleaseArtifacts,
  getAfterPackLocation,
  copyReleaseAssets,
  run,
};
