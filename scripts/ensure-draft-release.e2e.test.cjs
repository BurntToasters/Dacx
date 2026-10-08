const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const test = require('node:test');

// Runs the real ensure-draft-release.cjs inside a throwaway git repo that has a
// real bare "origin", with a stub `gh` on PATH that records GitHub API calls.
// Covers scripts/ensure-draft-release.failures.md.

const root = path.dirname(path.dirname(__filename));
const artifactDir = path.join(root, 'test-results', 'ensure-draft-release');
const copiedScripts = ['ensure-draft-release.cjs', 'github-cli.cjs', 'release-notes.cjs'];
const report = [];

const skip = process.platform === 'win32' ? 'stub gh is a POSIX shebang script' : false;

const FAKE_GH = `#!/usr/bin/env node
const fs = require('fs');
const statePath = process.env.FAKE_GH_STATE;
const state = JSON.parse(fs.readFileSync(statePath, 'utf8'));
const args = process.argv.slice(2);
const save = () => fs.writeFileSync(statePath, JSON.stringify(state, null, 2));
if (args[0] === 'auth') process.exit(0);
const method = args[args.indexOf('--method') + 1];
const endpoint = args[3];
const body = args.includes('--input') ? JSON.parse(fs.readFileSync(0, 'utf8') || '{}') : null;
state.calls.push({ method, endpoint, body });
let out;
if (method === 'GET' && endpoint.includes('/releases?')) {
  out = state.releases;
} else if (method === 'POST' && endpoint.endsWith('/releases')) {
  out = { id: state.releases.length + 1, assets: [], ...body };
  if (!('target_commitish' in body)) out.target_commitish = 'main';
  state.releases.push(out);
} else if (method === 'PATCH') {
  const id = Number(endpoint.split('/').pop());
  out = state.releases.find((r) => r.id === id);
  Object.assign(out, body);
} else {
  save();
  process.stderr.write('stub gh: unhandled ' + method + ' ' + endpoint + ' (HTTP 404)');
  process.exit(1);
}
save();
process.stdout.write(JSON.stringify(out));
`;

function sh(cwd, cmd, args) {
  const result = spawnSync(cmd, args, { cwd, encoding: 'utf8' });
  if (result.status !== 0) {
    throw new Error(`${cmd} ${args.join(' ')} failed: ${result.stderr}`);
  }
  return result.stdout.trim();
}

function changelog(version) {
  const beta = version.includes('beta');
  return (
    (beta ? '> [!NOTE]\n> This is a Beta build.\n\n' : '') +
    `[Download](https://github.com/BurntToasters/Dacx/releases/download/v${version}/Dacx-macOS.dmg)\n\n` +
    `## Changes in \`v${version}:\`\n- Fixture entry.\n`
  );
}

// Builds origin (bare) with main and beta, and a clone checked out on `branch`.
function fixture({ version, branch }) {
  const base = fs.mkdtempSync(path.join(os.tmpdir(), 'dacx-draft-target-'));
  const origin = path.join(base, 'origin.git');
  const work = path.join(base, 'work');
  const bin = path.join(base, 'bin');
  fs.mkdirSync(path.join(work, 'scripts'), { recursive: true });
  fs.mkdirSync(bin);
  sh(base, 'git', ['init', '--quiet', '--bare', origin]);
  sh(work, 'git', ['init', '--quiet', '-b', 'main']);
  sh(work, 'git', ['config', 'user.email', 'e2e@example.invalid']);
  sh(work, 'git', ['config', 'user.name', 'e2e']);
  sh(work, 'git', ['config', 'commit.gpgsign', 'false']);
  sh(work, 'git', ['remote', 'add', 'origin', origin]);
  for (const name of copiedScripts) {
    fs.copyFileSync(path.join(root, 'scripts', name), path.join(work, 'scripts', name));
  }
  fs.writeFileSync(path.join(work, 'package.json'), JSON.stringify({ version }) + '\n');
  fs.writeFileSync(path.join(work, 'CHANGELOG.md'), changelog(version));
  sh(work, 'git', ['add', '-A']);
  sh(work, 'git', ['commit', '--quiet', '-m', 'main base']);
  sh(work, 'git', ['push', '--quiet', 'origin', 'main']);
  sh(work, 'git', ['checkout', '--quiet', '-b', 'beta']);
  sh(work, 'git', ['commit', '--quiet', '--allow-empty', '-m', 'beta tip']);
  sh(work, 'git', ['push', '--quiet', 'origin', 'beta']);
  sh(work, 'git', ['checkout', '--quiet', branch]);
  fs.writeFileSync(path.join(bin, 'gh'), FAKE_GH, { mode: 0o755 });
  const statePath = path.join(base, 'gh-state.json');
  fs.writeFileSync(statePath, JSON.stringify({ releases: [], calls: [] }));
  return { base, work, bin, statePath, origin };
}

function run(fx, args = [], env = {}) {
  const result = spawnSync(process.execPath, [path.join(fx.work, 'scripts', 'ensure-draft-release.cjs'), ...args], {
    cwd: fx.work,
    encoding: 'utf8',
    env: {
      ...process.env,
      PATH: fx.bin + path.delimiter + process.env.PATH,
      FAKE_GH_STATE: fx.statePath,
      FORCE_UPLOAD: '',
      GH_REQUEST_RETRIES: '1',
      RELEASE_DRAFT_WAIT_TIMEOUT_MS: '0',
      RELEASE_DRAFT_WAIT_POLL_MS: '1',
      ...env,
    },
  });
  return { ...result, state: JSON.parse(fs.readFileSync(fx.statePath, 'utf8')) };
}

function seedDraft(fx, version, target) {
  const state = JSON.parse(fs.readFileSync(fx.statePath, 'utf8'));
  state.releases.push({
    id: 1,
    tag_name: 'v' + version,
    name: version,
    draft: true,
    prerelease: version.includes('beta'),
    target_commitish: target,
    body: 'stale',
    assets: [],
  });
  fs.writeFileSync(fx.statePath, JSON.stringify(state));
}

function record(name, fx, result, expected) {
  report.push({
    name,
    expected,
    status: result.status,
    head: sh(fx.work, 'git', ['rev-parse', 'HEAD']),
    stdout: result.stdout,
    stderr: result.stderr,
    githubCalls: result.state.calls,
    releases: result.state.releases,
  });
}

const writes = (state) => state.calls.filter((c) => c.method !== 'GET');

test.after(() => {
  if (!report.length) return;
  fs.rmSync(artifactDir, { recursive: true, force: true });
  fs.mkdirSync(artifactDir, { recursive: true });
  fs.writeFileSync(path.join(artifactDir, 'report.json'), JSON.stringify(report, null, 2) + '\n');
});

test('stable draft from main targets the main tip commit', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  const mainTip = sh(fx.work, 'git', ['rev-parse', 'origin/main']);
  const result = run(fx);
  record('stable-main-creates-draft', fx, result, 'draft targets main tip');
  assert.equal(result.status, 0, result.stderr);
  const [post] = writes(result.state);
  assert.equal(post.method, 'POST');
  assert.equal(post.body.target_commitish, mainTip);
  assert.equal(post.body.prerelease, false);
  assert.equal(post.body.draft, true);
});

test('beta draft from beta targets the beta tip commit, not main', { skip }, () => {
  const fx = fixture({ version: '1.0.0-beta.1', branch: 'beta' });
  const betaTip = sh(fx.work, 'git', ['rev-parse', 'origin/beta']);
  const mainTip = sh(fx.work, 'git', ['rev-parse', 'origin/main']);
  const result = run(fx);
  record('beta-beta-creates-draft', fx, result, 'draft targets beta tip');
  assert.equal(result.status, 0, result.stderr);
  const [post] = writes(result.state);
  assert.equal(post.body.target_commitish, betaTip);
  assert.notEqual(post.body.target_commitish, mainTip);
  assert.equal(post.body.prerelease, true);
});

test('stable version on beta branch is refused before any GitHub call', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'beta' });
  const result = run(fx);
  record('stable-on-beta-refused', fx, result, 'refused, no GitHub calls');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must be built from main, but the checkout is on beta/);
  assert.equal(result.state.calls.length, 0);
});

test('beta version on main branch is refused', { skip }, () => {
  const fx = fixture({ version: '1.0.0-beta.1', branch: 'main' });
  const result = run(fx);
  record('beta-on-main-refused', fx, result, 'refused, no GitHub calls');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /must be built from beta, but the checkout is on main/);
  assert.equal(result.state.calls.length, 0);
});

test('detached HEAD is refused', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  sh(fx.work, 'git', ['checkout', '--quiet', '--detach']);
  const result = run(fx);
  record('detached-head-refused', fx, result, 'refused, no GitHub calls');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Detached HEAD/);
  assert.equal(result.state.calls.length, 0);
});

test('unpushed local commit is refused', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  sh(fx.work, 'git', ['commit', '--quiet', '--allow-empty', '-m', 'local only']);
  const result = run(fx);
  record('unpushed-commit-refused', fx, result, 'refused, no GitHub calls');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Pull or push so the release targets the latest pushed commit/);
  assert.equal(result.state.calls.length, 0);
});

test('checkout behind origin is refused so the draft cannot target an old commit', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  const other = path.join(fx.base, 'other');
  sh(fx.base, 'git', ['clone', '--quiet', '-b', 'main', fx.origin, other]);
  sh(other, 'git', ['-c', 'user.email=e@x.invalid', '-c', 'user.name=x', '-c', 'commit.gpgsign=false',
    'commit', '--quiet', '--allow-empty', '-m', 'newer upstream']);
  sh(other, 'git', ['push', '--quiet', 'origin', 'main']);
  const result = run(fx);
  record('behind-origin-refused', fx, result, 'refused, no GitHub calls');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /but origin\/main is at/);
  assert.equal(result.state.calls.length, 0);
});

test('missing origin branch fails closed', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  sh(fx.work, 'git', ['push', '--quiet', 'origin', '--delete', 'main']);
  const result = run(fx);
  record('missing-origin-branch-refused', fx, result, 'refused, no GitHub calls');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Could not fetch origin\/main/);
  assert.equal(result.state.calls.length, 0);
});

test('creator refuses to reuse a draft that targets a stale commit', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  seedDraft(fx, '1.0.0', '0'.repeat(40));
  const result = run(fx);
  record('creator-stale-draft-refused', fx, result, 'refused, draft untouched');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /Delete or retarget the stale draft/);
  assert.equal(writes(result.state).length, 0);
});

test('creator refreshes notes on a matching draft without changing its target', { skip }, () => {
  const fx = fixture({ version: '1.0.0', branch: 'main' });
  const head = sh(fx.work, 'git', ['rev-parse', 'HEAD']);
  seedDraft(fx, '1.0.0', head);
  const result = run(fx);
  record('creator-refresh-keeps-target', fx, result, 'PATCH body only, target kept');
  assert.equal(result.status, 0, result.stderr);
  const [patch] = writes(result.state);
  assert.equal(patch.method, 'PATCH');
  assert.equal('target_commitish' in patch.body, false);
  assert.equal(result.state.releases[0].target_commitish, head);
});

test('waiter proceeds when the draft targets its checked-out commit', { skip }, () => {
  const fx = fixture({ version: '1.0.0-beta.1', branch: 'beta' });
  seedDraft(fx, '1.0.0-beta.1', sh(fx.work, 'git', ['rev-parse', 'HEAD']));
  const result = run(fx, ['--wait']);
  record('waiter-matching-draft', fx, result, 'proceeds, no writes');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stdout, /Proceeding/);
  assert.equal(writes(result.state).length, 0);
});

test('waiter refuses a draft built from another commit', { skip }, () => {
  const fx = fixture({ version: '1.0.0-beta.1', branch: 'beta' });
  seedDraft(fx, '1.0.0-beta.1', sh(fx.work, 'git', ['rev-parse', 'origin/main']));
  const result = run(fx, ['--wait']);
  record('waiter-mismatched-draft-refused', fx, result, 'refused');
  assert.notEqual(result.status, 0);
  assert.match(result.stderr, /not checked-out commit/);
});

test('FORCE_UPLOAD=1 bypasses a target mismatch with a visible warning', { skip }, () => {
  const fx = fixture({ version: '1.0.0-beta.1', branch: 'beta' });
  seedDraft(fx, '1.0.0-beta.1', '0'.repeat(40));
  const result = run(fx, ['--wait'], { FORCE_UPLOAD: '1' });
  record('force-upload-bypass-warns', fx, result, 'proceeds with warning');
  assert.equal(result.status, 0, result.stderr);
  assert.match(result.stderr, /WARNING: .*FORCE_UPLOAD=1 bypassing commit check/);
});
