// Ensures fvm is installed and the Flutter version pinned in .fvmrc is
// available locally. Safe to run on dev machines and CI/release VMs; exits
// quickly when already in sync.

import { execSync } from 'node:child_process';
import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import { delimiter, join } from 'node:path';
import { homedir } from 'node:os';
import crossSpawn from 'cross-spawn';

// Pub installs global executables here; fvm lands here after activation.
// We prepend this to PATH for child processes so `fvm` resolves even on
// fresh machines where the user hasn't manually added it.
function pubBinDir() {
  if (process.platform === 'win32') {
    return join(process.env.LOCALAPPDATA || join(homedir(), 'AppData', 'Local'),
      'Pub', 'Cache', 'bin');
  }
  return join(homedir(), '.pub-cache', 'bin');
}

const childEnv = {
  ...process.env,
  PATH: `${pubBinDir()}${delimiter}${process.env.PATH || ''}`,
};

function run(cmd, args, opts = {}) {
  const result = crossSpawn.sync(cmd, args, {
    stdio: 'inherit',
    env: childEnv,
    windowsHide: true,
    ...opts,
  });
  if (result.error) throw result.error;
  if ((result.status ?? 1) !== 0) {
    throw new Error(`${cmd} ${args.join(' ')} exited with ${result.status}`);
  }
  return result;
}

function capture(cmd, args) {
  const result = crossSpawn.sync(cmd, args, {
    encoding: 'utf8',
    stdio: ['ignore', 'pipe', 'pipe'],
    env: childEnv,
    windowsHide: true,
  });
  if (result.error) throw result.error;
  if ((result.status ?? 1) !== 0) {
    throw new Error(result.stderr || `${cmd} ${args.join(' ')} exited with ${result.status}`);
  }
  return (result.stdout || '').trim();
}

function has(cmd) {
  const result = crossSpawn.sync(
    process.platform === 'win32' ? 'where' : 'which',
    [cmd],
    { stdio: 'ignore', env: childEnv, windowsHide: true },
  );
  return result.status === 0;
}

const fvmrcPath = join(process.cwd(), '.fvmrc');
if (!existsSync(fvmrcPath)) {
  console.error('✖ .fvmrc not found. Run `fvm use <version>` first to pin Flutter.');
  process.exit(1);
}

let pinned = '';
try {
  pinned = JSON.parse(readFileSync(fvmrcPath, 'utf8')).flutter;
} catch (e) {
  console.error(`✖ Could not parse .fvmrc: ${e.message ?? e}`);
  process.exit(1);
}
if (!pinned) {
  console.error('✖ .fvmrc has no `flutter` field.');
  process.exit(1);
}
if (!/^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$/.test(pinned)) {
  console.error(`✖ .fvmrc flutter version is not a valid pinned version: "${pinned}"`);
  process.exit(1);
}

console.log(`Pinned Flutter version: ${pinned}`);

if (!has('fvm')) {
  console.log('▶ fvm not found; installing via `dart pub global activate fvm`');
  run('dart', ['pub', 'global', 'activate', 'fvm']);
}

let installed = '';
try {
  installed = capture('fvm', ['api', 'list']);
} catch {
  installed = '';
}
if (installed.includes(`"${pinned}"`)) {
  console.log(`✓ Flutter ${pinned} already installed via fvm`);
} else {
  console.log(`▶ Installing Flutter ${pinned} via fvm`);
  run('fvm', ['install', pinned]);
}

// Verify by running `fvm flutter --version` so any download/setup completes.
run('fvm', ['flutter', '--version']);

// Persist `fvm` on the user's shell PATH so subsequent npm scripts that call
// `fvm flutter` directly resolve it. Idempotent; checked before writing.
ensurePubBinOnPath();
console.log(`✓ fvm flutter pinned to ${pinned} and ready`);

function ensurePubBinOnPath() {
  const bin = pubBinDir();
  const userPath = process.env.PATH || '';
  if (userPath.split(delimiter).some((p) => p.toLowerCase() === bin.toLowerCase())) {
    return;
  }
  if (process.env.CI) {
    // CI workflows handle PATH via GITHUB_PATH / equivalents.
    return;
  }
  try {
    if (process.platform === 'win32') {
      addToWindowsUserPath(bin);
    } else {
      addToShellRc(bin);
    }
  } catch (e) {
    console.log('');
    console.log('⚠  Could not auto-add to PATH; do it manually:');
    console.log(`     ${bin}`);
    console.log(`   Reason: ${e.message ?? e}`);
  }
}

function addToWindowsUserPath(bin) {
  // Use User-scope SetEnvironmentVariable via PowerShell; no admin needed,
  // persists across shells, idempotent guard avoids duplicate entries.
  const psCmd =
    `$bin = '${bin.replace(/'/g, "''")}'; ` +
    `$current = [Environment]::GetEnvironmentVariable('Path','User'); ` +
    `if ($current -split ';' | Where-Object { $_ -ieq $bin }) { 'already' } ` +
    `else { [Environment]::SetEnvironmentVariable('Path', ($current + ';' + $bin), 'User'); 'added' }`;
  const result = execSync(`powershell -NoProfile -Command "${psCmd}"`, {
    encoding: 'utf8',
  }).trim();
  if (result === 'added') {
    console.log('');
    console.log(`✓ Added to User PATH: ${bin}`);
    console.log('  Restart your shell to pick it up in this session.');
  }
}

function addToShellRc(bin) {
  // Append to whichever rc files exist for the user's likely shells. macOS
  // defaults to zsh and sources .zprofile for login shells (SSH) + .zshrc for
  // interactive; most Linux distros default to bash; I also added fish because I use it.
  // Write to all that exist so the user is covered regardless of which shell
  // they launch.
  const home = homedir();
  const targets = [
    join(home, '.zprofile'),
    join(home, '.zshrc'),
    join(home, '.bashrc'),
    join(home, '.bash_profile'),
    join(home, '.profile'),
    join(home, '.config', 'fish', 'config.fish'),
  ].filter((p) => existsSync(p));

  if (targets.length === 0) {
    // No rc file exists yet; create .profile as a safe default.
    targets.push(join(home, '.profile'));
  }

  const marker = '# Added by dacx setup:flutter: fvm bin';
  let wrote = false;
  for (const file of targets) {
    const isFish = file.endsWith('config.fish');
    const line = isFish
      ? `set -gx PATH "${bin}" $PATH`
      : `export PATH="${bin}:$PATH"`;
    const existing = existsSync(file) ? readFileSync(file, 'utf8') : '';
    if (existing.includes(marker) || existing.includes(line)) continue;
    appendFileSync(file, `\n${marker}\n${line}\n`);
    console.log(`✓ Appended PATH update to ${file}`);
    wrote = true;
  }
  if (wrote) {
    console.log('  Open a new shell (or source the file) to pick up `fvm`.');
  }
}
