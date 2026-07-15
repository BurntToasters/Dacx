#!/usr/bin/env node
import crossSpawn from "cross-spawn";
import path from "node:path";
import { fileURLToPath } from "node:url";
import { loadLocalDotEnv } from "./xcode-env.js";

loadLocalDotEnv();

const env = { ...process.env };
const skipWindowsCodeSigning = env.SKIP_WIN_CODESIGN?.trim() === "1";
const required = [
  "AZURE_CLIENT_ID",
  "AZURE_TENANT_ID",
  "AZURE_CLIENT_SECRET",
  "AZURE_ARTIFACT_SIGNING_ENDPOINT",
  "AZURE_ARTIFACT_SIGNING_ACCOUNT",
  "AZURE_ARTIFACT_SIGNING_PROFILE",
  "AZURE_ARTIFACT_SIGNING_PUBLISHER",
];
const missing = skipWindowsCodeSigning
  ? []
  : required.filter((name) => !env[name]?.trim());
if (process.platform !== "win32")
  throw new Error("Signed Windows builds must run on Windows.");
if (missing.length)
  throw new Error(
    `Missing Artifact Signing environment variables: ${missing.join(", ")}`,
  );
if (skipWindowsCodeSigning)
  console.warn(
    "[flutter-build-windows] SKIP_WIN_CODESIGN=1; producing unsigned Windows artifacts.",
  );
const publisher = skipWindowsCodeSigning
  ? ""
  : env.AZURE_ARTIFACT_SIGNING_PUBLISHER.trim();

const flutterArgs = [
  "flutter",
  "build",
  "windows",
  "--release",
  `--dart-define=DACX_WINDOWS_SIGNER_PUBLISHER=${publisher}`,
];

const result = crossSpawn.sync("fvm", flutterArgs, {
  stdio: "inherit",
  env,
});

if (result.error) {
  console.error(`Failed to launch flutter: ${result.error.message}`);
  process.exit(1);
}
if (result.status !== 0) process.exit(result.status ?? 1);

if (skipWindowsCodeSigning) process.exit(0);

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const executable = path.join(
  root,
  "build",
  "windows",
  "x64",
  "runner",
  "Release",
  "dacx.exe",
);
const sign = crossSpawn.sync(
  "powershell.exe",
  [
    "-NoProfile",
    "-NonInteractive",
    "-ExecutionPolicy",
    "Bypass",
    "-File",
    path.join(root, "scripts", "windows-artifact-sign.ps1"),
    "-FilePath",
    executable,
  ],
  { stdio: "inherit", env },
);
if (sign.error) throw sign.error;
process.exit(sign.status ?? 1);
