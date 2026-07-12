#!/usr/bin/env node
import crossSpawn from 'cross-spawn';
import { loadLocalDotEnv } from './xcode-env.js';

loadLocalDotEnv();

const env = { ...process.env };
const thumbprint = (
  env.DACX_WINDOWS_SIGNER_THUMBPRINT ||
  env.WINDOWS_SIGNING_CERT_THUMBPRINT ||
  ''
).trim();

const requireSigner = process.env.DACX_REQUIRE_WINDOWS_SIGNER === '1';
if (!thumbprint) {
  const message =
    'WINDOWS_SIGNING_CERT_THUMBPRINT (or DACX_WINDOWS_SIGNER_THUMBPRINT) not set in .env; MSI will not be Authenticode-pinned; self-update still requires the Ed25519-signed manifest (Authenticode is an optional extra pin when the thumbprint is baked in).';
  if (requireSigner) {
    console.error(
      `ERROR: ${message}\nSet the thumbprint on release VMs, or unset DACX_REQUIRE_WINDOWS_SIGNER for local dev builds.`,
    );
    process.exit(1);
  }
  console.warn(`WARN: ${message}`);
}

const flutterArgs = ['flutter', 'build', 'windows', '--release'];
if (thumbprint) {
  flutterArgs.push(`--dart-define=DACX_WINDOWS_SIGNER_THUMBPRINT=${thumbprint}`);
}

const result = crossSpawn.sync('fvm', flutterArgs, {
  stdio: 'inherit',
  env,
});

if (result.error) {
  console.error(`Failed to launch flutter: ${result.error.message}`);
  process.exit(1);
}

process.exit(result.status ?? 1);
