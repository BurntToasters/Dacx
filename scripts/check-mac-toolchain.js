#!/usr/bin/env node
import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
import {
  hasXcodebuildBinary,
  loadLocalDotEnv,
  resolveDeveloperDir,
} from './xcode-env.js';

function canRun(cmd, env = process.env) {
  try {
    execSync(cmd, { stdio: 'ignore', shell: true, env });
    return true;
  } catch {
    return false;
  }
}

function capture(cmd, env = process.env) {
  try {
    return execSync(cmd, {
      encoding: 'utf8',
      stdio: ['ignore', 'pipe', 'ignore'],
      shell: true,
      env,
    }).trim();
  } catch {
    return '';
  }
}

if (process.platform !== 'darwin') {
  console.log('Skipping macOS toolchain check on non-macOS host.');
  process.exit(0);
}

loadLocalDotEnv();

const defaultXcodeDeveloperDir = '/Applications/Xcode.app/Contents/Developer';
const selectedDeveloperDir = capture('xcode-select -p');
const hasDefaultXcode = existsSync(`${defaultXcodeDeveloperDir}/usr/bin/xcodebuild`);
const {
  effectiveDeveloperDir,
  source,
  xcodeDirRaw,
  xcodeDirNormalized,
} = resolveDeveloperDir();

const commandEnv = effectiveDeveloperDir
  ? { ...process.env, DEVELOPER_DIR: effectiveDeveloperDir }
  : process.env;

const hasXcrunXcodebuild = canRun('xcrun --find xcodebuild', commandEnv);
const hasXcodebuildVersion = canRun('xcodebuild -version', commandEnv);

if (hasXcrunXcodebuild && hasXcodebuildVersion) {
  if (effectiveDeveloperDir) {
    const sourceLabel = source === 'default'
      ? 'default /Applications/Xcode.app'
      : source;
    console.log(
      `✔ macOS toolchain check passed (xcodebuild available via ${sourceLabel}: ${effectiveDeveloperDir}).`
    );
  } else {
    console.log('✔ macOS toolchain check passed (xcodebuild available via xcode-select).');
  }
  process.exit(0);
}

const envDeveloperDir = process.env.DEVELOPER_DIR
  ? `Detected DEVELOPER_DIR: ${process.env.DEVELOPER_DIR}\n`
  : '';
const xcodeDirDetails = xcodeDirRaw
  ? `Detected XCODE_DIR: ${xcodeDirRaw}\nResolved XCODE_DIR developer dir: ${xcodeDirNormalized}\n`
  : '';
const effectiveDetails = effectiveDeveloperDir
  ? `Attempted DEVELOPER_DIR for this check: ${effectiveDeveloperDir}\n` +
    (hasXcodebuildBinary(effectiveDeveloperDir)
      ? ''
      : 'xcodebuild was not found under that directory.\n')
  : '';

console.error(
  '\n✖ Full Xcode is required for macOS builds, but xcodebuild is unavailable.\n' +
  (selectedDeveloperDir
    ? `Current xcode-select path: ${selectedDeveloperDir}\n`
    : 'Current xcode-select path: unavailable\n') +
  (hasDefaultXcode
    ? `Default Xcode developer dir exists at ${defaultXcodeDeveloperDir}, but it is not active or initialized.\n`
    : `Default Xcode developer dir not found at ${defaultXcodeDeveloperDir}.\n`) +
  xcodeDirDetails +
  effectiveDetails +
  envDeveloperDir +
  '\nFix:\n' +
  '  1) If Xcode is on another drive, set XCODE_DIR in .env (Xcode.app path or Contents/Developer path)\n' +
  '     Example: XCODE_DIR=/Volumes/WD/Applications/Xcode.app\n' +
  '  2) Or install Xcode to /Applications/Xcode.app\n' +
  '  3) Optional system-wide switch:\n' +
  '     sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer\n' +
  '  4) Initialize Xcode once:\n' +
  '     sudo xcodebuild -runFirstLaunch\n' +
  '     sudo xcodebuild -license accept\n' +
  '  5) unset DEVELOPER_DIR if it points to an old location\n\n' +
  'Verify:\n' +
  '  npm run check:mac:toolchain\n' +
  '  xcrun --find xcodebuild\n' +
  '  xcodebuild -version\n' +
  '  fvm flutter doctor -v\n'
);

process.exit(1);
