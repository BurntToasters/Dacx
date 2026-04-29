#!/usr/bin/env node

import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { run as finalizeAssets } from "./post-release-assets.js";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const root = path.resolve(__dirname, "..");

function runGit(args, options = {}) {
  const result = spawnSync("git", args, {
    cwd: root,
    encoding: "utf8",
    stdio: options.capture ? ["ignore", "pipe", "pipe"] : "inherit",
    shell: process.platform === "win32",
    windowsHide: true,
  });

  if (result.error) {
    throw result.error;
  }

  if (result.status !== 0) {
    const stderr = String(result.stderr || "").trim();
    const suffix = stderr ? `: ${stderr}` : "";
    throw new Error(`git ${args.join(" ")} failed${suffix}`);
  }

  return String(result.stdout || "").trim();
}

function ensureCleanWorkingTree() {
  const status = runGit(["status", "--porcelain"], { capture: true });
  if (status) {
    throw new Error(
      "Refusing destructive cleanup: working tree is not clean. Commit, stash, or discard changes first.",
    );
  }
}

function ensureUpstreamExists() {
  runGit(["rev-parse", "--abbrev-ref", "@{u}"], { capture: true });
}

function cleanupRepo() {
  ensureCleanWorkingTree();
  ensureUpstreamExists();
  runGit(["fetch", "origin"]);
  runGit(["reset", "--hard", "@{u}"]);
  runGit(["clean", "-fd"]);
}

function main() {
  const shouldClean = process.argv.includes("--clean");
  const result = finalizeAssets();

  if (!shouldClean) {
    if (result.mirrored) {
      console.log(`Mirrored cleaned release assets to: ${result.destination}`);
    } else {
      console.log("Cleaned release assets; repo cleanup skipped.");
    }
    return;
  }

  cleanupRepo();

  if (result.mirrored) {
    console.log(`Mirrored cleaned release assets to: ${result.destination}`);
  }
  console.log("Repository cleanup completed.");
}

try {
  main();
} catch (error) {
  const message =
    error && typeof error === "object" && "message" in error
      ? String(error.message)
      : String(error);
  console.error(`Release finalize failed: ${message}`);
  process.exit(1);
}
