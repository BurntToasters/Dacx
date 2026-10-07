#!/usr/bin/env node

const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const { githubApi } = require('./github-cli.cjs');

const ROOT = path.resolve(__dirname, '..');
const PINNED_TRUST_CONFIG = path.join(ROOT, 'lib', 'services', 'update_trust_config.dart');
const ED25519_SPKI_PREFIX = Buffer.from('302a300506032b6570032100', 'hex');
const PRIMARY_ASSETS = [
  'Dacx-Windows-x64.msi',
  'Dacx-macOS.dmg',
  'Dacx-macOS.zip',
  'Dacx-Linux-x86_64.AppImage',
  'Dacx-Linux-x86_64.flatpak',
  'Dacx-Linux-x86_64.tar.gz',
  'Dacx-Linux-amd64.deb',
  'Dacx-Linux-x86_64.rpm',
];
const CHECKSUM_MEMBERSHIP = {
  'SHA256SUMS-Windows-x64.txt': ['Dacx-Windows-x64.msi'],
  'SHA256SUMS-macOS.txt': ['Dacx-macOS.dmg', 'Dacx-macOS.zip'],
  'SHA256SUMS-Linux-x86_64.txt': [
    'Dacx-Linux-x86_64.AppImage',
    'Dacx-Linux-x86_64.flatpak',
    'Dacx-Linux-x86_64.tar.gz',
    'Dacx-Linux-amd64.deb',
    'Dacx-Linux-x86_64.rpm',
  ],
};
const CHECKSUM_ASSETS = Object.keys(CHECKSUM_MEMBERSHIP);
const PLATFORM_PROOFS = ['windows', 'macos', 'linux'];
const PACKAGE_PROOF_SCHEMA = 'dacx.e2e.package.v2';
const PLATFORM_PROOF_ASSETS = {
  windows: 'Dacx-Windows-x64.msi',
  macos: 'Dacx-macOS.dmg',
  linux: 'Dacx-Linux-x86_64.AppImage',
};

function parseArgs(argv) {
  const args = {
    local: path.join(ROOT, 'release'),
    proofDir: null,
    report: null,
    remote: false,
    remoteAssetsFile: null,
    noRemote: false,
    verifySignatures: false,
    allowGpgSkip: false,
    manifestPublicKey: null,
    gpgFingerprint: null,
  };
  for (let index = 0; index < argv.length; index += 1) {
    const item = argv[index];
    if (item === '--remote') {
      args.remote = true;
      continue;
    }
    if (item === '--no-remote') {
      args.noRemote = true;
      continue;
    }
    if (item === '--verify-signatures') {
      args.verifySignatures = true;
      continue;
    }
    if (item === '--allow-gpg-skip') {
      args.allowGpgSkip = true;
      continue;
    }
    if (!item.startsWith('--')) throw new Error(`Unexpected argument: ${item}`);
    const key = item.slice(2);
    const value = argv[++index];
    if (!value || value.startsWith('--')) throw new Error(`Missing value for ${item}`);
    if (key === 'local') args.local = path.resolve(value);
    else if (key === 'proof-dir') args.proofDir = path.resolve(value);
    else if (key === 'report') args.report = path.resolve(value);
    else if (key === 'remote-assets-file') args.remoteAssetsFile = path.resolve(value);
    else if (key === 'manifest-public-key') args.manifestPublicKey = value;
    else if (key === 'gpg-fingerprint') args.gpgFingerprint = value;
    else throw new Error(`Unknown option: ${item}`);
  }
  return args;
}

function reportPathHint(argv) {
  const index = argv.indexOf('--report');
  if (index >= 0 && argv[index + 1] && !argv[index + 1].startsWith('--')) {
    return path.resolve(argv[index + 1]);
  }
  return path.join(ROOT, 'test-results', 'release-proof', 'unknown', 'report.json');
}

function versionFromPackage() {
  const pkg = JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/u.test(pkg.version || '')) {
    throw new Error(`Invalid package.json version: "${pkg.version}"`);
  }
  return pkg.version;
}

function sha256Bytes(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function sha256(filePath) {
  return sha256Bytes(fs.readFileSync(filePath));
}

function writeJson(filePath, value) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const temporary = `${filePath}.tmp-${process.pid}`;
  try {
    fs.writeFileSync(temporary, `${JSON.stringify(value, null, 2)}\n`, 'utf8');
    fs.renameSync(temporary, filePath);
  } finally {
    fs.rmSync(temporary, { force: true });
  }
}

function redact(value) {
  return String(value ?? '')
    .replace(/(GPG_PASSPHRASE|DACX_UPDATE_PRIVATE_KEY_PKCS8_BASE64|GITHUB_TOKEN|GH_TOKEN)\s*=\s*[^\s]+/giu, '$1=[REDACTED]')
    .replace(/(authorization\s*:\s*bearer\s+)[^\s]+/giu, '$1[REDACTED]')
    .replace(/\bgh[pousr]_[A-Za-z0-9_]+\b/gu, '[REDACTED_TOKEN]');
}

function allEntries(directory) {
  if (!fs.existsSync(directory)) return [];
  return fs.readdirSync(directory, { withFileTypes: true })
    .map((entry) => entry.name)
    .sort();
}

function verifyAssetSet(localDir) {
  const files = allEntries(localDir);
  const requiredSidecars = [
    ...PRIMARY_ASSETS.map((name) => `${name}.asc`),
    ...CHECKSUM_ASSETS.map((name) => `${name}.asc`),
    'Dacx-update-manifest-Windows-x64.json',
    'Dacx-update-manifest-Windows-x64.json.sig',
  ];
  const required = [...PRIMARY_ASSETS, ...CHECKSUM_ASSETS, ...requiredSidecars];
  const missing = required.filter((name) => !files.includes(name));
  const allowed = new Set(required);
  const unrecognizedArtifacts = files.filter((name) => !allowed.has(name));
  return {
    files,
    required,
    missing,
    unrecognizedArtifacts,
    passed: missing.length === 0 && unrecognizedArtifacts.length === 0,
  };
}

function verifyChecksums(localDir) {
  const entries = [];
  const failures = [];
  const platformMismatches = [];
  const seen = new Set();
  for (const checksumName of CHECKSUM_ASSETS) {
    const filePath = path.join(localDir, checksumName);
    if (!fs.existsSync(filePath)) continue;
    const expectedMembers = new Set(CHECKSUM_MEMBERSHIP[checksumName]);
    for (const line of fs.readFileSync(filePath, 'utf8').split(/\r?\n/u)) {
      if (!line.trim()) continue;
      const match = line.match(/^([a-f0-9]{64})\s+[* ]?(.+)$/iu);
      if (!match) {
        failures.push(`${checksumName}: malformed checksum line`);
        continue;
      }
      const [, expected, rawName] = match;
      const target = path.basename(rawName.trim());
      const targetPath = path.join(localDir, target);
      const entry = {
        checksum: checksumName,
        asset: target,
        expected: expected.toLowerCase(),
        actual: fs.existsSync(targetPath) ? sha256(targetPath) : null,
      };
      entries.push(entry);
      if (rawName.trim() !== target || !path.isAbsolute(targetPath) || target.includes('..')) {
        failures.push(`${checksumName}: unsafe checksum asset path ${rawName.trim()}`);
      }
      if (!expectedMembers.has(target)) {
        platformMismatches.push(`${checksumName}:${target}`);
      }
      if (seen.has(target)) failures.push(`${target}: duplicate checksum entry`);
      seen.add(target);
      if (!entry.actual) failures.push(`${checksumName}: missing asset ${target}`);
      else if (entry.actual !== entry.expected) failures.push(`${checksumName}: hash mismatch for ${target}`);
    }
    for (const member of expectedMembers) {
      const matching = entries.filter((entry) => entry.checksum === checksumName && entry.asset === member);
      if (matching.length !== 1) failures.push(`${checksumName}: expected exactly one entry for ${member}`);
    }
  }
  for (const primary of PRIMARY_ASSETS) {
    if (!seen.has(primary)) failures.push(`missing checksum entry for ${primary}`);
  }
  return {
    entries,
    failures,
    platformMismatches,
    passed: failures.length === 0 && platformMismatches.length === 0,
  };
}

function readPinnedManifestPublicKey() {
  const source = fs.readFileSync(PINNED_TRUST_CONFIG, 'utf8');
  const match = source.match(/windowsManifestPublicKeyBase64\s*=\s*['"]([^'"]+)['"]/u);
  if (!match) throw new Error(`Pinned Windows manifest key not found in ${PINNED_TRUST_CONFIG}`);
  return match[1];
}

function ed25519PublicKey(base64) {
  const raw = Buffer.from(String(base64).trim(), 'base64');
  if (raw.length === 32) {
    return crypto.createPublicKey({ key: Buffer.concat([ED25519_SPKI_PREFIX, raw]), format: 'der', type: 'spki' });
  }
  if (raw.length === 44) {
    return crypto.createPublicKey({ key: raw, format: 'der', type: 'spki' });
  }
  throw new Error('Windows manifest public key must be raw Ed25519 (32 bytes) or SPKI DER');
}

function verifyManifest(localDir, version, explicitPublicKey = null) {
  const manifestPath = path.join(localDir, 'Dacx-update-manifest-Windows-x64.json');
  const signaturePath = `${manifestPath}.sig`;
  const result = { status: 'failed', signature: fs.existsSync(signaturePath), checks: {} };
  if (!fs.existsSync(manifestPath)) {
    result.reason = 'manifest missing';
    return result;
  }
  try {
    const manifestBytes = fs.readFileSync(manifestPath);
    const manifest = JSON.parse(manifestBytes.toString('utf8'));
    const msiPath = path.join(localDir, 'Dacx-Windows-x64.msi');
    const expectedHash = manifest.assets?.['Dacx-Windows-x64.msi'];
    const actualHash = fs.existsSync(msiPath) ? sha256(msiPath) : null;
    const publicKey = ed25519PublicKey(explicitPublicKey || readPinnedManifestPublicKey());
    let signatureValid = false;
    let signatureError = null;
    try {
      const signatureText = fs.readFileSync(signaturePath, 'utf8').trim();
      if (!/^[A-Za-z0-9+/]+={0,2}$/u.test(signatureText)) throw new Error('signature is not base64');
      const signatureBytes = Buffer.from(signatureText, 'base64');
      if (signatureBytes.length !== 64) throw new Error('signature must contain 64 bytes');
      signatureValid = crypto.verify(null, manifestBytes, publicKey, signatureBytes);
    } catch (error) {
      signatureError = error.message;
    }
    result.manifest = manifest;
    result.checks = {
      schema: manifest.schema === 1,
      app: manifest.app === 'Dacx',
      platform: manifest.platform === 'Windows-x64',
      version: manifest.version === version,
      signature: signatureValid,
      msiHash: Boolean(expectedHash && actualHash && String(expectedHash).toLowerCase() === actualHash),
    };
    result.status = Object.values(result.checks).every(Boolean) ? 'passed' : 'failed';
    if (result.status !== 'passed') {
      result.reason = signatureError || (result.checks.signature ? 'manifest checks failed' : 'manifest signature invalid');
    }
  } catch (error) {
    result.reason = `manifest invalid: ${error.message}`;
  }
  return result;
}

function commandExists(command) {
  const lookup = process.platform === 'win32' ? 'where.exe' : 'which';
  return spawnSync(lookup, [command], { stdio: 'ignore', windowsHide: true }).status === 0;
}

function verifyGpg(localDir, expectedFingerprint) {
  const fingerprint = String(expectedFingerprint || '').replace(/\s+/gu, '').toUpperCase();
  if (!/^[A-F0-9]{40,64}$/u.test(fingerprint)) {
    return { status: 'failed', reason: 'GPG fingerprint required (40- or 64-hex)', checks: [], fingerprintMismatches: [] };
  }
  if (!commandExists('gpg')) return { status: 'skipped', reason: 'gpg unavailable', checks: [], fingerprintMismatches: [] };
  const checks = [];
  const fingerprintMismatches = [];
  for (const asset of [...PRIMARY_ASSETS, ...CHECKSUM_ASSETS]) {
    const target = path.join(localDir, asset);
    const signature = `${target}.asc`;
    const result = spawnSync('gpg', ['--batch', '--status-fd', '1', '--verify', signature, target], {
      encoding: 'utf8',
      windowsHide: true,
    });
    const output = redact(`${result.stdout || ''}${result.stderr || ''}`.trim());
    const match = String(result.stdout || '').match(/^\[GNUPG:\] VALIDSIG ([A-F0-9]+)(?:\s|$)/imu);
    const actualFingerprint = match?.[1]?.toUpperCase() || null;
    const fingerprintMatches = actualFingerprint === fingerprint;
    if (!fingerprintMatches) fingerprintMismatches.push({ asset, expected: fingerprint, actual: actualFingerprint });
    checks.push({
      asset,
      status: result.status === 0 && Boolean(match) && fingerprintMatches ? 'passed' : 'failed',
      actualFingerprint,
      output,
    });
  }
  return {
    status: checks.every((check) => check.status === 'passed') ? 'passed' : 'failed',
    expectedFingerprint: fingerprint,
    checks,
    fingerprintMismatches,
  };
}

function proofPlatform(report) {
  const value = String(report.platform || '').toLowerCase();
  if (value === 'win' || value === 'windows') return 'windows';
  if (value === 'mac' || value === 'macos' || value === 'darwin') return 'macos';
  if (value === 'linux') return 'linux';
  return null;
}

function verifyProofReport(report, platform, version, localDir) {
  const failures = [];
  if (report.schema !== PACKAGE_PROOF_SCHEMA) failures.push(`schema must be ${PACKAGE_PROOF_SCHEMA}`);
  if (report.status !== 'passed') failures.push('status must be passed');
  if (report.releaseProof !== true) failures.push('releaseProof must be true');
  if (report.version !== version) failures.push(`version must be ${version}`);
  if (proofPlatform(report) !== platform) failures.push(`platform must be ${platform}`);
  const expectedArtifact = PLATFORM_PROOF_ASSETS[platform];
  const localArtifact = expectedArtifact ? path.join(localDir, expectedArtifact) : null;
  const localHash = localArtifact && fs.existsSync(localArtifact) ? sha256(localArtifact) : null;
  if (report.artifact?.name !== expectedArtifact) {
    failures.push(`artifact name must be ${expectedArtifact}`);
  }
  if (
    !localHash ||
    !/^[a-f0-9]{64}$/iu.test(String(report.artifact?.sha256 || '')) ||
    String(report.artifact.sha256).toLowerCase() !== localHash
  ) {
    failures.push(`artifact sha256 must match local ${expectedArtifact}`);
  }
  if (report.checks?.artifact?.exists !== true) failures.push('checks.artifact.exists must be true');
  if (report.checks?.hash?.status !== 'passed') failures.push('checks.hash.status must be passed');
  if (report.checks?.checksums?.status !== 'passed') failures.push('checks.checksums.status must be passed');
  if (report.checks?.proofMetadata?.status !== 'passed') failures.push('checks.proofMetadata.status must be passed');
  if (report.checks?.version?.status !== 'passed') failures.push('checks.version.status must be passed');
  if (report.checks?.executableBinding?.status !== 'passed') {
    failures.push('checks.executableBinding.status must be passed');
  }
  if (!Array.isArray(report.checks?.requiredPaths) || report.checks.requiredPaths.some((check) => check.status !== 'passed')) {
    failures.push('checks.requiredPaths must be an array containing no failures');
  }
  if (report.checks?.launch?.status !== 'passed') failures.push('checks.launch.status must be passed');
  if (report.checks?.launch?.process?.status !== 'passed') {
    failures.push('checks.launch.process.status must be passed');
  }
  if (report.checks?.launch?.playback?.status !== 'passed') {
    failures.push('checks.launch.playback.status must be passed');
  }
  if (!Array.isArray(report.checks?.trust) || report.checks.trust.length === 0 || report.checks.trust.some((check) => check.status !== 'passed')) {
    failures.push('checks.trust must contain only passed checks');
  }
  return failures;
}

function verifyProofs(proofDir, version, localDir) {
  const result = { directory: proofDir, reports: [], missing: [], failures: [], passed: false };
  if (!proofDir || !fs.existsSync(proofDir)) {
    result.missing = [...PLATFORM_PROOFS];
    return result;
  }
  const files = fs.readdirSync(proofDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith('.json') && entry.name !== 'report.json')
    .map((entry) => path.join(proofDir, entry.name));
  const found = new Set();
  for (const filePath of files) {
    let report;
    try {
      report = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (error) {
      result.failures.push(`${path.basename(filePath)}: invalid JSON (${error.message})`);
      continue;
    }
    const platform = proofPlatform(report) || PLATFORM_PROOFS.find((candidate) =>
      path.basename(filePath, '.json').toLowerCase() === candidate,
    );
    if (!platform) continue;
    found.add(platform);
    const failures = verifyProofReport(report, platform, version, localDir);
    result.reports.push({ file: filePath, platform, version: report.version, status: report.status, releaseProof: report.releaseProof, failures });
    result.failures.push(...failures.map((failure) => `${path.basename(filePath)}: ${failure}`));
  }
  result.missing = PLATFORM_PROOFS.filter((platform) => !found.has(platform));
  result.passed = result.missing.length === 0 && result.failures.length === 0;
  return result;
}

function remoteAssetsFromFile(filePath) {
  const parsed = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  if (Array.isArray(parsed)) return parsed;
  if (Array.isArray(parsed.assets)) return parsed.assets;
  throw new Error('remote assets file must contain an array or { assets: [] }');
}

async function downloadRemoteBytes(url) {
  const response = await fetch(url, { redirect: 'follow', signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error(`download returned HTTP ${response.status}`);
  const bytes = Buffer.from(await response.arrayBuffer());
  const temporary = path.join(os.tmpdir(), `dacx-release-verify-${process.pid}-${Date.now()}.bin`);
  try {
    fs.writeFileSync(temporary, bytes);
    return { size: fs.statSync(temporary).size, digest: sha256(temporary) };
  } finally {
    fs.rmSync(temporary, { force: true });
  }
}

async function verifyRemoteAssets(version, expectedNames, localDir, options, log) {
  let assets;
  let release = null;
  if (options.remoteAssetsFile) {
    assets = remoteAssetsFromFile(options.remoteAssetsFile);
  } else {
    const owner = process.env.GH_REPO_OWNER || 'BurntToasters';
    const name = process.env.GH_REPO_NAME || 'Dacx';
    const releases = githubApi('GET', `/repos/${owner}/${name}/releases?per_page=100`);
    release = Array.isArray(releases) ? releases.find((item) => item.tag_name === `v${version}`) : null;
    if (!release) return { status: 'failed', reason: `draft v${version} not found` };
    if (!release.draft) return { status: 'failed', reason: `release v${version} is already published` };
    assets = release.assets || [];
  }
  const actualNames = assets.map((asset) => asset.name).sort();
  const expected = [...expectedNames].sort();
  const missing = expected.filter((asset) => !actualNames.includes(asset));
  const unexpected = actualNames.filter((asset) => !expected.includes(asset));
  const digestMismatches = [];
  const sizeMismatches = [];
  const downloadFailures = [];
  for (const name of expectedNames) {
    const remote = assets.find((asset) => asset.name === name);
    const localPath = path.join(localDir, name);
    if (!remote || !fs.existsSync(localPath)) continue;
    const localSize = fs.statSync(localPath).size;
    const localDigest = sha256(localPath);
    if (typeof remote.size !== 'number' || remote.size !== localSize) sizeMismatches.push(name);
    const advertised = typeof remote.digest === 'string' ? remote.digest.split(':').pop().toLowerCase() : null;
    if (advertised) {
      if (!/^[a-f0-9]{64}$/u.test(advertised) || advertised !== localDigest) digestMismatches.push(name);
      continue;
    }
    if (!remote.browser_download_url) {
      downloadFailures.push(`${name}: no GitHub digest or download URL`);
      continue;
    }
    try {
      const downloaded = await downloadRemoteBytes(remote.browser_download_url);
      if (downloaded.size !== localSize) sizeMismatches.push(name);
      if (downloaded.digest !== localDigest) digestMismatches.push(name);
    } catch (error) {
      downloadFailures.push(`${name}: ${error.message}`);
      log.push(`${name}: ${error.message}`);
    }
  }
  return {
    status: missing.length === 0 && unexpected.length === 0 && digestMismatches.length === 0 && sizeMismatches.length === 0 && downloadFailures.length === 0 ? 'passed' : 'failed',
    tag: release?.tag_name || `v${version}`,
    draft: release?.draft ?? true,
    assets: actualNames,
    missing,
    unexpected,
    digestMismatches,
    sizeMismatches,
    downloadFailures,
  };
}

function createReport(version = null, local = null) {
  return {
    schema: 'dacx.release-proof.v1',
    version,
    tag: version ? `v${version}` : null,
    status: 'failed',
    releaseProof: false,
    local: { directory: local },
    primaryAssets: null,
    checksums: null,
    manifest: null,
    signatures: null,
    platformProof: null,
    remote: null,
    error: null,
    log: '',
  };
}

async function run(argv = process.argv.slice(2)) {
  const reportPath = reportPathHint(argv);
  let report = createReport();
  const log = [];
  try {
    const args = parseArgs(argv);
    const version = versionFromPackage();
    const proofDir = args.proofDir || path.join(ROOT, 'test-results', 'release-proof', version);
    const expectedNames = [
      ...PRIMARY_ASSETS,
      ...CHECKSUM_ASSETS,
      ...PRIMARY_ASSETS.map((name) => `${name}.asc`),
      ...CHECKSUM_ASSETS.map((name) => `${name}.asc`),
      'Dacx-update-manifest-Windows-x64.json',
      'Dacx-update-manifest-Windows-x64.json.sig',
    ];
    report = createReport(version, args.local);
    report.primaryAssets = verifyAssetSet(args.local);
    log.push(`Assets: ${report.primaryAssets.files.join(', ')}`);
    report.checksums = verifyChecksums(args.local);
    report.manifest = verifyManifest(args.local, version, args.manifestPublicKey);
    const expectedFingerprint = args.gpgFingerprint || process.env.GPG_FINGERPRINT || process.env.RELEASE_GPG_FINGERPRINT;
    report.signatures = args.verifySignatures
      ? verifyGpg(args.local, expectedFingerprint)
      : { status: 'not-requested', expectedFingerprint: expectedFingerprint || null };
    if (args.verifySignatures && report.signatures.status === 'skipped' && !args.allowGpgSkip) report.signatures.status = 'failed';
    report.platformProof = verifyProofs(proofDir, version, args.local);
    if (args.remote && !args.noRemote) {
      report.remote = await verifyRemoteAssets(version, expectedNames, args.local, args, log);
    } else {
      report.remote = { status: 'not-requested' };
    }
    const signaturePass = report.signatures.status === 'passed' || report.signatures.status === 'not-requested' || (report.signatures.status === 'skipped' && args.allowGpgSkip);
    report.releaseProof = [
      report.primaryAssets.passed,
      report.checksums.passed,
      report.manifest.status === 'passed',
      signaturePass,
      report.platformProof.passed,
      report.remote.status === 'passed' || report.remote.status === 'not-requested',
    ].every(Boolean);
    report.status = report.releaseProof ? 'passed' : 'failed';
    log.push(`Status: ${report.status}`);
  } catch (error) {
    report.error = redact(error.message || String(error));
    log.push(`ERROR: ${report.error}`);
  }
  report.log = redact(log.join('\n'));
  writeJson(reportPath, report);
  fs.writeFileSync(`${reportPath}.log`, `${redact(log.join('\n'))}\n`, 'utf8');
  return report.releaseProof ? 0 : 1;
}

if (require.main === module) {
  run()
    .then((code) => {
      process.exitCode = code;
    })
    .catch((error) => {
      console.error(error.message || String(error));
      process.exitCode = 1;
    });
}

module.exports = {
  PRIMARY_ASSETS,
  CHECKSUM_ASSETS,
  verifyAssetSet,
  verifyChecksums,
  verifyManifest,
  verifyProofs,
  verifyRemoteAssets,
  run,
};
