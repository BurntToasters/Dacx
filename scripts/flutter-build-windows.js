#!/usr/bin/env node
import { spawnSync } from 'node:child_process';
import { loadLocalDotEnv } from './xcode-env.js';

loadLocalDotEnv();

const env = { ...process.env };
const thumbprint = (
  env.DACX_WINDOWS_SIGNER_THUMBPRINT ||
  env.WINDOWS_SIGNING_CERT_THUMBPRINT ||
  ''
).trim();

const isReleaseBuild = !env.DACX_BUILD_DEV_NO_THUMBPRINT;
if (!thumbprint) {
  if (isReleaseBuild) {
    console.error(
      'ERROR: WINDOWS_SIGNING_CERT_THUMBPRINT (or DACX_WINDOWS_SIGNER_THUMBPRINT) not set in .env — release Windows builds must have it baked in for Authenticode pinning.\n' +
      '       Set the thumbprint in .env, or set DACX_BUILD_DEV_NO_THUMBPRINT=1 to override for local dev builds.',
    );
    process.exit(1);
  }
  console.warn(
    'WARN: WINDOWS_SIGNING_CERT_THUMBPRINT not set in .env — Authenticode verification will be skipped; Ed25519 update-manifest verification is still required.',
  );
}

const flutterArgs = ['flutter', 'build', 'windows', '--release'];
if (thumbprint) {
  flutterArgs.push(`--dart-define=DACX_WINDOWS_SIGNER_THUMBPRINT=${thumbprint}`);
}

const result = spawnSync('fvm', flutterArgs, {
  stdio: 'inherit',
  env,
  shell: true,
});

if (result.error) {
  console.error(`Failed to launch flutter: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
