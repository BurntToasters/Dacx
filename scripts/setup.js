// WIN: Requires winget and VS C++
// MAC: Requires Homebrew
// Linux: Requires Deb/Ubuntu-based

import { execSync } from 'node:child_process';
import { platform } from 'node:os';

const target = process.argv[2];
if (!['win', 'mac', 'linux'].includes(target)) {
  console.error('Usage: node scripts/setup.js <win|mac|linux>');
  process.exit(1);
}

// Helpers
function run(cmd, opts = {}) {
  console.log(`\n▶ ${cmd}`);
  try {
    execSync(cmd, { stdio: 'inherit', shell: true, ...opts });
    return true;
  } catch {
    if (!opts.allowFail) {
      console.error(`✖ Command failed: ${cmd}`);
      process.exit(1);
    }
    return false;
  }
}

function hasCmd(name) {
  try {
    const check = platform() === 'win32'
      ? `where ${name} 2>nul`
      : `command -v ${name}`;
    execSync(check, { stdio: 'ignore', shell: true });
    return true;
  } catch {
    return false;
  }
}

function header(msg) {
  console.log(`\n${'─'.repeat(60)}\n  ${msg}\n${'─'.repeat(60)}`);
}

// Win

function setupWindows() {
  header('DACX — Windows setup');

  // Flutter
  if (!hasCmd('flutter')) {
    console.log('\nFlutter not found. Attempting install via winget...');
    if (hasCmd('winget')) {
      run('winget install --id Google.Flutter -e --accept-source-agreements --accept-package-agreements', { allowFail: true });
      console.log('\n⚠  You may need to restart your terminal / re-open SSH session so flutter is on PATH.');
    } else {
      console.error(
        '\n✖ winget is not available. Install Flutter manually:\n' +
        '  https://docs.flutter.dev/get-started/install/windows/desktop\n' +
        '  Then re-run this script.'
      );
      process.exit(1);
    }
  } else {
    console.log('✔ Flutter found');
  }

  // Visual Studio Build Tools check
  console.log('\n⚠  Windows desktop builds require Visual Studio Build Tools with the');
  console.log('   "Desktop development with C++" workload. If not installed:');
  console.log('   winget install Microsoft.VisualStudio.2022.BuildTools');
  console.log('   Then add the C++ desktop workload via the VS Installer.');

  // Common steps
  commonSetup();

  header('Windows setup complete');
  console.log('Run "flutter doctor" to verify everything is configured.');
  console.log('Run "npm run dev:win" to start the app.\n');
}

// macOS

function setupMac() {
  header('DACX — macOS setup');

  // Xcode CLI tools
  console.log('\nChecking Xcode command-line tools...');
  run('xcode-select --install 2>/dev/null || true', { allowFail: true });
  run('sudo xcodebuild -license accept 2>/dev/null || true', { allowFail: true });

  // Homebrew
  if (!hasCmd('brew')) {
    console.error(
      '\n✖ Homebrew is required but not installed.\n' +
      '  Install it from https://brew.sh then re-run this script.'
    );
    process.exit(1);
  } else {
    console.log('✔ Homebrew found');
  }

  // Flutter
  if (!hasCmd('flutter')) {
    console.log('\nInstalling Flutter via Homebrew...');
    run('brew install --cask flutter');
    console.log('\n⚠  You may need to restart your terminal / re-open SSH session so flutter is on PATH.');
  } else {
    console.log('✔ Flutter found');
  }

  // CocoaPods
  if (!hasCmd('pod')) {
    console.log('\nInstalling CocoaPods...');
    run('brew install cocoapods');
  } else {
    console.log('✔ CocoaPods found');
  }

  // Common steps
  commonSetup();

  header('macOS setup complete');
  console.log('Run "flutter doctor" to verify everything is configured.');
  console.log('Run "npm run dev:mac" to start the app.\n');
}

// Linux

function setupLinux() {
  header('DACX — Linux setup (apt-based)');

  // System packages for Flutter desktop + media_kit (libmpv)
  const packages = [
    'clang', 'cmake', 'ninja-build', 'pkg-config',
    'libgtk-3-dev', 'libmpv-dev', 'mpv',
    'libunwind-dev',
    'curl', 'git', 'unzip', 'xz-utils', 'zip',
  ];

  console.log('\nInstalling system packages...');
  run(`sudo apt-get update`);
  run(`sudo apt-get install -y ${packages.join(' ')}`);

  // Flutter via snap
  if (!hasCmd('flutter')) {
    console.log('\nInstalling Flutter via snap...');
    if (hasCmd('snap')) {
      run('sudo snap install flutter --classic');
    } else {
      console.log('snap not available. Trying manual install...');
      run('sudo apt-get install -y snapd', { allowFail: true });
      if (hasCmd('snap')) {
        run('sudo snap install flutter --classic');
      } else {
        console.error(
          '\n✖ Could not install Flutter automatically.\n' +
          '  Install manually: https://docs.flutter.dev/get-started/install/linux/desktop\n' +
          '  Then re-run this script.'
        );
        process.exit(1);
      }
    }
    console.log('\n⚠  You may need to restart your terminal / re-open SSH session so flutter is on PATH.');
  } else {
    console.log('✔ Flutter found');
  }

  commonSetup();

  header('Linux setup complete');
  console.log('Run "flutter doctor" to verify everything is configured.');
  console.log('Run "npm run dev:linux" to start the app.\n');
}

// all platforms

function commonSetup() {
  header('Common setup');

  // Flutter desktop support
  const desktopDevice = target === 'win' ? 'windows' : target === 'mac' ? 'macos' : 'linux';
  run(`flutter config --enable-${desktopDevice}-desktop`, { allowFail: true });

  // doctor
  run('flutter doctor -v', { allowFail: true });

  // Dart/Flutter
  console.log('\nInstalling Dart/Flutter packages...');
  run('flutter pub get');

  // npm
  console.log('\nInstalling npm packages...');
  run('npm install');
}

switch (target) {
  case 'win':   setupWindows(); break;
  case 'mac':   setupMac();     break;
  case 'linux': setupLinux();   break;
}
