#!/usr/bin/env node

/**
 * Deterministic fixture and release-package smoke harness.
 *
 * Fixture generation is safe on every host. Package proof is intentionally
 * fail-closed: a report is `passed` only after artifact, launch/playback, and
 * host trust checks pass. `--no-launch` is useful for inspecting a candidate,
 * but returns exit code 2 and never claims release proof.
 *
 * Examples:
 *   node scripts/platform-release-smoke.js fixtures \
 *     --output test-results/e2e/windows/fixtures \
 *     --report test-results/e2e/windows/fixture-report.json
 *   node scripts/platform-release-smoke.js package --platform win \
 *     --artifact release/Dacx-Windows-x64.msi \
 *     --executable C:/Program\ Files/Dacx/dacx.exe \
 *     --fixture test-results/e2e/windows/fixtures/release-smoke.wav \
 *     --report test-results/release-proof/1.0.0/windows.json
 */

import { spawn, spawnSync } from "node:child_process";
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ROOT = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const FIXTURE_WAV = "release-smoke.wav";
const FIXTURE_SRT = "release-smoke.srt";
const DEFAULT_SMOKE_MS = 8_000;

function usage() {
  console.error(`Usage:
  node scripts/platform-release-smoke.js fixtures --output DIR --report FILE
  node scripts/platform-release-smoke.js package --platform win|mac|linux \
    --artifact FILE --report FILE --version VERSION [--fixture FILE]

Package options:
  --signature FILE       GPG detached signature for artifact
  --checksums FILE       sha256sum-style file containing artifact hash
  --expected-sha256 HEX  Expected artifact hash
  --proof-metadata FILE  JSON version/hash binding for this artifact
  --manifest FILE        Alias for --proof-metadata
  --smoke-ms N           Keep launched app alive for N milliseconds
  --extract              Extract/install package into report staging directory
  --no-launch            Inspect artifact only; exits 2 (incomplete)
  --executable FILE      Executable path, bound to extracted artifact when possible
  --launcher COMMAND     Wrapper command (for example flatpak)
  --launch-arg ARG       Repeated argument passed to launcher before fixture
  --wrapper-arg ARG      Alias for --launch-arg
  --playback-report FILE Receipt produced by candidate app probe
  --require-path PATH    Required path next to explicit executable (repeatable)`);
}

function parseArgs(argv) {
  const [command, ...rest] = argv;
  const args = { command, requirePaths: [] };
  for (let i = 0; i < rest.length; i += 1) {
    const value = rest[i];
    if (!value.startsWith("--")) {
      throw new Error(`Unexpected argument: ${value}`);
    }
    const key = value.slice(2);
    if (key === "no-launch") {
      args.noLaunch = true;
      continue;
    }
    if (key === "extract") {
      args.extract = true;
      continue;
    }
    const next = rest[i + 1];
    const acceptsFlagValue = ["launch-arg", "wrapper-arg"].includes(key);
    if (next == null || (next.startsWith("--") && !acceptsFlagValue)) {
      throw new Error(`Missing value for --${key}`);
    }
    i += 1;
    if (key === "require-path") {
      args.requirePaths.push(next);
    } else if (key === "launch-arg" || key === "wrapper-arg") {
      args.launch_args ??= [];
      args.launch_args.push(next);
    } else {
      const normalizedKey = key.replaceAll("-", "_");
      args[normalizedKey] = next;
      if (key === "manifest") args.proof_metadata = next;
    }
  }
  return args;
}

function ensureParent(filePath) {
  fs.mkdirSync(path.dirname(path.resolve(filePath)), { recursive: true });
}

function writeReport(filePath, report) {
  ensureParent(filePath);
  const temp = `${filePath}.tmp-${process.pid}`;
  fs.writeFileSync(temp, `${JSON.stringify(report, null, 2)}\n`, "utf8");
  fs.renameSync(temp, filePath);
}

function writeLog(reportPath, text) {
  const logPath = `${reportPath}.log`;
  ensureParent(logPath);
  fs.writeFileSync(logPath, text ?? "", "utf8");
  return logPath;
}

function sha256File(filePath) {
  const hash = crypto.createHash("sha256");
  hash.update(fs.readFileSync(filePath));
  return hash.digest("hex");
}

function writeDeterministicWav(filePath) {
  const sampleRate = 44_100;
  const seconds = 6;
  const channels = 1;
  const bitsPerSample = 16;
  const sampleCount = sampleRate * seconds;
  const dataSize = sampleCount * channels * (bitsPerSample / 8);
  const buffer = Buffer.alloc(44 + dataSize);
  buffer.write("RIFF", 0, "ascii");
  buffer.writeUInt32LE(36 + dataSize, 4);
  buffer.write("WAVE", 8, "ascii");
  buffer.write("fmt ", 12, "ascii");
  buffer.writeUInt32LE(16, 16);
  buffer.writeUInt16LE(1, 20);
  buffer.writeUInt16LE(channels, 22);
  buffer.writeUInt32LE(sampleRate, 24);
  buffer.writeUInt32LE(sampleRate * channels * (bitsPerSample / 8), 28);
  buffer.writeUInt16LE(channels * (bitsPerSample / 8), 32);
  buffer.writeUInt16LE(bitsPerSample, 34);
  buffer.write("data", 36, "ascii");
  buffer.writeUInt32LE(dataSize, 40);

  // Silent PCM still exercises decoding, duration, and playing state without
  // making release automation emit an unexpected test tone.
  for (let i = 0; i < sampleCount; i += 1) {
    buffer.writeInt16LE(0, 44 + i * 2);
  }
  fs.writeFileSync(filePath, buffer);
}

function writeDeterministicSrt(filePath) {
  fs.writeFileSync(
    filePath,
    "1\n00:00:00,000 --> 00:00:05,500\nDacx release smoke fixture\n\n",
    "utf8",
  );
}

function createFixtures(outputDir, reportPath) {
  fs.mkdirSync(outputDir, { recursive: true });
  const wavPath = path.join(outputDir, FIXTURE_WAV);
  const srtPath = path.join(outputDir, FIXTURE_SRT);
  writeDeterministicWav(wavPath);
  writeDeterministicSrt(srtPath);
  const files = [wavPath, srtPath].map((filePath) => ({
    name: path.basename(filePath),
    bytes: fs.statSync(filePath).size,
    sha256: sha256File(filePath),
  }));
  const report = {
    schema: "dacx.e2e.fixture.v1",
    status: "passed",
    directory: path.resolve(outputDir),
    files,
  };
  writeReport(reportPath, report);
  return report;
}

function commandText(command, args) {
  return [command, ...args]
    .map((part) => (/\s/.test(part) ? JSON.stringify(part) : part))
    .join(" ");
}

function runCaptured(command, args, options = {}) {
  const started = Date.now();
  const result = spawnSync(command, args, {
    cwd: options.cwd ?? ROOT,
    encoding: "utf8",
    timeout: options.timeout ?? 30_000,
    windowsHide: true,
    env: options.env,
  });
  const stdout = result.stdout ?? "";
  const stderr = result.stderr ?? "";
  return {
    command: commandText(command, args),
    code: result.status,
    signal: result.signal ?? null,
    timedOut: Boolean(result.error?.code === "ETIMEDOUT"),
    stdout,
    stderr,
    output: `${stdout}${stderr}`,
    elapsedMs: Date.now() - started,
  };
}

function commandExists(command) {
  const lookup = process.platform === "win32" ? "where.exe" : "which";
  return spawnSync(lookup, [command], {
    encoding: "utf8",
    windowsHide: true,
  }).status === 0;
}

function hostForPackage(platform) {
  if (platform === "win") return "win32";
  if (platform === "mac") return "darwin";
  return "linux";
}

function checkExpectedHash(actual, args) {
  if (args.expected_sha256) {
    const expected = String(args.expected_sha256).trim().toLowerCase();
    return {
      status: /^[a-f0-9]{64}$/.test(expected) && expected === actual ? "passed" : "failed",
      expected,
      actual,
    };
  }
  return { status: "skipped", reason: "No --expected-sha256 supplied", actual };
}

function checkChecksums(artifact, args) {
  if (!args.checksums) {
    return { status: "skipped", reason: "No --checksums supplied" };
  }
  if (!fs.existsSync(args.checksums)) {
    return { status: "failed", reason: `Checksum file does not exist: ${args.checksums}` };
  }
  const actual = sha256File(artifact);
  const baseName = path.basename(artifact).replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = fs
    .readFileSync(args.checksums, "utf8")
    .split(/\r?\n/)
    .map((line) => line.trim())
    .find((line) => new RegExp(`^([a-f0-9]{64})\\s+[* ]?${baseName}$`, "i").test(line));
  if (!match) {
    return { status: "failed", reason: `No hash entry for ${path.basename(artifact)}` };
  }
  const expected = match.match(/^([a-f0-9]{64})/i)[1].toLowerCase();
  return {
    status: expected === actual ? "passed" : "failed",
    expected,
    actual,
  };
}

function checkProofMetadata(artifact, actualHash, args) {
  if (!args.proof_metadata) {
    return {
      status: "incomplete",
      reason: "--proof-metadata is required to bind release version and artifact",
    };
  }
  if (!fs.existsSync(args.proof_metadata)) {
    return {
      status: "failed",
      reason: `Proof metadata does not exist: ${args.proof_metadata}`,
    };
  }
  let metadata;
  try {
    metadata = JSON.parse(fs.readFileSync(args.proof_metadata, "utf8"));
  } catch (error) {
    return { status: "failed", reason: `Invalid proof metadata JSON: ${error.message}` };
  }
  const version = metadata.version ?? metadata.releaseVersion ?? metadata.release?.version;
  const artifactEntry =
    metadata.artifacts?.[path.basename(artifact)] ??
    metadata.artifact ??
    metadata.files?.[path.basename(artifact)];
  const expectedSha256 = String(
    artifactEntry?.sha256 ?? artifactEntry?.hash ?? metadata.sha256 ?? metadata.artifactSha256 ?? "",
  ).toLowerCase();
  const versionMatches = typeof version === "string" && version === String(args.version);
  const hashMatches = /^[a-f0-9]{64}$/.test(expectedSha256) && expectedSha256 === actualHash;
  const hasBinding = typeof version === "string" && Boolean(expectedSha256);
  return {
    status: versionMatches && hashMatches ? "passed" : hasBinding ? "failed" : "incomplete",
    source: path.resolve(args.proof_metadata),
    expectedVersion: version ?? null,
    actualVersion: String(args.version),
    expectedSha256: expectedSha256 || null,
    actualSha256: actualHash,
    executableSha256: metadata.executableSha256 ?? metadata.executable?.sha256 ?? null,
    flatpakAppId:
      artifactEntry?.flatpakAppId ?? metadata.flatpakAppId ?? metadata.appId ?? metadata.packageId ?? null,
    reason:
      versionMatches && hashMatches
        ? undefined
        : !versionMatches
          ? "Proof metadata version does not match --version"
          : !hashMatches
            ? "Proof metadata artifact hash does not match artifact"
            : "Proof metadata must include version and artifact sha256",
  };
}

function isSafeArchiveEntry(entry) {
  const normalized = String(entry).replaceAll("\\", "/");
  if (!normalized || normalized === "." || normalized === "./") return true;
  if (normalized.startsWith("/") || /^[A-Za-z]:\//.test(normalized)) return false;
  const collapsed = path.posix.normalize(normalized);
  return collapsed !== ".." && !collapsed.startsWith("../");
}

function existingFilePath(value) {
  if (!value || typeof value !== "string") return null;
  const resolved = path.resolve(value);
  return fs.existsSync(resolved) && fs.statSync(resolved).isFile() ? resolved : null;
}

function resolveLaunchCommand(value) {
  if (!value) return null;
  const file = existingFilePath(value);
  if (file) return file;
  if (commandExists(value)) return value;
  return path.resolve(value);
}

function checkRequiredPaths(executable, paths) {
  return paths.map((requiredPath) => {
    const resolved = path.isAbsolute(requiredPath)
      ? requiredPath
      : path.join(path.dirname(executable), requiredPath);
    return {
      path: resolved,
      exists: fs.existsSync(resolved),
      status: fs.existsSync(resolved) ? "passed" : "failed",
    };
  });
}

function artifactFormat(platform, filePath) {
  const name = path.basename(filePath).toLowerCase();
  if (platform === "win" && (name.endsWith(".msi") || name.endsWith(".exe"))) {
    return name.endsWith(".msi") ? "msi" : "exe";
  }
  if (platform === "mac" && (name.endsWith(".dmg") || name.endsWith(".zip"))) {
    return name.endsWith(".dmg") ? "dmg" : "zip";
  }
  if (platform === "linux") {
    if (name.endsWith(".appimage")) return "appimage";
    if (name.endsWith(".flatpak")) return "flatpak";
    if (name.endsWith(".tar.gz")) return "tar.gz";
    if (name.endsWith(".deb")) return "deb";
    if (name.endsWith(".rpm")) return "rpm";
  }
  return null;
}

function findPackagedExecutable(directory, macApp = false) {
  if (!fs.existsSync(directory)) return null;
  const entries = fs.readdirSync(directory, { withFileTypes: true });
  for (const entry of entries) {
    const candidate = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (macApp && entry.name.toLowerCase().endsWith(".app")) {
        const appBinary = findPackagedExecutable(
          path.join(candidate, "Contents", "MacOS"),
        );
        if (appBinary) return appBinary;
      }
      const nested = findPackagedExecutable(candidate, macApp);
      if (nested) return nested;
      continue;
    }
    const lower = entry.name.toLowerCase();
    if (lower === "dacx.exe" || lower === "dacx") return candidate;
  }
  return null;
}

function prepareDmgExtraction({ artifact, staging, run }) {
  const mount = path.join(staging, "mount");
  fs.mkdirSync(mount, { recursive: true });
  let attached = false;
  let outcome = {
    executable: null,
    cleanup: staging,
    status: "failed",
    reason: "DMG app bundle missing or copy failed",
    detach: { status: "skipped" },
  };
  try {
    const attachedResult = run("hdiutil", [
      "attach",
      artifact,
      "-mountpoint",
      mount,
      "-nobrowse",
      "-readonly",
      "-noautoopen",
    ]);
    if (attachedResult.code !== 0) {
      outcome.reason = "DMG attach failed";
    } else {
      attached = true;
      const app = fs
        .readdirSync(mount, { withFileTypes: true })
        .map((entry) => path.join(mount, entry.name))
        .find((candidate) => candidate.toLowerCase().endsWith(".app"));
      const copy = app
        ? run("ditto", [app, path.join(staging, path.basename(app))])
        : null;
      if (app && copy?.code === 0) {
        outcome = {
          executable: findPackagedExecutable(staging, true),
          cleanup: staging,
          status: "passed",
          detach: { status: "skipped" },
        };
      }
    }
  } catch (error) {
    outcome = {
      executable: null,
      cleanup: staging,
      status: "failed",
      reason: error.message,
      detach: { status: "skipped" },
    };
  } finally {
    if (attached) {
      try {
        const detached = run("hdiutil", ["detach", mount, "-force"]);
        outcome.detach = {
          status: detached.code === 0 ? "passed" : "failed",
          command: detached.command,
          output: detached.output?.trim() ?? "",
        };
        if (detached.code !== 0 && outcome.status === "passed") {
          outcome.status = "failed";
          outcome.reason = "DMG detach failed";
        }
      } catch (error) {
        outcome.detach = { status: "failed", reason: error.message };
        outcome.status = "failed";
        outcome.reason = "DMG detach failed";
      }
    }
  }
  return outcome;
}

function prepareTarExtraction({ artifact, staging, run }) {
  const listing = run("tar", ["-tzf", artifact]);
  if (listing.code !== 0) {
    return {
      executable: null,
      cleanup: staging,
      status: "failed",
      reason: "Linux tar listing failed",
    };
  }
  const unsafeEntry = listing.output
    .split(/\r?\n/)
    .map((entry) => entry.trim())
    .find((entry) => entry && !isSafeArchiveEntry(entry));
  if (unsafeEntry) {
    return {
      executable: null,
      cleanup: staging,
      status: "failed",
      reason: `Unsafe tar entry rejected: ${unsafeEntry}`,
    };
  }
  const result = run("tar", [
    "--extract",
    "--gzip",
    "--file",
    artifact,
    "--directory",
    staging,
    "--no-same-owner",
    "--no-same-permissions",
  ]);
  if (result.code !== 0) {
    return { executable: null, cleanup: staging, status: "failed", reason: "Linux tar extraction failed" };
  }
  return { executable: findPackagedExecutable(staging), cleanup: staging, status: "passed" };
}

function packageBindingForExecutable({ artifact, executable, format, preparation, metadata, launchArgs }) {
  if (!executable) {
    return { status: "incomplete", mode: "missing", reason: "No executable or launcher was supplied" };
  }
  const executablePath = existingFilePath(executable);
  if (executablePath && path.resolve(executablePath) === path.resolve(artifact) && format === "appimage") {
    return { status: "passed", mode: "artifact", path: executablePath };
  }
  if (preparation.binding?.status === "passed") return preparation.binding;
  if (
    preparation.binding?.mode === "wrapper" &&
    format === "flatpak" &&
    metadata?.flatpakAppId &&
    (launchArgs ?? []).includes(String(metadata.flatpakAppId))
  ) {
    return {
      status: "passed",
      mode: "proof-metadata-wrapper",
      launcher: executable,
      appId: metadata.flatpakAppId,
    };
  }
  if (executablePath && metadata?.executableSha256) {
    const actual = sha256File(executablePath);
    const expected = String(metadata.executableSha256).toLowerCase();
    if (/^[a-f0-9]{64}$/.test(expected) && actual === expected) {
      return { status: "passed", mode: "proof-metadata", path: executablePath, sha256: actual };
    }
    return {
      status: "failed",
      mode: "proof-metadata",
      path: executablePath,
      expectedSha256: expected,
      actualSha256: actual,
      reason: "Executable hash does not match proof metadata",
    };
  }
  if (preparation.binding) return preparation.binding;
  if (executablePath) {
    return {
      status: "failed",
      mode: "external",
      path: executablePath,
      reason: "Executable is not demonstrably produced by this artifact",
    };
  }
  return {
    status: "incomplete",
    mode: executablePath ? "external" : "wrapper",
    path: executablePath ?? executable,
    reason: "Executable is not demonstrably produced by this artifact",
  };
}

function preparePackageExecutable({ platform, format, artifact, args, log }) {
  const launchArgs = args.launch_args ?? [];
  const requested = args.executable ? resolveLaunchCommand(args.executable) : null;
  const launcher = args.launcher ? resolveLaunchCommand(args.launcher) : null;
  if (!args.extract && (requested || launcher)) {
    const executable = requested ?? launcher;
    const executablePath = existingFilePath(executable);
    const binding = requested
      ? executablePath && path.resolve(executablePath) === path.resolve(artifact) && format === "appimage"
        ? { status: "passed", mode: "artifact", path: executablePath }
        : {
            status: "failed",
            mode: "external",
            path: executablePath ?? executable,
            reason: "Explicit executable is not demonstrably produced by this artifact",
          }
      :
      executablePath && path.resolve(executablePath) === path.resolve(artifact) && format === "appimage"
        ? { status: "passed", mode: "artifact", path: executablePath }
        : {
            status: "incomplete",
            mode: executablePath ? "external" : "wrapper",
            path: executablePath ?? executable,
            reason: "Executable is not demonstrably produced by this artifact",
          };
    return {
      executable,
      launchArgs,
      cleanup: null,
      status: executable ? "passed" : "failed",
      binding,
    };
  }
  if (args.noLaunch && !args.extract) {
    return { executable: null, launchArgs, cleanup: null, status: "skipped", binding: null };
  }
  if (platform === "linux" && format === "appimage" && !args.extract) {
    if (process.platform !== "linux") {
      return {
        executable: null,
        launchArgs,
        cleanup: null,
        status: "skipped",
        reason: "AppImage launch requires Linux host",
        binding: null,
      };
    }
    try {
      fs.chmodSync(artifact, 0o755);
    } catch (error) {
      return { executable: null, launchArgs, cleanup: null, status: "failed", reason: error.message, binding: null };
    }
    return {
      executable: artifact,
      launchArgs,
      cleanup: null,
      status: "passed",
      binding: { status: "passed", mode: "artifact", path: artifact },
    };
  }
  if (args.extract !== "true" && args.extract !== true) {
    return {
      executable: null,
      launchArgs,
      cleanup: null,
      status: "skipped",
      reason: "Pass --extract, --executable, or --launcher to prepare package for launch",
      binding: null,
    };
  }

  const staging = path.join(
    path.dirname(path.resolve(args.report)),
    `.package-staging-${platform}-${process.pid}`,
  );
  fs.rmSync(staging, { recursive: true, force: true });
  fs.mkdirSync(staging, { recursive: true });
  const run = (command, commandArgs) => {
    const result = runCaptured(command, commandArgs, { timeout: 120_000 });
    log.push(result);
    return result;
  };
  let prepared;
  if (platform === "win" && format === "msi") {
    if (!commandExists("msiexec.exe")) {
      prepared = { executable: null, cleanup: staging, status: "skipped", reason: "msiexec.exe unavailable" };
    } else {
      const result = run("msiexec.exe", [
        "/a",
        artifact,
        "/qn",
        "/norestart",
        `TARGETDIR=${staging}`,
      ]);
      prepared = result.code !== 0
        ? { executable: null, cleanup: staging, status: "failed", reason: "MSI administrative extraction failed" }
        : { executable: findPackagedExecutable(staging), cleanup: staging, status: "passed" };
    }
  } else if (platform === "mac" && format === "zip") {
    if (!commandExists("ditto")) {
      prepared = { executable: null, cleanup: staging, status: "skipped", reason: "ditto unavailable" };
    } else {
      const result = run("ditto", ["-x", "-k", artifact, staging]);
      prepared = result.code !== 0
        ? { executable: null, cleanup: staging, status: "failed", reason: "macOS ZIP extraction failed" }
        : { executable: findPackagedExecutable(staging, true), cleanup: staging, status: "passed" };
    }
  } else if (platform === "mac" && format === "dmg") {
    prepared = !commandExists("hdiutil") || !commandExists("ditto")
      ? {
          executable: null,
          cleanup: staging,
          status: "skipped",
          reason: "hdiutil or ditto unavailable",
        }
      : prepareDmgExtraction({ artifact, staging, run });
  } else if (platform === "linux" && format === "tar.gz") {
    prepared = prepareTarExtraction({ artifact, staging, run });
  } else {
    prepared = {
      executable: null,
      cleanup: staging,
      status: "skipped",
      reason: `Automatic preparation is unavailable for ${platform}/${format}; pass --executable`,
    };
  }

  const extracted = prepared.executable;
  if (requested) {
    const requestedPath = existingFilePath(requested);
    const stagingPrefix = `${path.resolve(staging)}${path.sep}`;
    if (requestedPath && requestedPath.startsWith(stagingPrefix)) {
      prepared.executable = requestedPath;
      prepared.binding = { status: "passed", mode: "extracted", path: requestedPath, staging };
    } else {
      prepared.binding = {
        status: "failed",
        mode: "extracted",
        path: requestedPath ?? requested,
        reason: "Explicit executable is outside extracted package staging",
      };
    }
  } else if (prepared.executable) {
    prepared.binding = { status: "passed", mode: "extracted", path: prepared.executable, staging };
  }
  prepared.launchArgs = launchArgs;
  return prepared;
}

function enclosingMacApp(filePath) {
  let current = path.resolve(filePath);
  while (current !== path.dirname(current)) {
    if (current.toLowerCase().endsWith(".app")) return current;
    current = path.dirname(current);
  }
  return null;
}

function runTrustChecks(platform, artifact, executable, args, log) {
  const checks = [];
  const host = process.platform;
  if (host !== hostForPackage(platform)) {
    checks.push({
      name: "platform-trust",
      status: "skipped",
      reason: `Package target ${platform} cannot be verified on host ${host}`,
    });
    return checks;
  }

  if (platform === "win") {
    if (!commandExists("powershell.exe")) {
      checks.push({ name: "authenticode", status: "skipped", reason: "powershell.exe unavailable" });
    } else {
      const targets = [artifact];
      const executablePath = existingFilePath(executable);
      if (executablePath && path.resolve(executablePath) !== path.resolve(artifact)) {
        targets.push(executablePath);
      }
      for (const target of targets) {
        const result = runCaptured(
          "powershell.exe",
          [
            "-NoProfile",
            "-NonInteractive",
            "-Command",
            `(Get-AuthenticodeSignature -LiteralPath '${String(target).replaceAll("'", "''")}').Status`,
          ],
        );
        log.push(result);
        checks.push({
          name: `authenticode:${path.basename(target)}`,
          status: result.code === 0 && result.stdout.trim() === "Valid" ? "passed" : "failed",
          command: result.command,
          output: result.output.trim(),
        });
      }
    }
  }

  if (platform === "mac") {
    const executablePath = existingFilePath(executable);
    const target = enclosingMacApp(executablePath ?? artifact) ?? executablePath ?? artifact;
    for (const [name, command, commandArgs] of [
      ["codesign", "codesign", ["--verify", "--deep", "--strict", "--verbose=2", target]],
      ["gatekeeper", "spctl", ["--assess", "--type", "execute", "--verbose", target]],
    ]) {
      if (!commandExists(command)) {
        checks.push({ name, status: "skipped", reason: `${command} unavailable` });
        continue;
      }
      const result = runCaptured(command, commandArgs);
      log.push(result);
      checks.push({
        name,
        status: result.code === 0 ? "passed" : "failed",
        command: result.command,
        output: result.output.trim(),
      });
    }
  }

  if (platform === "linux") {
    if (args.signature) {
      if (!commandExists("gpg")) {
        checks.push({ name: "gpg-signature", status: "skipped", reason: "gpg unavailable" });
      } else if (!fs.existsSync(args.signature)) {
        checks.push({ name: "gpg-signature", status: "failed", reason: "Signature file does not exist" });
      } else {
        const result = runCaptured("gpg", ["--batch", "--status-fd", "1", "--verify", args.signature, artifact]);
        log.push(result);
        checks.push({
          name: "gpg-signature",
          status: result.code === 0 && result.stdout.includes("[GNUPG:] GOODSIG") ? "passed" : "failed",
          command: result.command,
          output: result.output.trim(),
        });
      }
    } else {
      checks.push({ name: "gpg-signature", status: "skipped", reason: "No --signature supplied" });
    }
  }
  return checks;
}

function cleanupProcessTree(child) {
  if (!child?.pid) return { status: "skipped", reason: "Child process has no PID" };
  if (process.platform === "win32") {
    const result = runCaptured("taskkill.exe", ["/PID", String(child.pid), "/T", "/F"], {
      timeout: 10_000,
    });
    return {
      status: result.code === 0 ? "passed" : "incomplete",
      command: result.command,
      output: result.output.trim(),
      code: result.code,
    };
  }
  let status = "passed";
  let reason = "";
  try {
    process.kill(-child.pid, "SIGTERM");
  } catch (error) {
    status = "failed";
    reason = error.message;
  }
  return { status, reason, signal: "SIGTERM" };
}

function readPlaybackReceipt(filePath, { runId, version, fixtureSha256, startedAt }) {
  if (!filePath) {
    return {
      status: "incomplete",
      reason: "No --playback-report supplied; process survival is not playback proof",
    };
  }
  if (!fs.existsSync(filePath)) {
    return { status: "incomplete", reason: `Playback receipt was not produced: ${filePath}` };
  }
  const stat = fs.statSync(filePath);
  if (stat.mtimeMs < startedAt) {
    return { status: "failed", reason: "Playback receipt predates this smoke run" };
  }
  let receipt;
  try {
    receipt = JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch (error) {
    return { status: "failed", reason: `Invalid playback receipt JSON: ${error.message}` };
  }
  const durationMs = Number(receipt.checks?.durationMs ?? receipt.durationMs ?? 0);
  const playing = receipt.checks?.playing === true || receipt.playing === true;
  const errorText = receipt.checks?.error ?? receipt.error ?? null;
  const fixtureMatch =
    !fixtureSha256 || receipt.fixture?.sha256 === fixtureSha256 || receipt.fixtureSha256 === fixtureSha256;
  const valid =
    receipt.schema === "dacx.e2e.desktop-playback.v1" &&
    receipt.version === version &&
    receipt.runId === runId &&
    receipt.status === "passed" &&
    receipt.releaseProof === true &&
    durationMs > 0 &&
    playing &&
    !errorText &&
    fixtureMatch;
  return {
    status: valid ? "passed" : "failed",
    schema: receipt.schema ?? null,
    version: receipt.version ?? null,
    runId: receipt.runId ?? null,
    durationMs,
    playing,
    error: errorText,
    fixtureMatch,
    reason: valid ? undefined : "Playback receipt did not prove duration, playing state, version, run, and no error",
  };
}

function spawnForSmoke({ command, launchArgs, fixture, smokeMs, log, playbackReport, version, fixtureSha256 }) {
  return new Promise((resolve) => {
    const started = Date.now();
    const runId = crypto.randomUUID();
    let output = "";
    let finished = false;
    let timedOut = false;
    let cleanup = { status: "skipped", reason: "Process exited before timeout" };
    let args = [...(launchArgs ?? []), ...(fixture ? [fixture] : [])];
    // Node treats wrapper-like flags as process options unless `--` ends its
    // option section. Keep synthetic Node launchers usable in deterministic
    // tests while leaving real app launchers unchanged.
    if (path.resolve(command) === path.resolve(process.execPath)) {
      const evaluateIndex = args.findIndex((arg) => arg === "-e" || arg === "--eval");
      if (evaluateIndex >= 0 && evaluateIndex + 1 < args.length) {
        args = [
          ...args.slice(0, evaluateIndex + 2),
          "--",
          ...args.slice(evaluateIndex + 2),
        ];
      }
    }
    if (playbackReport) {
      try {
        fs.rmSync(playbackReport, { force: true });
      } catch (error) {
        log.push({ reason: `Could not clear stale playback report: ${error.message}` });
      }
    }
    const commandPath = existingFilePath(command);
    const child = spawn(command, args, {
      cwd: commandPath ? path.dirname(commandPath) : ROOT,
      stdio: ["ignore", "pipe", "pipe"],
      windowsHide: true,
      detached: process.platform !== "win32",
      env: {
        ...process.env,
        DACX_E2E_PACKAGED_PROBE: "1",
        DACX_E2E_VERSION: String(version),
        DACX_E2E_RUN_ID: runId,
        ...(fixture ? { DACX_E2E_FIXTURE: fixture } : {}),
        ...(playbackReport ? { DACX_E2E_REPORT: playbackReport } : {}),
      },
    });
    const append = (chunk) => {
      output += chunk.toString();
      if (output.length > 20_000) output = output.slice(-20_000);
    };
    child.stdout?.on("data", append);
    child.stderr?.on("data", append);
    let cleanupStarted = false;
    const terminate = () => {
      if (cleanupStarted) return;
      cleanupStarted = true;
      cleanup = cleanupProcessTree(child);
      try {
        child.kill();
      } catch {
        // The process may already have exited after taskkill/group termination.
      }
    };
    const timer = setTimeout(() => {
      timedOut = true;
      terminate();
    }, smokeMs);
    const finish = (code, signal, error = null) => {
      if (finished) return;
      finished = true;
      clearTimeout(timer);
      const processStatus =
        timedOut && cleanup.status === "passed" ? "passed" : "failed";
      const playback = readPlaybackReceipt(playbackReport, {
        runId,
        version: String(version),
        fixtureSha256,
        startedAt: started,
      });
      const status = error
        ? "failed"
        : playback.status === "passed" && processStatus === "passed"
          ? "passed"
          : playback.status === "failed" || processStatus === "failed"
            ? "failed"
            : "incomplete";
      const result = {
        command: commandText(command, args),
        status,
        code,
        signal,
        timedOut,
        process: {
          status: processStatus,
          code,
          signal,
          timedOut,
        },
        cleanup,
        playback,
        error: error?.message ?? null,
        output,
        elapsedMs: Date.now() - started,
      };
      log.push(result);
      resolve(result);
    };
    child.once("error", (error) => finish(null, null, error));
    child.once("exit", (code, signal) => finish(code, signal));
  });
}

async function packageSmoke(args) {
  const log = [];
  const platform = args.platform;
  if (!["win", "mac", "linux"].includes(platform)) {
    throw new Error("--platform must be win, mac, or linux");
  }
  if (!args.artifact) throw new Error("--artifact is required");
  if (!args.report) throw new Error("--report is required");
  if (!args.version) throw new Error("--version is required for package proof");
  const artifact = path.resolve(args.artifact);
  const report = {
    schema: "dacx.e2e.package.v2",
    version: String(args.version),
    status: "failed",
    releaseProof: false,
    platform,
    host: {
      platform: process.platform,
      arch: process.arch,
      node: process.version,
      ci: process.env.CI === "true" || process.env.CI === "1",
    },
    artifact: {
      path: artifact,
      name: path.basename(artifact),
    },
    checks: {
      artifact: { exists: fs.existsSync(artifact) },
      format: { status: "skipped" },
      hash: { status: "skipped" },
      checksums: { status: "skipped" },
      proofMetadata: { status: "incomplete" },
      version: { status: "incomplete", expected: String(args.version) },
      requiredPaths: [],
      trust: [],
      launch: { status: "skipped" },
      executableBinding: { status: "incomplete" },
    },
    fixture: null,
    log: "",
  };

  if (!fs.existsSync(artifact)) {
    report.log = `Artifact does not exist: ${artifact}`;
    report.logPath = writeLog(args.report, report.log);
    writeReport(args.report, report);
    return 1;
  }

  const format = artifactFormat(platform, artifact);
  report.checks.format = format
    ? { status: "passed", kind: format }
    : {
        status: "failed",
        reason: `Unsupported ${platform} artifact format: ${path.basename(artifact)}`,
      };
  report.artifact.bytes = fs.statSync(artifact).size;
  report.artifact.sha256 = sha256File(artifact);
  report.checks.hash = checkExpectedHash(report.artifact.sha256, args);
  report.checks.checksums = checkChecksums(artifact, args);
  report.checks.proofMetadata = checkProofMetadata(artifact, report.artifact.sha256, args);
  report.checks.version = {
    status: report.checks.proofMetadata.status,
    expected: String(args.version),
    source: report.checks.proofMetadata.source ?? null,
    metadataVersion: report.checks.proofMetadata.expectedVersion ?? null,
  };

  let fixture = args.fixture ? path.resolve(args.fixture) : null;
  if (!fixture && !args.noLaunch) {
    const fixtureDir = path.join(path.dirname(path.resolve(args.report)), "fixtures");
    const fixtureReportPath = path.join(fixtureDir, "fixture-report.json");
    createFixtures(fixtureDir, fixtureReportPath);
    fixture = path.join(fixtureDir, FIXTURE_WAV);
  }
  if (fixture) {
    report.fixture = {
      path: fixture,
      exists: fs.existsSync(fixture),
      sha256: fs.existsSync(fixture) ? sha256File(fixture) : null,
    };
  }

  const preparation = preparePackageExecutable({
    platform,
    format,
    artifact,
    args,
    log,
  });
  report.checks.prepare = {
    status: preparation.status,
    ...(preparation.reason ? { reason: preparation.reason } : {}),
    ...(preparation.detach ? { detach: preparation.detach } : {}),
  };
  if (preparation.reason) log.push({ reason: preparation.reason });
  const executable = preparation.executable;
  if (executable) {
    const executablePath = existingFilePath(executable);
    const executableExists = Boolean(executablePath) || commandExists(executable);
    report.checks.executable = {
      path: executable,
      exists: executableExists,
      status: executableExists ? "passed" : "failed",
    };
    report.checks.requiredPaths = executablePath ? checkRequiredPaths(executablePath, args.requirePaths) : [];
  } else {
    report.checks.executable = {
      status: "skipped",
      reason: "No --executable supplied; package cannot prove launch/playback",
    };
  }
  report.checks.executableBinding = packageBindingForExecutable({
    artifact,
    executable,
    format,
    preparation,
    metadata: report.checks.proofMetadata,
    launchArgs: preparation.launchArgs,
  });

  report.checks.trust = runTrustChecks(platform, artifact, executable, args, log);

  if (args.noLaunch) {
    report.checks.launch = {
      status: "skipped",
      reason: "--no-launch supplied; this report cannot be release proof",
    };
  } else if (!executable || report.checks.executable.status !== "passed") {
    report.checks.launch = {
      status: "failed",
      reason: "Existing --executable path required for launch/playback proof",
    };
  } else if (fixture && !fs.existsSync(fixture)) {
    report.checks.launch = {
      status: "failed",
      reason: `Fixture does not exist: ${fixture}`,
    };
  } else {
    report.checks.launch = await spawnForSmoke(
      {
        command: executable,
        launchArgs: preparation.launchArgs ?? [],
        fixture,
        smokeMs: Number(args.smoke_ms ?? DEFAULT_SMOKE_MS),
        log,
        playbackReport: args.playback_report ? path.resolve(args.playback_report) : null,
        version: String(args.version),
        fixtureSha256: report.fixture?.sha256 ?? null,
      },
    );
  }

  const allChecks = [
    report.checks.artifact.exists,
    report.checks.format.status === "passed",
    report.checks.hash.status !== "failed",
    report.checks.checksums.status !== "failed",
    report.checks.hash.status === "passed" || report.checks.checksums.status === "passed",
    report.checks.version.status === "passed",
    report.checks.proofMetadata.status === "passed",
    report.checks.prepare.status !== "failed",
    report.checks.executable?.status !== "failed",
    report.checks.executableBinding.status === "passed",
    report.checks.requiredPaths.every((check) => check.status === "passed"),
    report.checks.launch.status === "passed",
    report.checks.trust.length > 0 && report.checks.trust.every((check) => check.status === "passed"),
  ];
  const anyFailed = [
    report.checks.hash,
    report.checks.format,
    report.checks.checksums,
    report.checks.proofMetadata,
    report.checks.version,
    report.checks.prepare,
    report.checks.executable,
    report.checks.executableBinding,
    ...report.checks.requiredPaths,
    report.checks.launch,
    ...report.checks.trust,
  ].some((check) => check?.status === "failed");
  report.releaseProof = allChecks.every(Boolean);
  report.status = report.releaseProof ? "passed" : anyFailed ? "failed" : "incomplete";
  report.log = log
    .map((entry) => `${entry.command ?? "check"}\n${entry.output ?? entry.reason ?? ""}`)
    .join("\n\n");
  try {
    report.logPath = writeLog(args.report, report.log);
    writeReport(args.report, report);
    return report.status === "passed" ? 0 : report.status === "incomplete" ? 2 : 1;
  } finally {
    if (preparation.cleanup) {
      fs.rmSync(preparation.cleanup, { recursive: true, force: true });
    }
  }
}

async function main(argv) {
  if (!argv.length || argv.includes("--help")) {
    usage();
    return 1;
  }
  const args = parseArgs(argv);
  if (args.command === "fixtures") {
    if (!args.output || !args.report) throw new Error("fixtures requires --output and --report");
    createFixtures(path.resolve(args.output), path.resolve(args.report));
    console.log(`Fixture report: ${path.resolve(args.report)}`);
    return 0;
  }
  if (args.command === "package") {
    const exitCode = await packageSmoke(args);
    console.log(`Package report: ${path.resolve(args.report)}`);
    return exitCode;
  }
  throw new Error(`Unknown command: ${args.command}`);
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main(process.argv.slice(2))
    .then((code) => process.exit(code))
    .catch((error) => {
      console.error(error.message);
      usage();
      process.exit(1);
    });
}

export {
  createFixtures,
  isSafeArchiveEntry,
  packageSmoke,
  prepareDmgExtraction,
  sha256File,
  writeDeterministicSrt,
  writeDeterministicWav,
};
