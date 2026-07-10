#!/usr/bin/env node

import { spawnSync } from 'node:child_process';

const allowedBranches = new Set(['main', 'beta', 'next-0.10.1']);

function runGit(args) {
  const result = spawnSync('git', args, {
    encoding: 'utf8',
    windowsHide: true,
  });
  if (result.status !== 0) {
    const stderr = (result.stderr ?? '').trim();
    throw new Error(stderr || `git ${args.join(' ')} failed`);
  }
  return (result.stdout ?? '').trim();
}

function fail(message) {
  console.error(`\nRelease guard failed: ${message}`);
  process.exit(1);
}

let branch;
let status;

try {
  branch = runGit(['rev-parse', '--abbrev-ref', 'HEAD']);
  status = runGit(['status', '--porcelain']);
} catch (error) {
  fail(error instanceof Error ? error.message : String(error));
}

if (!allowedBranches.has(branch)) {
  fail(
    `branch '${branch}' is not allowed. Allowed branches: ${[
      ...allowedBranches,
    ].join(', ')}`,
  );
}

if (status.length > 0) {
  fail('working tree is dirty. Commit/stash all changes before release.');
}

console.log(`Release guard passed on branch '${branch}' with a clean tree.`);
