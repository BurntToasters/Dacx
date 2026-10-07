const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

const root = path.dirname(path.dirname(__filename));
const script = path.join(root, 'scripts', 'verify-draft-release.cjs');
const version = '1.0.0-beta.1';
const primary = [
  'Dacx-Windows-x64.msi',
  'Dacx-macOS.dmg',
  'Dacx-macOS.zip',
  'Dacx-Linux-x86_64.AppImage',
  'Dacx-Linux-x86_64.flatpak',
  'Dacx-Linux-x86_64.tar.gz',
  'Dacx-Linux-amd64.deb',
  'Dacx-Linux-x86_64.rpm',
];
const signable = primary;
const checksums = [
  'SHA256SUMS-Windows-x64.txt',
  'SHA256SUMS-macOS.txt',
  'SHA256SUMS-Linux-x86_64.txt',
];
const proofAssets = {
  windows: 'Dacx-Windows-x64.msi',
  macos: 'Dacx-macOS.dmg',
  linux: 'Dacx-Linux-x86_64.AppImage',
};
const HAS_GPG = spawnSync('gpg', ['--version'], { stdio: 'ignore' }).status === 0;

function run(args, env = {}) {
  return spawnSync(process.execPath, [script, ...args], {
    cwd: root,
    encoding: 'utf8',
    windowsHide: true,
    env: { ...process.env, ...env },
  });
}

function sha256(file) {
  return require('node:crypto').createHash('sha256').update(fs.readFileSync(file)).digest('hex');
}

function fixtureRoot() {
  return fs.mkdtempSync(path.join(os.tmpdir(), 'dacx-release-verifier-'));
}

function createFixture(base) {
  const release = path.join(base, 'release');
  const proof = path.join(base, 'proof');
  fs.mkdirSync(release, { recursive: true });
  fs.mkdirSync(proof, { recursive: true });
  for (const name of primary) fs.writeFileSync(path.join(release, name), `fixture:${name}`);
  const groups = {
    'SHA256SUMS-Windows-x64.txt': ['Dacx-Windows-x64.msi'],
    'SHA256SUMS-macOS.txt': ['Dacx-macOS.dmg', 'Dacx-macOS.zip'],
    'SHA256SUMS-Linux-x86_64.txt': primary.slice(3),
  };
  for (const [name, entries] of Object.entries(groups)) {
    fs.writeFileSync(
      path.join(release, name),
      entries.map((entry) => `${sha256(path.join(release, entry))}  ${entry}`).join('\n') + '\n',
    );
  }
  for (const name of signable) fs.writeFileSync(path.join(release, `${name}.asc`), 'test signature\n');
  for (const name of checksums) fs.writeFileSync(path.join(release, `${name}.asc`), 'test signature\n');
  const manifest = JSON.stringify({
      schema: 1,
      app: 'Dacx',
      platform: 'Windows-x64',
      version,
      assets: { 'Dacx-Windows-x64.msi': sha256(path.join(release, 'Dacx-Windows-x64.msi')) },
    }, null, 2) + '\n';
  fs.writeFileSync(path.join(release, 'Dacx-update-manifest-Windows-x64.json'), manifest);
  const keyPair = crypto.generateKeyPairSync('ed25519');
  const publicDer = keyPair.publicKey.export({ format: 'der', type: 'spki' });
  fs.writeFileSync(
    path.join(release, 'Dacx-update-manifest-Windows-x64.json.sig'),
    `${crypto.sign(null, Buffer.from(manifest), keyPair.privateKey).toString('base64')}\n`,
  );
  for (const platform of ['windows', 'macos', 'linux']) {
    const proofAsset = proofAssets[platform];
    fs.writeFileSync(
      path.join(proof, `${platform}.json`),
      JSON.stringify({
        schema: 'dacx.e2e.package.v2',
        status: 'passed',
        releaseProof: true,
        version,
        platform,
        artifact: {
          name: proofAsset,
          sha256: sha256(path.join(release, proofAsset)),
        },
        checks: {
          artifact: { exists: true },
          hash: { status: 'passed' },
          checksums: { status: 'passed' },
          proofMetadata: { status: 'passed' },
          version: { status: 'passed', expected: version },
          executableBinding: { status: 'passed' },
          requiredPaths: [],
          launch: {
            status: 'passed',
            process: { status: 'passed' },
            playback: { status: 'passed' },
          },
          trust: [{ status: 'passed' }],
        },
      }) + '\n',
    );
  }
  const remoteAssetsPath = path.join(base, 'remote-assets.json');
  fs.writeFileSync(
    remoteAssetsPath,
    JSON.stringify(
      [...fs.readdirSync(release)].map((name) => ({
        name,
        size: fs.statSync(path.join(release, name)).size,
        digest: `sha256:${sha256(path.join(release, name))}`,
      })),
      null,
      2,
    ) + '\n',
  );
  return {
    release,
    proof,
    remoteAssetsPath,
    manifestPublicKey: publicDer.subarray(publicDer.length - 32).toString('base64'),
  };
}

test('draft verifier audits complete local release and emits repeatable report', () => {
  const base = fixtureRoot();
  const { release, proof, remoteAssetsPath, manifestPublicKey } = createFixture(base);
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--remote',
    '--remote-assets-file', remoteAssetsPath,
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.status, 'passed');
  assert.equal(parsed.releaseProof, true);
  assert.deepEqual(parsed.primaryAssets.missing, []);
  assert.deepEqual(parsed.platformProof.missing, []);
  assert.match(parsed.log, /Dacx-Windows-x64\.msi/);
});

test('draft verifier accepts the current package proof v2 schema', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  assert.equal(JSON.parse(fs.readFileSync(report, 'utf8')).releaseProof, true);
});

test('draft verifier rejects legacy package proof schemas', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  const proofPath = path.join(proof, 'linux.json');
  const proofData = JSON.parse(fs.readFileSync(proofPath, 'utf8'));
  proofData.schema = 'dacx.e2e.package.v1';
  fs.writeFileSync(proofPath, `${JSON.stringify(proofData)}\n`);
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  assert.match(
    JSON.parse(fs.readFileSync(report, 'utf8')).platformProof.failures.join('\n'),
    /schema must be dacx\.e2e\.package\.v2/,
  );
});

test('draft verifier rejects a platform proof bound to different artifact bytes', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  const proofPath = path.join(proof, 'windows.json');
  const proofData = JSON.parse(fs.readFileSync(proofPath, 'utf8'));
  proofData.artifact.sha256 = '0'.repeat(64);
  fs.writeFileSync(proofPath, `${JSON.stringify(proofData)}\n`);
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  assert.match(
    JSON.parse(fs.readFileSync(report, 'utf8')).platformProof.failures.join('\n'),
    /artifact sha256 must match/,
  );
});

test('draft verifier rejects an extra local staging file', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  fs.writeFileSync(path.join(release, 'README.txt'), 'not a release asset\n');
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.deepEqual(parsed.primaryAssets.unrecognizedArtifacts, ['README.txt']);
});

test('draft verifier requires the proof version at the top level', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  const proofPath = path.join(proof, 'linux.json');
  const reportData = JSON.parse(fs.readFileSync(proofPath, 'utf8'));
  delete reportData.version;
  fs.writeFileSync(proofPath, `${JSON.stringify(reportData)}\n`);
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  assert.match(
    JSON.parse(fs.readFileSync(report, 'utf8')).platformProof.failures.join('\n'),
    /version must be/,
  );
});

test('draft verifier fails closed and still writes report when asset is missing', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  fs.rmSync(path.join(release, 'Dacx-macOS.dmg'));
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.releaseProof, false);
  assert.ok(parsed.primaryAssets.missing.includes('Dacx-macOS.dmg'));
});

test('draft verifier rejects a tampered Windows manifest signature', () => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  fs.writeFileSync(
    path.join(release, 'Dacx-update-manifest-Windows-x64.json.sig'),
    `${Buffer.alloc(64, 0).toString('base64')}\n`,
  );
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.manifest.status, 'failed');
  assert.match(parsed.manifest.reason, /signature/i);
});

test('draft verifier rejects remote digest or size drift', () => {
  const base = fixtureRoot();
  const { release, proof, remoteAssetsPath, manifestPublicKey } = createFixture(base);
  const remote = JSON.parse(fs.readFileSync(remoteAssetsPath, 'utf8'));
  const target = remote.find((asset) => asset.name === 'Dacx-Windows-x64.msi');
  target.digest = `sha256:${'0'.repeat(64)}`;
  target.size += 1;
  fs.writeFileSync(remoteAssetsPath, JSON.stringify(remote, null, 2) + '\n');
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--remote',
    '--remote-assets-file', remoteAssetsPath,
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.notEqual(result.status, 0);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.remote.status, 'failed');
  assert.ok(parsed.remote.digestMismatches.includes('Dacx-Windows-x64.msi'));
  assert.ok(parsed.remote.sizeMismatches.includes('Dacx-Windows-x64.msi'));
});

test('draft verifier hashes downloaded remote bytes when digest is absent', () => {
  const base = fixtureRoot();
  const { release, proof, remoteAssetsPath, manifestPublicKey } = createFixture(base);
  const remote = JSON.parse(fs.readFileSync(remoteAssetsPath, 'utf8'));
  for (const asset of remote) {
    delete asset.digest;
    asset.browser_download_url = `data:application/octet-stream;base64,${fs
      .readFileSync(path.join(release, asset.name))
      .toString('base64')}`;
  }
  fs.writeFileSync(remoteAssetsPath, `${JSON.stringify(remote)}\n`);
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--allow-gpg-skip',
    '--remote',
    '--remote-assets-file', remoteAssetsPath,
    '--manifest-public-key', manifestPublicKey,
  ]);
  assert.equal(result.status, 0, result.stderr || result.stdout);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.remote.status, 'passed');
  assert.deepEqual(parsed.remote.digestMismatches, []);
  assert.deepEqual(parsed.remote.sizeMismatches, []);
});

// gpg-agent puts its sockets inside GNUPGHOME. macOS temp paths are long
// enough to push them past the 104-byte Unix socket limit, and the agent then
// fails to start ("IPC connect call failed"). Keep the home short on POSIX.
function shortGpgHome() {
  const root = process.platform === 'win32' ? os.tmpdir() : '/tmp';
  const home = fs.mkdtempSync(path.join(root, 'dxg-'));
  fs.chmodSync(home, 0o700);
  return home;
}

test('draft verifier rejects a wrong GPG signer fingerprint', { skip: !HAS_GPG }, (t) => {
  const base = fixtureRoot();
  const { release, proof, manifestPublicKey } = createFixture(base);
  const gpgHome = shortGpgHome();
  const env = { GNUPGHOME: gpgHome };
  t.after(() => {
    spawnSync('gpgconf', ['--kill', 'gpg-agent'], {
      env: { ...process.env, ...env },
      stdio: 'ignore',
    });
    fs.rmSync(gpgHome, { recursive: true, force: true });
  });
  const generated = spawnSync('gpg', [
    '--batch', '--pinentry-mode', 'loopback', '--passphrase', '',
    '--quick-gen-key', 'Dacx Test <dacx@example.invalid>', 'ed25519', 'sign', '0',
  ], { env: { ...process.env, ...env }, encoding: 'utf8' });
  assert.equal(generated.status, 0, generated.stderr || generated.stdout);
  const listed = spawnSync('gpg', ['--batch', '--with-colons', '--list-keys'], {
    env: { ...process.env, ...env }, encoding: 'utf8',
  });
  const fingerprint = listed.stdout.match(/^fpr:::::::::([A-F0-9]+):$/mu)?.[1];
  assert.ok(fingerprint);
  for (const name of [...primary, ...checksums]) {
    const signed = spawnSync('gpg', [
      '--batch', '--yes', '--armor', '--detach-sign', '--local-user', fingerprint,
      '--output', path.join(release, `${name}.asc`), path.join(release, name),
    ], { env: { ...process.env, ...env }, encoding: 'utf8' });
    assert.equal(signed.status, 0, signed.stderr || signed.stdout);
  }
  const report = path.join(base, 'report.json');
  const result = run([
    '--local', release,
    '--proof-dir', proof,
    '--report', report,
    '--verify-signatures',
    '--gpg-fingerprint', '0'.repeat(40),
    '--no-remote',
    '--manifest-public-key', manifestPublicKey,
  ], env);
  assert.notEqual(result.status, 0);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.signatures.status, 'failed');
  assert.ok(parsed.signatures.fingerprintMismatches.length > 0);
});

test('draft verifier emits report and redacted raw log on argument failure', () => {
  const base = fixtureRoot();
  const report = path.join(base, 'report.json');
  const result = run(['--report', report, '--unknown-option']);
  assert.notEqual(result.status, 0);
  assert.equal(fs.existsSync(report), true);
  assert.equal(fs.existsSync(`${report}.log`), true);
  const parsed = JSON.parse(fs.readFileSync(report, 'utf8'));
  assert.equal(parsed.status, 'failed');
  assert.equal(parsed.releaseProof, false);
  assert.match(fs.readFileSync(`${report}.log`, 'utf8'), /missing value|unknown option/i);
});
