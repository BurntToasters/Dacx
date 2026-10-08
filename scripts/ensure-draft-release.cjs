// For some reason, I needed to make this script because GitHub started to split my releases into two drafts.
// make ONE machine the single creator (win), this script has two modes:
//   (default)  create-or-reuse the single draft. Run by the Windows machine only.
//   --wait     poll until that draft exists; NEVER create. Run by mac/linux so
//              they only ever reuse the draft Windows created (no duplicates).
// The draft targets the exact commit at the tip of the channel branch (main for
// stable, beta for beta/alpha), and waiters refuse a draft built from another commit.

const path = require('path');
const { execFileSync } = require('child_process');

try {
  require('dotenv').config();
} catch {
  // dotenv-cli usually loads .env already; the module itself is optional.
}
const { assertGitHubCliAuthenticated, githubApi } = require('./github-cli.cjs');
const {
  assertValidReleaseNotes,
  readReleaseNotes,
} = require('./release-notes.cjs');

const REPOSITORY_ROOT = path.resolve(__dirname, '..');
const RELEASE_REMOTE = 'origin';
const REPO_OWNER = 'BurntToasters';
const REPO_NAME = 'Dacx';
const GH_REQUEST_RETRIES = Number.parseInt(process.env.GH_REQUEST_RETRIES || '3', 10);
const GH_REQUEST_RETRY_DELAY_MS = Number.parseInt(
  process.env.GH_REQUEST_RETRY_DELAY_MS || '1500',
  10
);

// --wait mode: how long mac/linux will wait for the Windows machine to create
// the draft before giving up (defaults to 30 minutes, polling every 15s).
const WAIT_MODE = process.argv.slice(2).includes('--wait');
const WAIT_TIMEOUT_MS = Number.parseInt(process.env.RELEASE_DRAFT_WAIT_TIMEOUT_MS || '1800000', 10);
const WAIT_POLL_INTERVAL_MS = Number.parseInt(
  process.env.RELEASE_DRAFT_WAIT_POLL_MS || '15000',
  10
);

const packageJson = require('../package.json');
const VERSION = packageJson.version;
const TAG_NAME = 'v' + VERSION;
const IS_PRERELEASE = VERSION.includes('beta') || VERSION.includes('alpha');
const RELEASE_BODY = readReleaseNotes();
assertValidReleaseNotes(RELEASE_BODY, VERSION);
const RELEASE_BRANCH = IS_PRERELEASE ? 'beta' : 'main';

function git(args) {
  return execFileSync('git', args, {
    cwd: REPOSITORY_ROOT,
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
  }).trim();
}

// Returns the SHA of the latest commit on the channel branch, and only when the
// local checkout is that branch and matches the remote tip exactly.
function resolveReleaseCommit() {
  let branch;
  try {
    branch = git(['symbolic-ref', '--quiet', '--short', 'HEAD']);
  } catch {
    throw new Error(
      'Detached HEAD; check out ' + RELEASE_BRANCH + ' before releasing ' + VERSION + '.'
    );
  }
  if (branch !== RELEASE_BRANCH) {
    throw new Error(
      (IS_PRERELEASE ? 'Beta' : 'Stable') +
        ' release ' +
        VERSION +
        ' must be built from ' +
        RELEASE_BRANCH +
        ', but the checkout is on ' +
        branch +
        '.'
    );
  }

  const remoteRef = 'refs/remotes/' + RELEASE_REMOTE + '/' + RELEASE_BRANCH;
  try {
    git(['fetch', '--quiet', RELEASE_REMOTE, '+refs/heads/' + RELEASE_BRANCH + ':' + remoteRef]);
  } catch (error) {
    const detail = String(error.stderr || error.message || '').trim();
    throw new Error(
      'Could not fetch ' + RELEASE_REMOTE + '/' + RELEASE_BRANCH + (detail ? ': ' + detail : '.'),
      { cause: error }
    );
  }

  const head = git(['rev-parse', 'HEAD']);
  const remoteHead = git(['rev-parse', remoteRef]);
  if (!/^[0-9a-f]{40,64}$/i.test(head)) {
    throw new Error('Could not resolve an exact release commit from git HEAD.');
  }
  if (head !== remoteHead) {
    throw new Error(
      'Local ' +
        RELEASE_BRANCH +
        ' is at ' +
        head.slice(0, 12) +
        ' but ' +
        RELEASE_REMOTE +
        '/' +
        RELEASE_BRANCH +
        ' is at ' +
        remoteHead.slice(0, 12) +
        '. Pull or push so the release targets the latest pushed commit.'
    );
  }
  return head;
}

function isExplicitTruthy(value) {
  return /^(1|true|yes|on)$/i.test(String(value || '').trim());
}

function assertReleaseTargetsCommit(release, commit) {
  if (!release || !release.draft || release.target_commitish === commit) return release;
  const target = release.target_commitish || 'an unknown commit';
  if (isExplicitTruthy(process.env.FORCE_UPLOAD)) {
    console.warn(
      'WARNING: Draft release ' +
        TAG_NAME +
        ' targets ' +
        target +
        ', not checked-out commit ' +
        commit +
        '. FORCE_UPLOAD=1 bypassing commit check.'
    );
    return release;
  }
  throw new Error(
    'Draft release ' +
      TAG_NAME +
      ' targets ' +
      target +
      ', not checked-out commit ' +
      commit +
      '. Delete or retarget the stale draft, or set FORCE_UPLOAD=1 to bypass.'
  );
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function isRetryableGithubError(error) {
  if (!error) return false;

  const retryableStatusCodes = new Set([408, 409, 425, 429, 500, 502, 503, 504]);
  const retryableCodes = new Set([
    'ETIMEDOUT',
    'ECONNRESET',
    'ENOTFOUND',
    'EAI_AGAIN',
    'ECONNREFUSED',
    'EPIPE',
  ]);

  if (typeof error.statusCode === 'number' && retryableStatusCodes.has(error.statusCode)) {
    return true;
  }
  if (typeof error.code === 'string' && retryableCodes.has(error.code)) {
    return true;
  }

  const msg = String(error.message || '').toLowerCase();
  return msg.includes('timeout') || msg.includes('socket hang up') || msg.includes('aborted');
}

function githubRequest(method, endpoint, body) {
  return Promise.resolve(githubApi(method, endpoint, body));
}

async function githubRequestWithRetry(method, endpoint, body) {
  const attempts = Math.max(1, GH_REQUEST_RETRIES);

  for (let attempt = 1; attempt <= attempts; attempt++) {
    try {
      return await githubRequest(method, endpoint, body);
    } catch (error) {
      const canRetry = attempt < attempts && isRetryableGithubError(error);
      if (!canRetry) {
        throw error;
      }

      const backoffMs = GH_REQUEST_RETRY_DELAY_MS * attempt;
      console.log(
        '   Retry ' +
          attempt +
          '/' +
          (attempts - 1) +
          ' in ' +
          backoffMs +
          'ms (' +
          error.message +
          ')'
      );
      await sleep(backoffMs);
    }
  }
}

async function findExistingRelease() {
  // Draft releases are not returned by the "get release by tag" endpoint
  // (no git tag exists yet), so we list and match on tag_name.
  const releases = await githubRequestWithRetry(
    'GET',
    '/repos/' + REPO_OWNER + '/' + REPO_NAME + '/releases?per_page=100'
  );

  if (!Array.isArray(releases)) {
    throw new Error('Unexpected releases payload type');
  }

  const matching = releases.filter((r) => r.tag_name === TAG_NAME);
  if (matching.length === 0) {
    return null;
  }

  // Prefer a draft (electron-builder publishes into drafts); fall back to any.
  const draft = matching.find((r) => r.draft);
  return draft || matching[0];
}

async function ensureDraftRelease(commit) {
  console.log(
    'Ensuring draft release exists for ' +
      TAG_NAME +
      ' targeting ' +
      RELEASE_BRANCH +
      '@' +
      commit.slice(0, 12) +
      '...'
  );

  const existing = await findExistingRelease();
  if (existing) {
    assertReleaseTargetsCommit(existing, commit);
    if (existing.draft && existing.body !== RELEASE_BODY) {
      console.log('   Draft exists but release notes differ; updating body...');
      return await githubRequestWithRetry(
        'PATCH',
        '/repos/' + REPO_OWNER + '/' + REPO_NAME + '/releases/' + existing.id,
        {
          body: RELEASE_BODY,
          prerelease: IS_PRERELEASE,
        }
      );
    }
    console.log(
      (existing.draft ? '   Draft already exists: ' : '   Published release already exists: ') +
        (existing.name || TAG_NAME) +
        ' (id ' +
        existing.id +
        ', ' +
        (existing.assets ? existing.assets.length : 0) +
        ' assets) - skipping create.'
    );
    return existing;
  }

  console.log('   No release found. Creating draft...');
  try {
    const release = await githubRequestWithRetry(
      'POST',
      '/repos/' + REPO_OWNER + '/' + REPO_NAME + '/releases',
      {
        // Match electron-builder's createRelease() so it reuses this draft:
        // tag = "v" + version, name defaults to the version, draft:true.
        tag_name: TAG_NAME,
        target_commitish: commit,
        name: VERSION,
        draft: true,
        prerelease: IS_PRERELEASE,
        body: RELEASE_BODY,
      }
    );
    console.log('   Created draft release: ' + (release.name || TAG_NAME) + ' (id ' + release.id + ')');
    return release;
  } catch (error) {
    // Another concurrent run may have created it (422 already_exists) - re-fetch.
    if (error.statusCode === 422) {
      console.log('   Create returned 422; re-checking for existing draft...');
      await sleep(2000);
      const afterRetry = await findExistingRelease();
      if (afterRetry) {
        console.log('   Found existing draft after retry: id ' + afterRetry.id);
        return assertReleaseTargetsCommit(afterRetry, commit);
      }
    }
    throw error;
  }
}

async function waitForDraftRelease(commit) {
  const deadline = Date.now() + WAIT_TIMEOUT_MS;
  console.log(
    'Waiting for draft release ' +
      TAG_NAME +
      ' (created by the Windows machine); will NOT create it here...'
  );

  let attempt = 0;
  for (;;) {
    attempt += 1;
    const existing = await findExistingRelease();
    if (existing) {
      assertReleaseTargetsCommit(existing, commit);
      console.log(
        '   Found draft: ' +
          (existing.name || TAG_NAME) +
          ' (id ' +
          existing.id +
          ', ' +
          (existing.assets ? existing.assets.length : 0) +
          ' assets). Proceeding.'
      );
      return existing;
    }

    if (Date.now() >= deadline) {
      throw new Error(
        'Timed out after ' +
          Math.round(WAIT_TIMEOUT_MS / 1000) +
          's waiting for draft ' +
          TAG_NAME +
          '. Run "npm run release:draft" on the Windows machine first (or run it here once), then retry.'
      );
    }

    console.log(
      '   Draft not found yet (attempt ' +
        attempt +
        '); re-checking in ' +
        Math.round(WAIT_POLL_INTERVAL_MS / 1000) +
        's...'
    );
    await sleep(WAIT_POLL_INTERVAL_MS);
  }
}

async function main() {
  const commit = resolveReleaseCommit();
  assertGitHubCliAuthenticated();

  if (WAIT_MODE) {
    await waitForDraftRelease(commit);
  } else {
    await ensureDraftRelease(commit);
  }
}

main().catch((error) => {
  const message = error && error.message ? error.message : String(error);
  console.error('✗ ERROR: Failed to ensure draft release: ' + message);
  process.exit(1);
});
