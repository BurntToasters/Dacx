import assert from "node:assert/strict";
import crypto from "node:crypto";
import { spawnSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { fileURLToPath } from "node:url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const script = path.join(root, "scripts", "platform-release-smoke.js");

function tempRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "dacx-platform-smoke-"));
}

function run(args) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: root,
    encoding: "utf8",
    windowsHide: true,
  });
}

function sha256(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function packageEvidence(rootDir, artifact, version = "1.0.0") {
  const digest = sha256(artifact);
  const checksums = path.join(rootDir, "SHA256SUMS");
  const metadata = path.join(rootDir, "proof-metadata.json");
  fs.writeFileSync(checksums, `${digest}  ${path.basename(artifact)}\n`, "utf8");
  fs.writeFileSync(
    metadata,
    `${JSON.stringify({
      version,
      artifacts: { [path.basename(artifact)]: { sha256: digest } },
    })}\n`,
    "utf8",
  );
  return { digest, checksums, metadata, version };
}

test("fixture command creates stable WAV/SRT and report hashes", () => {
  const rootDir = tempRoot();
  const fixtureDir = path.join(rootDir, "fixtures");
  const reportPath = path.join(rootDir, "fixture-report.json");

  const first = run([
    "fixtures",
    "--output",
    fixtureDir,
    "--report",
    reportPath,
  ]);
  assert.equal(first.status, 0, first.stderr || first.stdout);

  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.schema, "dacx.e2e.fixture.v1");
  assert.equal(report.status, "passed");
  assert.deepEqual(
    report.files.map((entry) => entry.name),
    ["release-smoke.wav", "release-smoke.srt"],
  );
  for (const entry of report.files) {
    assert.match(entry.sha256, /^[a-f0-9]{64}$/);
    assert.ok(fs.statSync(path.join(fixtureDir, entry.name)).size > 0);
  }

  const secondDir = path.join(rootDir, "fixtures-second");
  const secondReportPath = path.join(rootDir, "fixture-report-second.json");
  const second = run([
    "fixtures",
    "--output",
    secondDir,
    "--report",
    secondReportPath,
  ]);
  assert.equal(second.status, 0, second.stderr || second.stdout);
  const secondReport = JSON.parse(fs.readFileSync(secondReportPath, "utf8"));
  assert.deepEqual(
    secondReport.files.map((entry) => entry.sha256),
    report.files.map((entry) => entry.sha256),
  );
});

test("package command fails closed when candidate artifact is missing", () => {
  const rootDir = tempRoot();
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    process.platform === "win32" ? "win" : process.platform === "darwin" ? "mac" : "linux",
    "--artifact",
    path.join(rootDir, "missing-artifact"),
    "--report",
    reportPath,
    "--no-launch",
    "--version",
    "1.0.0",
  ]);
  assert.notEqual(result.status, 0);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.status, "failed");
  assert.equal(report.checks.artifact.exists, false);
  assert.match(report.log, /does not exist/i);
  assert.ok(fs.existsSync(`${reportPath}.log`));
});

test("package command marks skipped launch incomplete, never release proof", () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "candidate.AppImage");
  fs.writeFileSync(artifact, "deterministic candidate");
  const evidence = packageEvidence(rootDir, artifact);
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--report",
    reportPath,
    "--no-launch",
    "--version",
    evidence.version,
    "--proof-metadata",
    evidence.metadata,
    "--expected-sha256",
    evidence.digest,
    "--checksums",
    evidence.checksums,
  ]);
  assert.equal(result.status, 2, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.status, "incomplete");
  assert.equal(report.checks.launch.status, "skipped");
  assert.equal(report.releaseProof, false);
  assert.ok(fs.existsSync(`${reportPath}.log`));
});

test("package command rejects unknown artifact format before launch", () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "candidate.bin");
  fs.writeFileSync(artifact, "not a release package");
  const evidence = packageEvidence(rootDir, artifact);
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--report",
    reportPath,
    "--no-launch",
    "--version",
    evidence.version,
  ]);
  assert.equal(result.status, 1);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.status, "failed");
  assert.equal(report.checks.format.status, "failed");
});

test("package proof accepts canonical unversioned names and exposes bound version/schema", () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "Dacx-Linux-x86_64.AppImage");
  fs.writeFileSync(artifact, "deterministic candidate");
  const evidence = packageEvidence(rootDir, artifact, "1.0.0");
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--report",
    reportPath,
    "--no-launch",
    "--version",
    evidence.version,
    "--proof-metadata",
    evidence.metadata,
    "--expected-sha256",
    evidence.digest,
    "--checksums",
    evidence.checksums,
  ]);
  assert.equal(result.status, 2, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.schema, "dacx.e2e.package.v2");
  assert.equal(report.version, evidence.version);
  assert.equal(report.checks.version.status, "passed");
  assert.equal(report.checks.proofMetadata.status, "passed");
  assert.equal(report.artifact.name, "Dacx-Linux-x86_64.AppImage");
  assert.equal(report.releaseProof, false);
});

test("package proof rejects an executable unrelated to the inspected artifact", () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "Dacx-Linux-x86_64.AppImage");
  const executable = path.join(rootDir, "unrelated-launcher");
  fs.writeFileSync(artifact, "deterministic candidate");
  fs.writeFileSync(executable, "unrelated executable");
  const evidence = packageEvidence(rootDir, artifact);
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--executable",
    executable,
    "--report",
    reportPath,
    "--no-launch",
    "--version",
    evidence.version,
    "--proof-metadata",
    evidence.metadata,
    "--expected-sha256",
    evidence.digest,
    "--checksums",
    evidence.checksums,
  ]);
  assert.equal(result.status, 1);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.checks.executableBinding.status, "failed");
  assert.equal(report.releaseProof, false);
});

test("package proof does not turn timeout/process survival into playback proof", () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "Dacx-Linux-x86_64.AppImage");
  fs.writeFileSync(artifact, "deterministic candidate");
  const evidence = packageEvidence(rootDir, artifact);
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--report",
    reportPath,
    "--launcher",
    process.execPath,
    "--launch-arg",
    "-e",
    "--launch-arg",
    "setInterval(() => {}, 10000)",
    "--launch-arg",
    "--",
    "--launch-arg",
    "--flatpak-flag",
    "--launch-arg",
    "run.rosie.dacx",
    "--smoke-ms",
    "250",
    "--version",
    evidence.version,
    "--proof-metadata",
    evidence.metadata,
    "--expected-sha256",
    evidence.digest,
    "--checksums",
    evidence.checksums,
  ]);
  assert.equal(result.status, 2, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.checks.launch.status, "incomplete");
  assert.equal(report.checks.launch.playback.status, "incomplete");
  assert.equal(report.checks.launch.process.timedOut, true);
  assert.match(report.checks.launch.command, /--flatpak-flag/);
  assert.match(report.checks.launch.command, /run\.rosie\.dacx/);
  assert.equal(report.releaseProof, false);
});

test("package proof rejects an app that exits immediately after writing a passing receipt", () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "Dacx-Linux-x86_64.AppImage");
  const fixture = path.join(rootDir, "release-smoke.wav");
  const playbackReport = path.join(rootDir, "desktop-playback.json");
  fs.writeFileSync(artifact, "deterministic candidate");
  fs.writeFileSync(fixture, "deterministic playback fixture");
  const evidence = packageEvidence(rootDir, artifact);
  const reportPath = path.join(rootDir, "package-report.json");
  const receiptWriter = [
    'const fs = require("node:fs")',
    'const crypto = require("node:crypto")',
    'const fixture = process.env.DACX_E2E_FIXTURE',
    'const sha256 = crypto.createHash("sha256").update(fs.readFileSync(fixture)).digest("hex")',
    'fs.writeFileSync(process.env.DACX_E2E_REPORT, JSON.stringify({schema:"dacx.e2e.desktop-playback.v1",version:process.env.DACX_E2E_VERSION,runId:process.env.DACX_E2E_RUN_ID,status:"passed",releaseProof:true,fixture:{sha256},checks:{durationMs:6000,playing:true,error:null}}))',
  ].join(";");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--fixture",
    fixture,
    "--playback-report",
    playbackReport,
    "--report",
    reportPath,
    "--launcher",
    process.execPath,
    "--launch-arg",
    "-e",
    "--launch-arg",
    receiptWriter,
    "--smoke-ms",
    "1000",
    "--version",
    evidence.version,
    "--proof-metadata",
    evidence.metadata,
    "--expected-sha256",
    evidence.digest,
    "--checksums",
    evidence.checksums,
  ]);
  assert.notEqual(result.status, 0, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.equal(report.checks.launch.playback.status, "passed");
  assert.equal(report.checks.launch.process.status, "failed");
  assert.notEqual(report.checks.launch.status, "passed");
  assert.equal(report.releaseProof, false);
});

test("package proof cleans a child process tree after a timeout", { skip: process.platform !== "win32" }, () => {
  const rootDir = tempRoot();
  const artifact = path.join(rootDir, "Dacx-Linux-x86_64.AppImage");
  const launcher = path.join(rootDir, "tree-launcher.cjs");
  const childPidFile = path.join(rootDir, "child.pid");
  fs.writeFileSync(artifact, "deterministic candidate");
  fs.writeFileSync(
    launcher,
    `const fs = require("node:fs");\nconst { spawn } = require("node:child_process");\nconst child = spawn(process.execPath, ["-e", "setInterval(() => {}, 10000)"], { stdio: "ignore" });\nfs.writeFileSync(${JSON.stringify(childPidFile)}, String(child.pid));\nsetInterval(() => {}, 10000);\n`,
    "utf8",
  );
  const evidence = packageEvidence(rootDir, artifact);
  const reportPath = path.join(rootDir, "package-report.json");
  const result = run([
    "package",
    "--platform",
    "linux",
    "--artifact",
    artifact,
    "--report",
    reportPath,
    "--launcher",
    process.execPath,
    "--launch-arg",
    launcher,
    "--smoke-ms",
    "250",
    "--version",
    evidence.version,
    "--proof-metadata",
    evidence.metadata,
    "--expected-sha256",
    evidence.digest,
    "--checksums",
    evidence.checksums,
  ]);
  assert.equal(result.status, 2, result.stderr || result.stdout);
  const report = JSON.parse(fs.readFileSync(reportPath, "utf8"));
  assert.notEqual(report.checks.launch.cleanup.status, "failed");
  const childPid = Number(fs.readFileSync(childPidFile, "utf8"));
  assert.throws(() => process.kill(childPid, 0));
});

test("tar extraction rejects traversal entries before invoking tar", async () => {
  const { isSafeArchiveEntry } = await import("./platform-release-smoke.js");
  assert.equal(isSafeArchiveEntry("bundle/dacx"), true);
  assert.equal(isSafeArchiveEntry("../outside"), false);
  assert.equal(isSafeArchiveEntry("/absolute/outside"), false);
  assert.equal(isSafeArchiveEntry("bundle/../../outside"), false);
});

test("DMG extraction detaches in finally when bundle copy fails", async () => {
  const { prepareDmgExtraction } = await import("./platform-release-smoke.js");
  const calls = [];
  const staging = tempRoot();
  const result = prepareDmgExtraction({
    artifact: path.join(staging, "Dacx.dmg"),
    staging,
    run: (command, args) => {
      calls.push({ command, args });
      if (command === "hdiutil" && args[0] === "attach") {
        fs.mkdirSync(path.join(staging, "mount", "Dacx.app"), { recursive: true });
        return { code: 0, command: "hdiutil attach", output: "" };
      }
      if (command === "ditto") return { code: 1, command: "ditto", output: "copy failed" };
      return { code: 0, command: "hdiutil detach", output: "" };
    },
    log: [],
  });
  assert.equal(result.status, "failed");
  assert.equal(calls.filter(({ command, args }) => command === "hdiutil" && args[0] === "detach").length, 1);
});
