#!/usr/bin/env node

/**
 * Packages Flutter build output into distributable release artifacts.
 *
 * Usage:
 *   node scripts/package-release.js <platform>
 *
 * Platforms: win, mac, linux
 *
 * Windows produces:
 *   release/Dacx-Windows-x64.zip    (portable zip)
 *   release/Dacx-Windows-x64.msi    (WiX Toolset installer)
 *
 * macOS produces:
 *   release/Dacx-macOS.zip           (codesigned zip — from mac-codesign.sh or fallback)
 *   release/Dacx-macOS.dmg           (disk image via hdiutil)
 *
 * Linux produces:
 *   release/Dacx-Linux-x86_64.tar.gz (portable tarball)
 *   release/Dacx-Linux-amd64.deb     (Debian package via dpkg-deb)
 *   release/Dacx-Linux-x86_64.rpm    (RPM package via rpmbuild)
 *   release/Dacx-Linux-x86_64.AppImage (AppImage via appimagetool)
 */

import fs from "fs";
import path from "path";
import { execSync } from "child_process";
import { fileURLToPath } from "url";
import { loadLocalDotEnv } from "./xcode-env.js";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
loadLocalDotEnv();

const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf-8"));
const VERSION = pkg.version;
const AUDIO_EXTENSIONS = [
  "mp3",
  "flac",
  "wav",
  "ogg",
  "aac",
  "m4a",
  "wma",
  "opus",
  "ape",
  "alac",
];
const VIDEO_EXTENSIONS = [
  "mp4",
  "mkv",
  "avi",
  "webm",
  "mov",
  "wmv",
  "flv",
  "m4v",
];
const SUPPORTED_MEDIA_EXTENSIONS = [...AUDIO_EXTENSIONS, ...VIDEO_EXTENSIONS];
const MUSIC_FILE_ICON_SOURCE_PNG = path.join(root, "assets", "dacx_music_icon.png");
const WINDOWS_MUSIC_FILE_ICON_NAME = "dacx_music_icon.ico";
const MACOS_MUSIC_FILE_ICON_NAME = "dacx_music_icon.icns";

const platform = process.argv[2];
if (!platform) {
  console.error("Usage: node scripts/package-release.js <win|mac|linux>");
  process.exit(1);
}

const releaseDir = path.join(root, "release");
fs.mkdirSync(releaseDir, { recursive: true });

function run(cmd, opts = {}) {
  console.log(`  $ ${cmd}`);
  return execSync(cmd, { stdio: "inherit", cwd: root, ...opts });
}

function runSilent(cmd, opts = {}) {
  return execSync(cmd, { cwd: root, encoding: "utf-8", ...opts }).trim();
}

function hasCommand(cmd) {
  try {
    execSync(process.platform === "win32" ? `where ${cmd}` : `which ${cmd}`, {
      stdio: "ignore",
    });
    return true;
  } catch {
    return false;
  }
}

function removeIfExists(filePath) {
  if (fs.existsSync(filePath)) fs.unlinkSync(filePath);
}

function ensureWindowsAudioFileIcon(buildDir) {
  if (!fs.existsSync(MUSIC_FILE_ICON_SOURCE_PNG)) {
    console.warn(
      `  ⚠ Missing ${path.relative(root, MUSIC_FILE_ICON_SOURCE_PNG)}; ` +
      "audio files will use the app icon.",
    );
    return null;
  }

  if (!hasCommand("magick")) {
    console.warn(
      "  ⚠ ImageMagick (magick) not found; audio files will use the app icon.",
    );
    return null;
  }

  const outPath = path.join(buildDir, WINDOWS_MUSIC_FILE_ICON_NAME);
  run(
    `magick "${MUSIC_FILE_ICON_SOURCE_PNG}" ` +
    "-define icon:auto-resize=16,24,32,48,64,128,256 " +
    `"${outPath}"`,
  );
  console.log(`  ✓ ${WINDOWS_MUSIC_FILE_ICON_NAME}`);
  return WINDOWS_MUSIC_FILE_ICON_NAME;
}

function ensureMacAudioFileIconInBundle(appBundle) {
  if (!fs.existsSync(MUSIC_FILE_ICON_SOURCE_PNG)) {
    console.warn(
      `  ⚠ Missing ${path.relative(root, MUSIC_FILE_ICON_SOURCE_PNG)}; ` +
      "audio files will use the default document icon.",
    );
    return false;
  }

  const resourcesDir = path.join(appBundle, "Contents", "Resources");
  fs.mkdirSync(resourcesDir, { recursive: true });
  const outPath = path.join(resourcesDir, MACOS_MUSIC_FILE_ICON_NAME);

  if (hasCommand("magick")) {
    run(`magick "${MUSIC_FILE_ICON_SOURCE_PNG}" "${outPath}"`);
    console.log(`  ✓ ${MACOS_MUSIC_FILE_ICON_NAME}`);
    return true;
  }

  if (hasCommand("iconutil") && hasCommand("sips")) {
    const iconsetDir = path.join(root, "build", "mac-audio-icon.iconset");
    if (fs.existsSync(iconsetDir)) {
      fs.rmSync(iconsetDir, { recursive: true, force: true });
    }
    fs.mkdirSync(iconsetDir, { recursive: true });

    const iconsetOutputs = [
      ["icon_16x16.png", 16],
      ["icon_16x16@2x.png", 32],
      ["icon_32x32.png", 32],
      ["icon_32x32@2x.png", 64],
      ["icon_128x128.png", 128],
      ["icon_128x128@2x.png", 256],
      ["icon_256x256.png", 256],
      ["icon_256x256@2x.png", 512],
      ["icon_512x512.png", 512],
      ["icon_512x512@2x.png", 1024],
    ];

    for (const [fileName, size] of iconsetOutputs) {
      run(
        `sips -z ${size} ${size} "${MUSIC_FILE_ICON_SOURCE_PNG}" ` +
        `--out "${path.join(iconsetDir, fileName)}"`,
      );
    }

    run(`iconutil -c icns "${iconsetDir}" -o "${outPath}"`);
    fs.rmSync(iconsetDir, { recursive: true, force: true });
    console.log(`  ✓ ${MACOS_MUSIC_FILE_ICON_NAME}`);
    return true;
  }

  console.warn(
    "  ⚠ Could not generate macOS audio file icon " +
    "(needs ImageMagick or sips+iconutil).",
  );
  return false;
}

function escapePowerShellSingleQuoted(value) {
  return String(value).replace(/'/g, "''");
}

function copyDirSync(src, dest) {
  fs.mkdirSync(dest, { recursive: true });
  for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
    const srcPath = path.join(src, entry.name);
    const destPath = path.join(dest, entry.name);
    if (entry.isDirectory()) {
      copyDirSync(srcPath, destPath);
    } else {
      fs.copyFileSync(srcPath, destPath);
    }
  }
}

function resolveCommandFromPath(cmd) {
  try {
    if (process.platform === "win32") {
      const output = execSync(`where ${cmd}`, {
        cwd: root,
        encoding: "utf-8",
        stdio: ["ignore", "pipe", "ignore"],
      })
        .split(/\r?\n/)
        .map((line) => line.trim())
        .filter(Boolean);
      return output[0] || null;
    }
    const output = execSync(`which ${cmd}`, {
      cwd: root,
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    return output || null;
  } catch {
    return null;
  }
}

function firstExistingPath(paths) {
  for (const p of paths) {
    if (!p) continue;
    if (fs.existsSync(p)) return p;
  }
  return null;
}

function findWindowsDirByPrefix(baseDir, prefixRegex) {
  try {
    return fs
      .readdirSync(baseDir, { withFileTypes: true })
      .filter((entry) => entry.isDirectory() && prefixRegex.test(entry.name))
      .map((entry) => path.join(baseDir, entry.name))
      .sort((a, b) => b.localeCompare(a));
  } catch {
    return [];
  }
}

function resolveWixV4PlusTool() {
  if (process.env.WIX_BIN) {
    const wixExe = path.join(process.env.WIX_BIN, "wix.exe");
    if (fs.existsSync(wixExe)) return wixExe;
  }
  return resolveCommandFromPath("wix");
}

function getWixMajorVersion(wixPath) {
  try {
    const output = execSync(`"${wixPath}" --version`, {
      encoding: "utf-8",
      stdio: ["ignore", "pipe", "ignore"],
    }).trim();
    const match = output.match(/^(\d+)\./);
    return match ? parseInt(match[1], 10) : 4;
  } catch {
    return 4;
  }
}

function resolveWixV3ToolPaths() {
  const envBin = process.env.WIX_V3_BIN;
  if (envBin) {
    const envCandle = path.join(envBin, "candle.exe");
    const envLight = path.join(envBin, "light.exe");
    if (fs.existsSync(envCandle) && fs.existsSync(envLight)) {
      return { candlePath: envCandle, lightPath: envLight };
    }
  }

  const pathCandle = resolveCommandFromPath("candle");
  const pathLight = resolveCommandFromPath("light");
  if (pathCandle && pathLight) {
    return { candlePath: pathCandle, lightPath: pathLight };
  }

  const programFilesX86 = process.env["ProgramFiles(x86)"];
  const programFiles = process.env.ProgramFiles;

  const directBinCandidates = [
    programFilesX86 ? path.join(programFilesX86, "WiX Toolset v3.14", "bin") : null,
    programFilesX86 ? path.join(programFilesX86, "WiX Toolset v3.11", "bin") : null,
    programFiles ? path.join(programFiles, "WiX Toolset v3.14", "bin") : null,
    programFiles ? path.join(programFiles, "WiX Toolset v3.11", "bin") : null,
  ];

  const scannedBins = [
    ...findWindowsDirByPrefix(programFilesX86, /^WiX Toolset v3/i),
    ...findWindowsDirByPrefix(programFiles, /^WiX Toolset v3/i),
  ].map((dir) => path.join(dir, "bin"));

  const bins = [...directBinCandidates, ...scannedBins].filter(Boolean);
  for (const binDir of bins) {
    const candlePath = path.join(binDir, "candle.exe");
    const lightPath = path.join(binDir, "light.exe");
    if (fs.existsSync(candlePath) && fs.existsSync(lightPath)) {
      return { candlePath, lightPath };
    }
  }

  return null;
}

function toWindowsPath(inputPath) {
  return path.resolve(inputPath).replace(/\//g, "\\");
}

function normalizeWindowsThumbprint(value) {
  return String(value || "").replace(/[^0-9a-f]/gi, "").toUpperCase();
}

function windowsSigningThumbprint() {
  return normalizeWindowsThumbprint(
    process.env.WINDOWS_SIGNING_CERT_THUMBPRINT ||
      process.env.DACX_WINDOWS_SIGNER_THUMBPRINT ||
      "",
  );
}

function resolveSignToolPath() {
  const envPath = process.env.WINDOWS_SIGNTOOL_PATH || process.env.SIGNTOOL_PATH;
  if (envPath && fs.existsSync(envPath)) return envPath;

  const pathHit = resolveCommandFromPath("signtool");
  if (pathHit) return pathHit;

  const kitsRoot = process.env["ProgramFiles(x86)"]
    ? path.join(process.env["ProgramFiles(x86)"], "Windows Kits", "10", "bin")
    : null;
  if (!kitsRoot || !fs.existsSync(kitsRoot)) return null;

  const candidates = fs
    .readdirSync(kitsRoot, { withFileTypes: true })
    .filter((entry) => entry.isDirectory())
    .map((entry) => path.join(kitsRoot, entry.name, "x64", "signtool.exe"))
    .filter((candidate) => fs.existsSync(candidate))
    .sort((a, b) => b.localeCompare(a));
  return candidates[0] || null;
}

function verifyWindowsAuthenticode(filePath, expectedThumbprint) {
  const psPath = escapePowerShellSingleQuoted(toWindowsPath(filePath));
  const ps = [
    `$sig = Get-AuthenticodeSignature -LiteralPath '${psPath}'`,
    `$thumb = if ($sig.SignerCertificate) { $sig.SignerCertificate.Thumbprint } else { '' }`,
    `if ($sig.Status -ne 'Valid') { throw ('Authenticode status ' + $sig.Status + ': ' + $sig.StatusMessage) }`,
    `$normalized = ($thumb -replace '[^0-9A-Fa-f]', '').ToUpperInvariant()`,
    `if ($normalized -ne '${expectedThumbprint}') { throw ('Signer thumbprint ' + $normalized + ' does not match expected ${expectedThumbprint}') }`,
  ].join("; ");
  run(`powershell -NoProfile -ExecutionPolicy Bypass -Command "${ps}"`);
}

function signWindowsArtifact(filePath) {
  const thumbprint = windowsSigningThumbprint();
  if (!thumbprint) {
    console.warn(
      "  ⚠ WINDOWS_SIGNING_CERT_THUMBPRINT not set; Windows installer will not be Authenticode-signed.",
    );
    return;
  }

  const signtoolPath = resolveSignToolPath();
  if (!signtoolPath) {
    console.error("signtool.exe was not found, but WINDOWS_SIGNING_CERT_THUMBPRINT is set.");
    console.error("Set WINDOWS_SIGNTOOL_PATH to signtool.exe or install the Windows SDK.");
    process.exit(1);
  }

  const timestampUrl =
    process.env.WINDOWS_TIMESTAMP_URL || "http://timestamp.digicert.com";
  run(
    `"${signtoolPath}" sign /fd SHA256 /tr "${timestampUrl}" /td SHA256 ` +
      `/sha ${thumbprint} "${toWindowsPath(filePath)}"`,
  );
  verifyWindowsAuthenticode(filePath, thumbprint);
}

function escapeXmlAttr(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function renderWixV4FileAssociationComponent(audioIconFileName) {
  const audioIconValue = audioIconFileName
    ? `[INSTALLFOLDER]${audioIconFileName},0`
    : "[INSTALLFOLDER]dacx.exe,0";
  const lines = [
    '      <Component Id="CMP_FILE_ASSOC" Guid="*">',
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Dacx.Audio">',
    '          <RegistryValue Type="string" Value="Dacx Audio File" KeyPath="yes" />',
    "        </RegistryKey>",
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Dacx.Audio\\\\DefaultIcon">',
    `          <RegistryValue Type="string" Value="${audioIconValue}" />`,
    "        </RegistryKey>",
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Dacx.Audio\\\\shell\\\\open\\\\command">',
    '          <RegistryValue Type="string" Value="&quot;[INSTALLFOLDER]dacx.exe&quot; &quot;%1&quot;" />',
    "        </RegistryKey>",
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Dacx.Video">',
    '          <RegistryValue Type="string" Value="Dacx Video File" />',
    "        </RegistryKey>",
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Dacx.Video\\\\DefaultIcon">',
    '          <RegistryValue Type="string" Value="[INSTALLFOLDER]dacx.exe,0" />',
    "        </RegistryKey>",
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Dacx.Video\\\\shell\\\\open\\\\command">',
    '          <RegistryValue Type="string" Value="&quot;[INSTALLFOLDER]dacx.exe&quot; &quot;%1&quot;" />',
    "        </RegistryKey>",
    '        <RegistryKey Root="HKLM" Key="Software\\\\Classes\\\\Applications\\\\dacx.exe\\\\shell\\\\open\\\\command">',
      '          <RegistryValue Type="string" Value="&quot;[INSTALLFOLDER]dacx.exe&quot; &quot;%1&quot;" />',
    "        </RegistryKey>",
  ];

  for (const ext of SUPPORTED_MEDIA_EXTENSIONS) {
    lines.push(
      `        <RegistryKey Root="HKLM" Key="Software\\Classes\\Applications\\dacx.exe\\SupportedTypes">`,
    );
    lines.push(
      `          <RegistryValue Name=".${ext}" Type="string" Value="" />`,
    );
    lines.push("        </RegistryKey>");
  }

  for (const ext of AUDIO_EXTENSIONS) {
    lines.push(
      `        <RegistryKey Root="HKLM" Key="Software\\Classes\\.${ext}\\OpenWithProgids">`,
    );
    lines.push(
      '          <RegistryValue Name="Dacx.Audio" Type="string" Value="" />',
    );
    lines.push("        </RegistryKey>");
  }

  for (const ext of VIDEO_EXTENSIONS) {
    lines.push(
      `        <RegistryKey Root="HKLM" Key="Software\\Classes\\.${ext}\\OpenWithProgids">`,
    );
    lines.push(
      '          <RegistryValue Name="Dacx.Video" Type="string" Value="" />',
    );
    lines.push("        </RegistryKey>");
  }

  lines.push("      </Component>");
  return lines.join("\n");
}

function renderWixV3FileAssociationComponent(audioIconFileName) {
  const audioIconValue = audioIconFileName
    ? `[INSTALLFOLDER]${audioIconFileName},0`
    : "[INSTALLFOLDER]dacx.exe,0";
  const lines = [
    '          <Component Id="CMP_FILE_ASSOC" Guid="*" Win64="yes">',
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Dacx.Audio">',
    '              <RegistryValue Type="string" Value="Dacx Audio File" KeyPath="yes" />',
    "            </RegistryKey>",
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Dacx.Audio\\DefaultIcon">',
    `              <RegistryValue Type="string" Value="${audioIconValue}" />`,
    "            </RegistryKey>",
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Dacx.Audio\\shell\\open\\command">',
    '              <RegistryValue Type="string" Value="&quot;[INSTALLFOLDER]dacx.exe&quot; &quot;%1&quot;" />',
    "            </RegistryKey>",
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Dacx.Video">',
    '              <RegistryValue Type="string" Value="Dacx Video File" />',
    "            </RegistryKey>",
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Dacx.Video\\DefaultIcon">',
    '              <RegistryValue Type="string" Value="[INSTALLFOLDER]dacx.exe,0" />',
    "            </RegistryKey>",
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Dacx.Video\\shell\\open\\command">',
    '              <RegistryValue Type="string" Value="&quot;[INSTALLFOLDER]dacx.exe&quot; &quot;%1&quot;" />',
    "            </RegistryKey>",
    '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Applications\\dacx.exe\\shell\\open\\command">',
      '              <RegistryValue Type="string" Value="&quot;[INSTALLFOLDER]dacx.exe&quot; &quot;%1&quot;" />',
    "            </RegistryKey>",
  ];

  for (const ext of SUPPORTED_MEDIA_EXTENSIONS) {
    lines.push(
      '            <RegistryKey Root="HKLM" Key="Software\\Classes\\Applications\\dacx.exe\\SupportedTypes">',
    );
    lines.push(
      `              <RegistryValue Name=".${ext}" Type="string" Value="" />`,
    );
    lines.push("            </RegistryKey>");
  }

  for (const ext of AUDIO_EXTENSIONS) {
    lines.push(
      `            <RegistryKey Root="HKLM" Key="Software\\Classes\\.${ext}\\OpenWithProgids">`,
    );
    lines.push(
      '              <RegistryValue Name="Dacx.Audio" Type="string" Value="" />',
    );
    lines.push("            </RegistryKey>");
  }

  for (const ext of VIDEO_EXTENSIONS) {
    lines.push(
      `            <RegistryKey Root="HKLM" Key="Software\\Classes\\.${ext}\\OpenWithProgids">`,
    );
    lines.push(
      '              <RegistryValue Name="Dacx.Video" Type="string" Value="" />',
    );
    lines.push("            </RegistryKey>");
  }

  lines.push("          </Component>");
  return lines.join("\n");
}

function renderWixStartMenuShortcutComponent({ indent, includeIcon }) {
  const iconAttr = includeIcon ? ' Icon="AppIcon.ico"' : "";
  return [
    `${indent}<Component Id="CMP_START_MENU_SHORTCUT" Guid="*">`,
    `${indent}  <Shortcut Id="StartMenuShortcut" Name="Dacx" Description="Dacx media player" Target="[INSTALLFOLDER]dacx.exe" WorkingDirectory="INSTALLFOLDER"${iconAttr} />`,
    `${indent}  <RegistryValue Root="HKLM" Key="Software\\run.rosie\\Dacx" Name="StartMenuShortcut" Type="integer" Value="1" KeyPath="yes" />`,
    `${indent}</Component>`,
  ].join("\n");
}

function listFilesRecursive(baseDir) {
  const out = [];

  function walk(currentDir) {
    for (const entry of fs.readdirSync(currentDir, { withFileTypes: true })) {
      const full = path.join(currentDir, entry.name);
      if (entry.isDirectory()) {
        walk(full);
      } else if (entry.isFile()) {
        out.push(full);
      }
    }
  }

  walk(baseDir);
  return out;
}

function toMsiVersion(version) {
  const match = String(version).match(
    /^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z.-]+))?$/,
  );
  if (!match) {
    throw new Error(
      `Cannot convert version "${version}" to MSI version. Expected semver like 1.2.3 or 1.2.3-beta.4`,
    );
  }
  const major = Number(match[1]);
  const minor = Number(match[2]);
  const patch = Number(match[3]);
  const prerelease = match[4];

  if (patch > 654) {
    throw new Error(
      `Patch ${patch} exceeds 654 — MSI build field would overflow (max 65535).`,
    );
  }

  if (!prerelease) {
    return `${major}.${minor}.${patch * 100 + 99}`;
  }

  const tagMatch = prerelease.match(/^beta\.(\d+)$/);
  if (!tagMatch) {
    throw new Error(
      `Cannot encode prerelease "${prerelease}" — only beta.N is supported (e.g. beta.5).`,
    );
  }
  const n = Number(tagMatch[1]);
  if (n < 1 || n > 98) {
    throw new Error(
      `Beta counter ${n} out of range (1..98). Bump patch and reset.`,
    );
  }
  return `${major}.${minor}.${patch * 100 + n}`;
}

// ── Windows ────────────────────────────────────────────────────

function packageWindows() {
  const buildDir = path.join(root, "build", "windows", "x64", "runner", "Release");
  if (!fs.existsSync(buildDir)) {
    console.error(`Build directory not found: ${buildDir}`);
    console.error("Run 'npm run build:win' first.");
    process.exit(1);
  }

  const audioIconFileName = ensureWindowsAudioFileIcon(buildDir);

  // Defensive sweep: if a previous run was hard-killed between writing the
  // portable marker and its `finally` cleanup, the leftover file would be
  // harvested by WiX into the MSI. Remove it before MSI build runs.
  const portableMarkerPath = path.join(buildDir, "portable.txt");
  removeIfExists(portableMarkerPath);

  // 1. MSI installer (WiX Toolset) — must run before the portable marker is
  // dropped, so the MSI does not register the marker file and try to gate
  // itself out of the self-updater after installation.
  buildWindowsMsiInstaller(buildDir, audioIconFileName);

  // 2. Portable zip — drop the `portable.txt` marker so the running app can
  // detect it is the portable build and skip the MSI-based self-updater.
  // (Path declared above so the pre-MSI sweep can reuse it.)
  fs.writeFileSync(
    portableMarkerPath,
    "This file marks the Dacx portable build. Do not delete — its presence\r\n" +
      "tells the app to skip the MSI-based self-updater and direct the user to\r\n" +
      "the release page instead.\r\n",
  );

  const zipName = "Dacx-Windows-x64.zip";
  const zipPath = path.join(releaseDir, zipName);
  removeIfExists(zipPath);
  try {
    if (hasCommand("7z")) {
      run(`7z a -tzip -mx=9 "${zipPath}" *`, { cwd: buildDir });
    } else {
      const psSourceDir = escapePowerShellSingleQuoted(buildDir);
      const psZipPath = escapePowerShellSingleQuoted(zipPath);
      run(
        `powershell -NoProfile -Command "` +
          `$src='${psSourceDir}'; ` +
          `$dst='${psZipPath}'; ` +
          `if (Test-Path $dst) { Remove-Item -Force $dst }; ` +
          `Add-Type -AssemblyName System.IO.Compression.FileSystem; ` +
          `[System.IO.Compression.ZipFile]::CreateFromDirectory(` +
          `$src, $dst, [System.IO.Compression.CompressionLevel]::Optimal, $false)` +
          `"`,
      );
    }
  } finally {
    removeIfExists(portableMarkerPath);
  }
  console.log(`  ✓ ${zipName}`);
}

function buildWindowsMsiInstaller(buildDir, audioIconFileName) {
  // Prefer WiX v4+ (wix build), fall back to WiX v3 (candle + light).
  const wixV4Path = resolveWixV4PlusTool();
  if (wixV4Path) {
    buildWindowsMsiInstallerV4(buildDir, wixV4Path, audioIconFileName);
    return;
  }

  const wixV3Paths = resolveWixV3ToolPaths();
  if (wixV3Paths) {
    buildWindowsMsiInstallerV3(buildDir, wixV3Paths, audioIconFileName);
    return;
  }

  console.error("WiX tools were not found.");
  console.error("Install WiX v7 (.NET global tool):");
  console.error("  dotnet tool install -g wix --version 7.0.0");
  console.error("  wix eula accept wix7");
  console.error("Or set WIX_BIN to the directory containing wix.exe.");
  console.error("Alternatively, install WiX v3.14 (candle/light):");
  console.error("  https://github.com/wixtoolset/wix3/releases");
  console.error("Or set WIX_V3_BIN to the directory containing candle.exe and light.exe.");
  process.exit(1);
}

function buildWindowsMsiInstallerV4(buildDir, wixPath, audioIconFileName) {
  const outName = "Dacx-Windows-x64.msi";
  const outPath = path.join(releaseDir, outName);
  removeIfExists(outPath);

  const installerDir = path.join(root, "build", "win-installer");
  fs.mkdirSync(installerDir, { recursive: true });
  const wxsPath = path.join(installerDir, "dacx-installer.wxs");

  writeWindowsWixV4Source(buildDir, wxsPath, audioIconFileName);

  const majorVersion = getWixMajorVersion(wixPath);
  const acceptEulaFlag = majorVersion >= 7 ? " -acceptEula wix7" : "";
  run(
    `"${wixPath}" build${acceptEulaFlag} -arch x64 -pdbType none` +
      ` -out "${toWindowsPath(outPath)}" "${toWindowsPath(wxsPath)}"`,
  );

  if (!fs.existsSync(outPath)) {
    console.error(`WiX did not produce expected output: ${outPath}`);
    process.exit(1);
  }

  // Clean up stale WiX byproducts (e.g. .wixpdb, .msix) from the output directory
  const outDir = path.dirname(outPath);
  const outBase = path.basename(outPath, path.extname(outPath));
  for (const staleExt of [".wixpdb", ".msix"]) {
    const stale = path.join(outDir, outBase + staleExt);
    removeIfExists(stale);
  }

  signWindowsArtifact(outPath);
  console.log(`  ✓ ${outName}`);
}

function buildWindowsMsiInstallerV3(buildDir, wixV3Paths, audioIconFileName) {
  const outName = "Dacx-Windows-x64.msi";
  const outPath = path.join(releaseDir, outName);
  removeIfExists(outPath);

  const installerDir = path.join(root, "build", "win-installer");
  fs.mkdirSync(installerDir, { recursive: true });
  const wxsPath = path.join(installerDir, "dacx-installer.wxs");
  const wixobjPath = path.join(installerDir, "dacx-installer.wixobj");

  writeWindowsWixSource(buildDir, wxsPath, audioIconFileName);

  run(`"${wixV3Paths.candlePath}" -nologo -arch x64 -out "${wixobjPath}" "${wxsPath}"`);
  run(`"${wixV3Paths.lightPath}" -nologo -spdb -out "${outPath}" "${wixobjPath}"`);

  if (!fs.existsSync(outPath)) {
    console.error(`WiX did not produce expected output: ${outPath}`);
    process.exit(1);
  }
  signWindowsArtifact(outPath);
  console.log(`  ✓ ${outName}`);
}

function writeWindowsWixV4Source(buildDir, wxsPath, audioIconFileName) {
  const files = listFilesRecursive(buildDir)
    .map((absolutePath) => {
      const rel = path.relative(buildDir, absolutePath).replace(/\\/g, "/");
      const relDir = path.posix.dirname(rel) === "." ? "" : path.posix.dirname(rel);
      return { absolutePath, rel, relDir };
    })
    .sort((a, b) => a.rel.localeCompare(b.rel));

  const relDirs = new Set([""]);
  for (const file of files) {
    const parts = file.relDir ? file.relDir.split("/") : [];
    let acc = "";
    for (const part of parts) {
      acc = acc ? `${acc}/${part}` : part;
      relDirs.add(acc);
    }
  }

  const dirIdByRel = new Map([["", "INSTALLFOLDER"]]);
  let dirCounter = 1;
  for (const relDir of Array.from(relDirs).sort((a, b) => a.localeCompare(b))) {
    if (!relDir) continue;
    dirIdByRel.set(relDir, `DIR_${String(dirCounter).padStart(4, "0")}`);
    dirCounter += 1;
  }

  const rootNode = {
    name: "",
    relDir: "",
    id: "INSTALLFOLDER",
    children: new Map(),
  };
  for (const relDir of Array.from(relDirs).sort((a, b) => a.localeCompare(b))) {
    if (!relDir) continue;
    const parts = relDir.split("/");
    let node = rootNode;
    let acc = "";
    for (const part of parts) {
      acc = acc ? `${acc}/${part}` : part;
      if (!node.children.has(part)) {
        node.children.set(part, {
          name: part,
          relDir: acc,
          id: dirIdByRel.get(acc),
          children: new Map(),
        });
      }
      node = node.children.get(part);
    }
  }

  const componentsByDir = new Map();
  const fileComponentIds = [];
  files.forEach((file, index) => {
    const idx = String(index + 1).padStart(4, "0");
    const componentId = `CMP_FILE_${idx}`;
    const fileId = `FIL_${idx}`;
    fileComponentIds.push(componentId);

    // WiX v4+: no Win64="yes" — platform is inferred from -arch x64 at build time.
    const componentLines = [
      `<Component Id="${componentId}" Guid="*">`,
      `  <File Id="${fileId}" Source="${escapeXmlAttr(toWindowsPath(file.absolutePath))}" KeyPath="yes" />`,
      `</Component>`,
    ];

    const list = componentsByDir.get(file.relDir) || [];
    list.push(componentLines);
    componentsByDir.set(file.relDir, list);
  });

  function renderDirectoryContents(node, indent) {
    const lines = [];

    const components = componentsByDir.get(node.relDir) || [];
    for (const block of components) {
      for (const line of block) {
        lines.push(`${indent}${line}`);
      }
    }

    const children = Array.from(node.children.values()).sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    for (const child of children) {
      lines.push(
        `${indent}<Directory Id="${child.id}" Name="${escapeXmlAttr(child.name)}">`,
      );
      lines.push(...renderDirectoryContents(child, `${indent}  `));
      lines.push(`${indent}</Directory>`);
    }

    return lines;
  }

  const appIconPath = path.join(root, "windows", "runner", "resources", "app_icon.ico");
  const hasAppIcon = fs.existsSync(appIconPath);
  const msiVersion = toMsiVersion(VERSION);
  const iconBlock = hasAppIcon
    ? [
        `    <Icon Id="AppIcon.ico" SourceFile="${escapeXmlAttr(toWindowsPath(appIconPath))}" />`,
        `    <Property Id="ARPPRODUCTICON" Value="AppIcon.ico" />`,
      ].join("\n")
    : "";

  const componentRefs = [
    ...fileComponentIds.map((id) => `      <ComponentRef Id="${id}" />`),
    '      <ComponentRef Id="CMP_FILE_ASSOC" />',
    '      <ComponentRef Id="CMP_START_MENU_SHORTCUT" />',
  ].join("\n");

  // WiX v4+ schema: <Package> replaces the v3 <Product>+<Package> pair.
  // Scope="perMachine" replaces InstallScope="perMachine"; Platform moved to CLI (-arch x64).
  // StandardDirectory replaces manual TARGETDIR/ProgramFiles64Folder definitions.
  const wixSource = `<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package
    Name="Dacx"
    Language="1033"
    Version="${msiVersion}"
    Manufacturer="run.rosie"
    UpgradeCode="{D8D4A9F8-084A-4A7C-9713-3BC4F78E2A93}"
    Scope="perMachine">
    <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />
    <MediaTemplate EmbedCab="yes" />
${iconBlock}
    <Feature Id="ProductFeature" Title="Dacx" Level="1">
${componentRefs}
    </Feature>
  </Package>

  <Fragment>
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="Dacx">
${renderWixV4FileAssociationComponent(audioIconFileName)}
${renderDirectoryContents(rootNode, "        ").join("\n")}
      </Directory>
    </StandardDirectory>
  </Fragment>

  <Fragment>
    <StandardDirectory Id="ProgramMenuFolder">
${renderWixStartMenuShortcutComponent({ indent: "      ", includeIcon: hasAppIcon })}
    </StandardDirectory>
  </Fragment>
</Wix>
`;

  fs.writeFileSync(wxsPath, wixSource);
}

function writeWindowsWixSource(buildDir, wxsPath, audioIconFileName) {
  const files = listFilesRecursive(buildDir)
    .map((absolutePath) => {
      const rel = path.relative(buildDir, absolutePath).replace(/\\/g, "/");
      const relDir = path.posix.dirname(rel) === "." ? "" : path.posix.dirname(rel);
      return { absolutePath, rel, relDir };
    })
    .sort((a, b) => a.rel.localeCompare(b.rel));

  const relDirs = new Set([""]);
  for (const file of files) {
    const parts = file.relDir ? file.relDir.split("/") : [];
    let acc = "";
    for (const part of parts) {
      acc = acc ? `${acc}/${part}` : part;
      relDirs.add(acc);
    }
  }

  const dirIdByRel = new Map([["", "INSTALLFOLDER"]]);
  let dirCounter = 1;
  for (const relDir of Array.from(relDirs).sort((a, b) => a.localeCompare(b))) {
    if (!relDir) continue;
    dirIdByRel.set(relDir, `DIR_${String(dirCounter).padStart(4, "0")}`);
    dirCounter += 1;
  }

  const rootNode = {
    name: "",
    relDir: "",
    id: "INSTALLFOLDER",
    children: new Map(),
  };
  for (const relDir of Array.from(relDirs).sort((a, b) => a.localeCompare(b))) {
    if (!relDir) continue;
    const parts = relDir.split("/");
    let node = rootNode;
    let acc = "";
    for (const part of parts) {
      acc = acc ? `${acc}/${part}` : part;
      if (!node.children.has(part)) {
        node.children.set(part, {
          name: part,
          relDir: acc,
          id: dirIdByRel.get(acc),
          children: new Map(),
        });
      }
      node = node.children.get(part);
    }
  }

  const componentsByDir = new Map();
  const fileComponentIds = [];
  files.forEach((file, index) => {
    const idx = String(index + 1).padStart(4, "0");
    const componentId = `CMP_FILE_${idx}`;
    const fileId = `FIL_${idx}`;
    fileComponentIds.push(componentId);

    const componentLines = [
      `<Component Id="${componentId}" Guid="*" Win64="yes">`,
      `  <File Id="${fileId}" Source="${escapeXmlAttr(toWindowsPath(file.absolutePath))}" KeyPath="yes" />`,
      `</Component>`,
    ];

    const list = componentsByDir.get(file.relDir) || [];
    list.push(componentLines);
    componentsByDir.set(file.relDir, list);
  });

  function renderDirectoryContents(node, indent) {
    const lines = [];

    const components = componentsByDir.get(node.relDir) || [];
    for (const block of components) {
      for (const line of block) {
        lines.push(`${indent}${line}`);
      }
    }

    const children = Array.from(node.children.values()).sort((a, b) =>
      a.name.localeCompare(b.name),
    );
    for (const child of children) {
      lines.push(
        `${indent}<Directory Id="${child.id}" Name="${escapeXmlAttr(child.name)}">`,
      );
      lines.push(...renderDirectoryContents(child, `${indent}  `));
      lines.push(`${indent}</Directory>`);
    }

    return lines;
  }

  const appIconPath = path.join(root, "windows", "runner", "resources", "app_icon.ico");
  const hasAppIcon = fs.existsSync(appIconPath);
  const msiVersion = toMsiVersion(VERSION);
  const iconBlock = hasAppIcon
    ? [
        `    <Icon Id="AppIcon.ico" SourceFile="${escapeXmlAttr(toWindowsPath(appIconPath))}" />`,
        `    <Property Id="ARPPRODUCTICON" Value="AppIcon.ico" />`,
      ].join("\n")
    : "";

  const componentRefs = [
    ...fileComponentIds.map((id) => `      <ComponentRef Id="${id}" />`),
    '      <ComponentRef Id="CMP_FILE_ASSOC" />',
    '      <ComponentRef Id="CMP_START_MENU_SHORTCUT" />',
  ].join("\n");

  const wixSource = `<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product
    Id="*"
    Name="Dacx"
    Language="1033"
    Version="${msiVersion}"
    Manufacturer="run.rosie"
    UpgradeCode="{D8D4A9F8-084A-4A7C-9713-3BC4F78E2A93}">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" Platform="x64" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />
    <MediaTemplate EmbedCab="yes" />
${iconBlock}
    <Feature Id="ProductFeature" Title="Dacx" Level="1">
${componentRefs}
    </Feature>
  </Product>

  <Fragment>
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="Dacx">
${renderWixV3FileAssociationComponent(audioIconFileName)}
${renderDirectoryContents(rootNode, "          ").join("\n")}
        </Directory>
      </Directory>
      <Directory Id="ProgramMenuFolder">
${renderWixStartMenuShortcutComponent({ indent: "        ", includeIcon: hasAppIcon })}
      </Directory>
    </Directory>
  </Fragment>
</Wix>
`;

  fs.writeFileSync(wxsPath, wixSource);
}

// ── macOS ──────────────────────────────────────────────────────

function packageMac() {
  const appBundle = path.join(
    root, "build", "macos", "Build", "Products", "Release", "Dacx.app",
  );
  if (!fs.existsSync(appBundle)) {
    console.error(`App bundle not found: ${appBundle}`);
    console.error("Run 'npm run build:mac' first.");
    process.exit(1);
  }

  ensureMacAudioFileIconInBundle(appBundle);

  // 1. Zip (may already exist from mac-codesign.sh)
  const codesignZipPattern = /^dacx-(?:.*-)?macos\.zip$/i;
  const existing = fs.readdirSync(releaseDir).filter((f) => codesignZipPattern.test(f));
  if (existing.length > 0) {
    console.log(`  ✓ ${existing[0]} (from mac-codesign.sh)`);
  } else {
    const zipName = "Dacx-macOS.zip";
    const zipPath = path.join(releaseDir, zipName);
    removeIfExists(zipPath);
    run(`ditto -c -k --keepParent "${appBundle}" "${zipPath}"`);
    console.log(`  ✓ ${zipName} (unsigned)`);
  }

  // 2. DMG
  const dmgName = "Dacx-macOS.dmg";
  const dmgPath = path.join(releaseDir, dmgName);
  removeIfExists(dmgPath);

  // Create a temporary DMG staging directory
  const dmgStage = path.join(root, "build", "dmg-stage");
  if (fs.existsSync(dmgStage)) {
    run(`rm -rf "${dmgStage}"`);
  }
  fs.mkdirSync(dmgStage, { recursive: true });

  // Copy app bundle and create Applications symlink
  run(`cp -R "${appBundle}" "${dmgStage}/Dacx.app"`);
  run(`ln -s /Applications "${dmgStage}/Applications"`);

  // Create DMG
  run(
    `hdiutil create -volname "Dacx" -srcfolder "${dmgStage}" ` +
    `-ov -format UDZO "${dmgPath}"`,
  );

  // Clean up staging
  run(`rm -rf "${dmgStage}"`);

  // If we have a signing identity, sign the DMG too
  if (process.env.APPLE_SIGNING_IDENTITY) {
    run(
      `codesign --force --sign "${process.env.APPLE_SIGNING_IDENTITY}" "${dmgPath}"`,
    );
    console.log(`  ✓ ${dmgName} (signed)`);
  } else {
    console.log(`  ✓ ${dmgName}`);
  }
}

// ── Linux ──────────────────────────────────────────────────────

function packageLinux() {
  const buildDir = path.join(root, "build", "linux", "x64", "release", "bundle");
  if (!fs.existsSync(buildDir)) {
    console.error(`Build directory not found: ${buildDir}`);
    console.error("Run 'npm run build:linux' first.");
    process.exit(1);
  }

  const packagingDir = path.join(root, "linux", "packaging");
  const desktopFile = path.join(packagingDir, "dacx.desktop");
  // Use the first PNG icon found in assets, or fall back to a placeholder path
  const iconFile = findIcon();

  // 1. Portable tarball
  const tarName = "Dacx-Linux-x86_64.tar.gz";
  const tarPath = path.join(releaseDir, tarName);
  removeIfExists(tarPath);
  run(`tar -czf "${tarPath}" -C "${path.dirname(buildDir)}" "${path.basename(buildDir)}"`);
  console.log(`  ✓ ${tarName}`);

  // 2. .deb
  buildDeb(buildDir, desktopFile, iconFile);

  // 3. .rpm
  buildRpm(buildDir, desktopFile, iconFile);

  // 4. .AppImage
  buildAppImage(buildDir, desktopFile, iconFile);
}

function findIcon() {
  // Check common icon locations
  const candidates = [
    path.join(root, "assets", "icon", "icon.png"),
    path.join(root, "assets", "icon.png"),
    path.join(root, "linux", "packaging", "icon.png"),
    // Flutter's default icon location on Linux
    path.join(root, "linux", "flutter", "generated_plugin_registrant.h"), // just to find the linux dir
  ];

  for (const c of candidates) {
    if (fs.existsSync(c) && c.endsWith(".png")) return c;
  }

  // If no icon found, warn and return null
  console.warn("  ⚠ No icon.png found — .deb/.rpm/.AppImage will lack an icon.");
  console.warn("    Place a 256x256+ PNG at assets/icon/icon.png");
  return null;
}

function buildDeb(buildDir, desktopFile, iconFile) {
  if (!hasCommand("dpkg-deb")) {
    console.warn("  ⚠ dpkg-deb not found — skipping .deb");
    return;
  }

  const debRoot = path.join(root, "build", "deb-stage");
  if (fs.existsSync(debRoot)) fs.rmSync(debRoot, { recursive: true });

  // Create directory structure
  const optDir = path.join(debRoot, "opt", "dacx");
  const binDir = path.join(debRoot, "usr", "bin");
  const appsDir = path.join(debRoot, "usr", "share", "applications");
  const iconDir = path.join(debRoot, "usr", "share", "icons", "hicolor", "256x256", "apps");
  const debianDir = path.join(debRoot, "DEBIAN");

  fs.mkdirSync(optDir, { recursive: true });
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(appsDir, { recursive: true });
  fs.mkdirSync(iconDir, { recursive: true });
  fs.mkdirSync(debianDir, { recursive: true });

  // Copy bundle to /opt/dacx
  copyDirSync(buildDir, optDir);

  // Create /usr/bin/dacx symlink script
  fs.writeFileSync(
    path.join(binDir, "dacx"),
    '#!/bin/sh\nexec /opt/dacx/dacx "$@"\n',
    { mode: 0o755 },
  );

  // Copy desktop file
  if (fs.existsSync(desktopFile)) {
    // Update Exec path for installed location
    let desktop = fs.readFileSync(desktopFile, "utf-8");
    desktop = desktop.replace(/^Exec=.*$/m, "Exec=/opt/dacx/dacx %U");
    fs.writeFileSync(path.join(appsDir, "dacx.desktop"), desktop);
  }

  // Copy icon
  if (iconFile) {
    fs.copyFileSync(iconFile, path.join(iconDir, "dacx.png"));
  }

  // Generate control file from template
  const controlTemplate = path.join(root, "linux", "packaging", "control.template");
  if (fs.existsSync(controlTemplate)) {
    let control = fs.readFileSync(controlTemplate, "utf-8");
    control = control.replace(/\{\{VERSION\}\}/g, VERSION);
    // Remove the shebang line if present (it's a template marker, not a real script)
    control = control.replace(/^#!.*\n/, "");
    // Calculate installed size in KB
    const sizeKB = Math.ceil(getDirSizeBytes(optDir) / 1024);
    control += `Installed-Size: ${sizeKB}\n`;
    fs.writeFileSync(path.join(debianDir, "control"), control);
  }

  const debName = "Dacx-Linux-amd64.deb";
  const debPath = path.join(releaseDir, debName);
  removeIfExists(debPath);
  run(`dpkg-deb --build --root-owner-group "${debRoot}" "${debPath}"`);

  // Cleanup
  fs.rmSync(debRoot, { recursive: true });
  console.log(`  ✓ ${debName}`);
}

function semverToRpmVersionRelease(semver) {
  // Strip semver build metadata (after '+') — RPM disallows '+' in Version.
  const stripped = semver.split("+")[0];
  const dashIdx = stripped.indexOf("-");
  if (dashIdx < 0) {
    return { version: stripped, release: "1" };
  }
  const ver = stripped.substring(0, dashIdx);
  const pre = stripped.substring(dashIdx + 1).replace(/[^A-Za-z0-9.]/g, ".");
  return { version: ver, release: `0.${pre}` };
}

function buildRpm(buildDir, desktopFile, iconFile) {
  if (!hasCommand("rpmbuild")) {
    console.warn("  ⚠ rpmbuild not found — skipping .rpm");
    return;
  }

  const { version: rpmVersion, release: rpmRelease } =
    semverToRpmVersionRelease(VERSION);

  const rpmRoot = path.join(root, "build", "rpm-stage");
  if (fs.existsSync(rpmRoot)) fs.rmSync(rpmRoot, { recursive: true });

  // rpmbuild directory structure
  const buildroot = path.join(
    rpmRoot,
    "BUILDROOT",
    `dacx-${rpmVersion}-${rpmRelease}.x86_64`,
  );
  const specsDir = path.join(rpmRoot, "SPECS");
  const rpmsDir = path.join(rpmRoot, "RPMS");

  const optDir = path.join(buildroot, "opt", "dacx");
  const binDir = path.join(buildroot, "usr", "bin");
  const appsDir = path.join(buildroot, "usr", "share", "applications");
  const iconDir = path.join(buildroot, "usr", "share", "icons", "hicolor", "256x256", "apps");

  fs.mkdirSync(optDir, { recursive: true });
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(appsDir, { recursive: true });
  fs.mkdirSync(iconDir, { recursive: true });
  fs.mkdirSync(specsDir, { recursive: true });
  fs.mkdirSync(rpmsDir, { recursive: true });

  // Copy bundle
  copyDirSync(buildDir, optDir);

  // Launcher script
  fs.writeFileSync(
    path.join(binDir, "dacx"),
    '#!/bin/sh\nexec /opt/dacx/dacx "$@"\n',
    { mode: 0o755 },
  );

  // Desktop file
  if (fs.existsSync(desktopFile)) {
    let desktop = fs.readFileSync(desktopFile, "utf-8");
    desktop = desktop.replace(/^Exec=.*$/m, "Exec=/opt/dacx/dacx %U");
    fs.writeFileSync(path.join(appsDir, "dacx.desktop"), desktop);
  }

  // Icon
  if (iconFile) {
    fs.copyFileSync(iconFile, path.join(iconDir, "dacx.png"));
  }

  // Generate spec from template
  const specTemplate = path.join(root, "linux", "packaging", "dacx.spec.template");
  if (fs.existsSync(specTemplate)) {
    let spec = fs.readFileSync(specTemplate, "utf-8");
    spec = spec.replace(/\{\{VERSION\}\}/g, rpmVersion);
    spec = spec.replace(/\{\{RELEASE\}\}/g, rpmRelease);
    fs.writeFileSync(path.join(specsDir, "dacx.spec"), spec);
  }

  const rpmName = "Dacx-Linux-x86_64.rpm";
  const rpmPath = path.join(releaseDir, rpmName);
  removeIfExists(rpmPath);

  run(
    `rpmbuild --define "_topdir ${rpmRoot}" ` +
    `--define "buildroot ${buildroot}" ` +
    `--target x86_64 -bb "${path.join(specsDir, "dacx.spec")}"`,
  );

  // Find the built RPM and move it
  const builtRpms = findFiles(rpmsDir, ".rpm");
  if (builtRpms.length > 0) {
    fs.copyFileSync(builtRpms[0], rpmPath);
    console.log(`  ✓ ${rpmName}`);
  } else {
    console.warn("  ⚠ rpmbuild succeeded but no .rpm found in output");
  }

  // Cleanup
  fs.rmSync(rpmRoot, { recursive: true });
}

function buildAppImage(buildDir, desktopFile, iconFile) {
  // Check for appimagetool
  const toolName = hasCommand("appimagetool") ? "appimagetool" : null;
  const envTool = process.env.APPIMAGETOOL;
  const appimageToolCmd = envTool || toolName;

  if (!appimageToolCmd) {
    console.warn("  ⚠ appimagetool not found — skipping .AppImage");
    console.warn("    Install from: https://github.com/AppImage/appimagetool/releases");
    console.warn("    Or set APPIMAGETOOL=/path/to/appimagetool in .env");
    return;
  }

  const appDir = path.join(root, "build", "AppDir");
  if (fs.existsSync(appDir)) fs.rmSync(appDir, { recursive: true });

  // AppDir structure
  const optDir = path.join(appDir, "opt", "dacx");
  const binDir = path.join(appDir, "usr", "bin");
  const appsDir = path.join(appDir, "usr", "share", "applications");
  const iconDir = path.join(appDir, "usr", "share", "icons", "hicolor", "256x256", "apps");

  fs.mkdirSync(optDir, { recursive: true });
  fs.mkdirSync(binDir, { recursive: true });
  fs.mkdirSync(appsDir, { recursive: true });
  fs.mkdirSync(iconDir, { recursive: true });

  // Copy bundle
  copyDirSync(buildDir, optDir);

  // Launcher script at usr/bin
  fs.writeFileSync(
    path.join(binDir, "dacx"),
    '#!/bin/sh\nHERE="$(dirname "$(readlink -f "$0")")"\nexec "$HERE/../../opt/dacx/dacx" "$@"\n',
    { mode: 0o755 },
  );

  // Desktop file at root and usr/share
  if (fs.existsSync(desktopFile)) {
    let desktop = fs.readFileSync(desktopFile, "utf-8");
    desktop = desktop.replace(/^Exec=.*$/m, "Exec=dacx %U");
    fs.writeFileSync(path.join(appDir, "dacx.desktop"), desktop);
    fs.writeFileSync(path.join(appsDir, "dacx.desktop"), desktop);
  }

  // Icon at root and in hicolor
  if (iconFile) {
    fs.copyFileSync(iconFile, path.join(appDir, "dacx.png"));
    fs.copyFileSync(iconFile, path.join(iconDir, "dacx.png"));
  }

  // AppRun entry point
  fs.writeFileSync(
    path.join(appDir, "AppRun"),
    `#!/bin/sh
HERE="$(dirname "$(readlink -f "$0")")"
export LD_LIBRARY_PATH="$HERE/opt/dacx/lib:$LD_LIBRARY_PATH"
exec "$HERE/opt/dacx/dacx" "$@"
`,
    { mode: 0o755 },
  );

  const appImageName = "Dacx-Linux-x86_64.AppImage";
  const appImagePath = path.join(releaseDir, appImageName);
  removeIfExists(appImagePath);

  // ARCH must be set for appimagetool
  run(`ARCH=x86_64 "${appimageToolCmd}" "${appDir}" "${appImagePath}"`);

  // Cleanup
  fs.rmSync(appDir, { recursive: true });
  console.log(`  ✓ ${appImageName}`);
}

// ── Helpers ────────────────────────────────────────────────────

function getDirSizeBytes(dirPath) {
  let total = 0;
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const full = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      total += getDirSizeBytes(full);
    } else {
      total += fs.statSync(full).size;
    }
  }
  return total;
}

function findFiles(dirPath, ext) {
  const results = [];
  if (!fs.existsSync(dirPath)) return results;
  for (const entry of fs.readdirSync(dirPath, { withFileTypes: true })) {
    const full = path.join(dirPath, entry.name);
    if (entry.isDirectory()) {
      results.push(...findFiles(full, ext));
    } else if (entry.name.endsWith(ext)) {
      results.push(full);
    }
  }
  return results;
}

// ── Main ───────────────────────────────────────────────────────

console.log(`\nPackaging Dacx v${VERSION} for ${platform}...\n`);

switch (platform) {
  case "win":
    packageWindows();
    break;
  case "mac":
    packageMac();
    break;
  case "linux":
    packageLinux();
    break;
  default:
    console.error(`Unknown platform: ${platform}`);
    console.error("Valid options: win, mac, linux");
    process.exit(1);
}

console.log("\nDone. Artifacts in release/\n");
