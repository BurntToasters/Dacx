// WIN: Requires Flutter and VS C++
// MAC: Requires Homebrew
// Linux: Requires Deb/Ubuntu-based

import { execSync } from 'node:child_process';
import { existsSync } from 'node:fs';
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

function canRun(cmd) {
  try {
    execSync(cmd, { stdio: 'ignore', shell: true });
    return true;
  } catch {
    return false;
  }
}

function header(msg) {
  console.log(`\n${'─'.repeat(60)}\n  ${msg}\n${'─'.repeat(60)}`);
}

function resolveFlutterOnWindowsPath() {
  if (platform() !== 'win32') return hasCmd('flutter');
  if (hasCmd('flutter')) return true;

  const userProfile = process.env.USERPROFILE;
  const localAppData = process.env.LOCALAPPDATA;
  const candidates = [
    'C:\\src\\flutter\\bin',
    userProfile ? `${userProfile}\\flutter\\bin` : null,
    userProfile ? `${userProfile}\\dev\\flutter\\bin` : null,
    localAppData ? `${localAppData}\\Programs\\flutter\\bin` : null,
  ].filter(Boolean);

  for (const candidate of candidates) {
    if (!existsSync(candidate)) continue;
    process.env.PATH = `${candidate};${process.env.PATH ?? ''}`;
    if (hasCmd('flutter')) return true;
  }

  return false;
}

function printWindowsFlutterInstallHelp() {
  console.error(
    '\n✖ Flutter is not available on PATH.\n' +
    '  Install Flutter manually on Windows, restart terminal, then re-run setup.\n' +
    '  Docs: https://docs.flutter.dev/install/manual\n\n' +
    '  Quick PowerShell option:\n' +
    '  git clone https://github.com/flutter/flutter.git -b stable C:\\src\\flutter\n' +
    '  [Environment]::SetEnvironmentVariable("Path", $env:Path + ";C:\\src\\flutter\\bin", "User")\n\n' +
    '  Verify in a new terminal:\n' +
    '  flutter --version\n'
  );
}

function hasMacXcodebuild() {
  return (
    canRun('xcrun --find xcodebuild') &&
    canRun('xcodebuild -version')
  );
}

function printMacXcodeInstallHelp() {
  console.error(
    '\n✖ Full Xcode is required for macOS builds, but xcodebuild is unavailable.\n' +
    '  Install Xcode from the App Store or https://developer.apple.com/xcode/\n' +
    '  Then run:\n' +
    '  sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer\n' +
    '  sudo xcodebuild -runFirstLaunch\n' +
    '  sudo xcodebuild -license accept\n\n' +
    '  Verify:\n' +
    '  xcrun --find xcodebuild\n' +
    '  xcodebuild -version\n'
  );
}

// Win

function setupWindows() {
  header('DACX — Windows setup');

  // Flutter
  if (!resolveFlutterOnWindowsPath()) {
    printWindowsFlutterInstallHelp();
    process.exit(1);
  }
  console.log('✔ Flutter found');

  // Visual Studio Build Tools check
  console.log('\n⚠  Windows desktop builds require Visual Studio Build Tools with the');
  console.log('   "Desktop development with C++" workload. If not installed:');
  console.log('   winget install Microsoft.VisualStudio.2022.BuildTools');
  console.log('   Then add the C++ desktop workload via the VS Installer.');
  console.log('   For release installers (.exe + .msi), also install:');
  console.log('   winget install JRSoftware.InnoSetup');
  console.log('   WiX Toolset v3.14 (candle/light):');
  console.log('   https://github.com/wixtoolset/wix3/releases');

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

  // Full Xcode (required for flutter build macos / release:mac)
  if (!hasMacXcodebuild()) {
    const xcodeDeveloperDir = '/Applications/Xcode.app/Contents/Developer';
    if (existsSync(`${xcodeDeveloperDir}/usr/bin/xcodebuild`)) {
      console.log('\nXcode.app detected. Attempting to switch active developer directory...');
      run(`sudo xcode-select --switch "${xcodeDeveloperDir}"`, { allowFail: true });
      run('sudo xcodebuild -runFirstLaunch', { allowFail: true });
      run('sudo xcodebuild -license accept', { allowFail: true });
    }
  }
  if (!hasMacXcodebuild()) {
    printMacXcodeInstallHelp();
    process.exit(1);
  }
  console.log('✔ Xcode found');

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
    'libgtk-3-dev', 'libepoxy-dev', 'libmpv-dev', 'mpv',
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
