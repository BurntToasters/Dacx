#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import {
  hasXcodebuildBinary,
  loadLocalDotEnv,
  resolveDeveloperDir,
} from './xcode-env.js';

if (process.platform !== 'darwin') {
  console.error('flutter-build-macos.js must be run on macOS.');
  process.exit(1);
}

loadLocalDotEnv();

const {
  effectiveDeveloperDir,
  source,
  xcodeDirRaw,
  xcodeDirNormalized,
} = resolveDeveloperDir();

const env = { ...process.env };

if (effectiveDeveloperDir) {
  if (!hasXcodebuildBinary(effectiveDeveloperDir)) {
    console.error(
      '\n✖ Invalid Xcode developer directory for macOS build.\n' +
      `Resolved directory: ${effectiveDeveloperDir}\n` +
      (xcodeDirRaw
        ? `XCODE_DIR=${xcodeDirRaw}\nNormalized to: ${xcodeDirNormalized}\n`
        : '') +
      'Expected to find: <developer-dir>/usr/bin/xcodebuild\n'
    );
    process.exit(1);
  }

  env.DEVELOPER_DIR = effectiveDeveloperDir;
  const sourceLabel = source === 'default'
    ? 'default /Applications/Xcode.app'
    : source;
  console.log(`Using DEVELOPER_DIR=${effectiveDeveloperDir} (source: ${sourceLabel}).`);
} else {
  console.log('Using active xcode-select developer directory.');
}

const result = spawnSync('fvm', ['flutter', 'build', 'macos', '--release'], {
  stdio: 'inherit',
  env,
  shell: true,
});

if (result.error) {
  console.error(`Failed to launch flutter: ${result.error.message}`);
  process.exit(1);
}

const exitCode = result.status ?? 1;
if (exitCode === 0) {
  const iconResult = spawnSync('bash', ['scripts/embed-mac-document-icon.sh'], {
    stdio: 'inherit',
    env,
    shell: false,
  });
  if (iconResult.error) {
    console.warn(`WARN: failed to run icon embed step: ${iconResult.error.message}`);
  } else if ((iconResult.status ?? 0) !== 0) {
    console.warn(`WARN: icon embed step exited with code ${iconResult.status}.`);
  }
}

process.exit(exitCode);
