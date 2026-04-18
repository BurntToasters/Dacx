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
 *   release/DACX-Windows-x64.zip    (portable zip)
 *   release/DACX-Windows-x64.exe    (Inno Setup installer)
 *   release/DACX-Windows-x64.msi    (WiX Toolset installer)
 *
 * macOS produces:
 *   release/DACX-macOS.zip           (codesigned zip — from mac-codesign.sh or fallback)
 *   release/DACX-macOS.dmg           (disk image via hdiutil)
 *
 * Linux produces:
 *   release/DACX-Linux-x86_64.tar.gz (portable tarball)
 *   release/DACX-Linux-amd64.deb     (Debian package via dpkg-deb)
 *   release/DACX-Linux-x86_64.rpm    (RPM package via rpmbuild)
 *   release/DACX-Linux-x86_64.AppImage (AppImage via appimagetool)
 */

import fs from "fs";
import path from "path";
import { execSync } from "child_process";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf-8"));
const VERSION = pkg.version;

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

function resolveInnoSetupCompilerPath() {
  if (process.env.INNO_SETUP_COMPILER && fs.existsSync(process.env.INNO_SETUP_COMPILER)) {
    return process.env.INNO_SETUP_COMPILER;
  }

  const pathHit = resolveCommandFromPath("iscc");
  if (pathHit) return pathHit;

  const programFilesX86 = process.env["ProgramFiles(x86)"];
  const programFiles = process.env.ProgramFiles;

  const directCandidates = [
    programFilesX86 ? path.join(programFilesX86, "Inno Setup 6", "ISCC.exe") : null,
    programFiles ? path.join(programFiles, "Inno Setup 6", "ISCC.exe") : null,
  ];

  const prefixedDirCandidates = [
    ...findWindowsDirByPrefix(programFilesX86, /^Inno Setup/i),
    ...findWindowsDirByPrefix(programFiles, /^Inno Setup/i),
  ].map((dir) => path.join(dir, "ISCC.exe"));

  return firstExistingPath([...directCandidates, ...prefixedDirCandidates]);
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

function escapeXmlAttr(value) {
  return String(value)
    .replace(/&/g, "&amp;")
    .replace(/"/g, "&quot;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
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
  const match = String(version).match(/^(\d+)\.(\d+)\.(\d+)/);
  if (!match) {
    throw new Error(
      `Cannot convert version "${version}" to MSI version. Expected semver like 1.2.3`,
    );
  }
  return `${Number(match[1])}.${Number(match[2])}.${Number(match[3])}`;
}

// ── Windows ────────────────────────────────────────────────────

function packageWindows() {
  const buildDir = path.join(root, "build", "windows", "x64", "runner", "Release");
  if (!fs.existsSync(buildDir)) {
    console.error(`Build directory not found: ${buildDir}`);
    console.error("Run 'npm run build:win' first.");
    process.exit(1);
  }

  // 1. Portable zip
  const zipName = "DACX-Windows-x64.zip";
  const zipPath = path.join(releaseDir, zipName);
  removeIfExists(zipPath);
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
  console.log(`  ✓ ${zipName}`);

  // 2. EXE installer (Inno Setup)
  buildWindowsExeInstaller(buildDir);

  // 3. MSI installer (WiX Toolset)
  buildWindowsMsiInstaller(buildDir);
}

function buildWindowsExeInstaller(buildDir) {
  const isccPath = resolveInnoSetupCompilerPath();
  if (!isccPath) {
    console.error("Inno Setup compiler was not found.");
    console.error("Install it: winget install JRSoftware.InnoSetup");
    console.error(
      "If already installed but not detected, set INNO_SETUP_COMPILER to full ISCC.exe path.",
    );
    process.exit(1);
  }

  const outName = "DACX-Windows-x64.exe";
  const outPath = path.join(releaseDir, outName);
  removeIfExists(outPath);

  const installerDir = path.join(root, "build", "win-installer");
  fs.mkdirSync(installerDir, { recursive: true });
  const issPath = path.join(installerDir, "dacx-installer.iss");

  const setupIconPath = path.join(root, "windows", "runner", "resources", "app_icon.ico");

  const script = `; Auto-generated by scripts/package-release.js
#define AppName "DACX"
#define AppVersion GetEnv("APP_VERSION")
#define AppPublisher "run.rosie"
#define AppExeName "dacx.exe"
#define SourceDir GetEnv("SOURCE_DIR")
#define OutputDir GetEnv("OUTPUT_DIR")
#define OutputName GetEnv("OUTPUT_NAME")
#define SetupIconPath GetEnv("SETUP_ICON_PATH")

[Setup]
AppId=run.rosie.dacx
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={autopf}\\{#AppName}
DefaultGroupName={#AppName}
OutputDir={#OutputDir}
OutputBaseFilename={#OutputName}
Compression=lzma2
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
UninstallDisplayIcon={app}\\{#AppExeName}
DisableProgramGroupPage=yes
WizardStyle=modern
#if SetupIconPath != ""
SetupIconFile={#SetupIconPath}
#endif

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"

[Files]
Source: "{#SourceDir}\\*"; DestDir: "{app}"; Flags: recursesubdirs createallsubdirs ignoreversion

[Icons]
Name: "{autoprograms}\\{#AppName}"; Filename: "{app}\\{#AppExeName}"
Name: "{autodesktop}\\{#AppName}"; Filename: "{app}\\{#AppExeName}"; Tasks: desktopicon
`;

  fs.writeFileSync(issPath, script);

  run(`"${isccPath}" /Qp "${issPath}"`, {
    env: {
      ...process.env,
      APP_VERSION: VERSION,
      SOURCE_DIR: toWindowsPath(buildDir),
      OUTPUT_DIR: toWindowsPath(releaseDir),
      OUTPUT_NAME: "DACX-Windows-x64",
      SETUP_ICON_PATH: fs.existsSync(setupIconPath) ? toWindowsPath(setupIconPath) : "",
    },
  });

  if (!fs.existsSync(outPath)) {
    console.error(`Inno Setup did not produce expected output: ${outPath}`);
    process.exit(1);
  }
  console.log(`  ✓ ${outName}`);
}

function buildWindowsMsiInstaller(buildDir) {
  // Prefer WiX v4+ (wix build), fall back to WiX v3 (candle + light).
  const wixV4Path = resolveWixV4PlusTool();
  if (wixV4Path) {
    buildWindowsMsiInstallerV4(buildDir, wixV4Path);
    return;
  }

  const wixV3Paths = resolveWixV3ToolPaths();
  if (wixV3Paths) {
    buildWindowsMsiInstallerV3(buildDir, wixV3Paths);
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

function buildWindowsMsiInstallerV4(buildDir, wixPath) {
  const outName = "DACX-Windows-x64.msi";
  const outPath = path.join(releaseDir, outName);
  removeIfExists(outPath);

  const installerDir = path.join(root, "build", "win-installer");
  fs.mkdirSync(installerDir, { recursive: true });
  const wxsPath = path.join(installerDir, "dacx-installer.wxs");

  writeWindowsWixV4Source(buildDir, wxsPath);

  const majorVersion = getWixMajorVersion(wixPath);
  const acceptEulaFlag = majorVersion >= 7 ? " -acceptEula wix7" : "";
  run(
    `"${wixPath}" build${acceptEulaFlag} -arch x64` +
      ` -out "${toWindowsPath(outPath)}" "${toWindowsPath(wxsPath)}"`,
  );

  if (!fs.existsSync(outPath)) {
    console.error(`WiX did not produce expected output: ${outPath}`);
    process.exit(1);
  }
  console.log(`  ✓ ${outName}`);
}

function buildWindowsMsiInstallerV3(buildDir, wixV3Paths) {
  const outName = "DACX-Windows-x64.msi";
  const outPath = path.join(releaseDir, outName);
  removeIfExists(outPath);

  const installerDir = path.join(root, "build", "win-installer");
  fs.mkdirSync(installerDir, { recursive: true });
  const wxsPath = path.join(installerDir, "dacx-installer.wxs");
  const wixobjPath = path.join(installerDir, "dacx-installer.wixobj");

  writeWindowsWixSource(buildDir, wxsPath);

  run(`"${wixV3Paths.candlePath}" -nologo -arch x64 -out "${wixobjPath}" "${wxsPath}"`);
  run(`"${wixV3Paths.lightPath}" -nologo -spdb -out "${outPath}" "${wixobjPath}"`);

  if (!fs.existsSync(outPath)) {
    console.error(`WiX did not produce expected output: ${outPath}`);
    process.exit(1);
  }
  console.log(`  ✓ ${outName}`);
}

function writeWindowsWixV4Source(buildDir, wxsPath) {
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
  const msiVersion = toMsiVersion(VERSION);
  const iconBlock = fs.existsSync(appIconPath)
    ? [
        `    <Icon Id="AppIcon.ico" SourceFile="${escapeXmlAttr(toWindowsPath(appIconPath))}" />`,
        `    <Property Id="ARPPRODUCTICON" Value="AppIcon.ico" />`,
      ].join("\n")
    : "";

  const componentRefs = [
    ...fileComponentIds.map((id) => `      <ComponentRef Id="${id}" />`),
  ].join("\n");

  // WiX v4+ schema: <Package> replaces the v3 <Product>+<Package> pair.
  // Scope="perMachine" replaces InstallScope="perMachine"; Platform moved to CLI (-arch x64).
  // StandardDirectory replaces manual TARGETDIR/ProgramFiles64Folder definitions.
  const wixSource = `<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://wixtoolset.org/schemas/v4/wxs">
  <Package
    Name="DACX"
    Language="1033"
    Version="${msiVersion}"
    Manufacturer="run.rosie"
    UpgradeCode="{D8D4A9F8-084A-4A7C-9713-3BC4F78E2A93}"
    Scope="perMachine">
    <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />
    <MediaTemplate EmbedCab="yes" />
${iconBlock}
    <Feature Id="ProductFeature" Title="DACX" Level="1">
${componentRefs}
    </Feature>
  </Package>

  <Fragment>
    <StandardDirectory Id="ProgramFiles64Folder">
      <Directory Id="INSTALLFOLDER" Name="DACX">
${renderDirectoryContents(rootNode, "        ").join("\n")}
      </Directory>
    </StandardDirectory>
  </Fragment>
</Wix>
`;

  fs.writeFileSync(wxsPath, wixSource);
}

function writeWindowsWixSource(buildDir, wxsPath) {
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
  const msiVersion = toMsiVersion(VERSION);
  const iconBlock = fs.existsSync(appIconPath)
    ? [
        `    <Icon Id="AppIcon.ico" SourceFile="${escapeXmlAttr(toWindowsPath(appIconPath))}" />`,
        `    <Property Id="ARPPRODUCTICON" Value="AppIcon.ico" />`,
      ].join("\n")
    : "";

  const componentRefs = [
    ...fileComponentIds.map((id) => `      <ComponentRef Id="${id}" />`),
  ].join("\n");

  const wixSource = `<?xml version="1.0" encoding="UTF-8"?>
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product
    Id="*"
    Name="DACX"
    Language="1033"
    Version="${msiVersion}"
    Manufacturer="run.rosie"
    UpgradeCode="{D8D4A9F8-084A-4A7C-9713-3BC4F78E2A93}">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" Platform="x64" />
    <MajorUpgrade DowngradeErrorMessage="A newer version of [ProductName] is already installed." />
    <MediaTemplate EmbedCab="yes" />
${iconBlock}
    <Feature Id="ProductFeature" Title="DACX" Level="1">
${componentRefs}
    </Feature>
  </Product>

  <Fragment>
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="ProgramFiles64Folder">
        <Directory Id="INSTALLFOLDER" Name="DACX">
${renderDirectoryContents(rootNode, "          ").join("\n")}
        </Directory>
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
    root, "build", "macos", "Build", "Products", "Release", "dacx.app",
  );
  if (!fs.existsSync(appBundle)) {
    console.error(`App bundle not found: ${appBundle}`);
    console.error("Run 'npm run build:mac' first.");
    process.exit(1);
  }

  // 1. Zip (may already exist from mac-codesign.sh)
  const codesignZipPattern = new RegExp(`^dacx-.*-macos\\.zip$`, "i");
  const existing = fs.readdirSync(releaseDir).filter((f) => codesignZipPattern.test(f));
  if (existing.length > 0) {
    console.log(`  ✓ ${existing[0]} (from mac-codesign.sh)`);
  } else {
    const zipName = "DACX-macOS.zip";
    const zipPath = path.join(releaseDir, zipName);
    removeIfExists(zipPath);
    run(`ditto -c -k --keepParent "${appBundle}" "${zipPath}"`);
    console.log(`  ✓ ${zipName} (unsigned)`);
  }

  // 2. DMG
  const dmgName = "DACX-macOS.dmg";
  const dmgPath = path.join(releaseDir, dmgName);
  removeIfExists(dmgPath);

  // Create a temporary DMG staging directory
  const dmgStage = path.join(root, "build", "dmg-stage");
  if (fs.existsSync(dmgStage)) {
    run(`rm -rf "${dmgStage}"`);
  }
  fs.mkdirSync(dmgStage, { recursive: true });

  // Copy app bundle and create Applications symlink
  run(`cp -R "${appBundle}" "${dmgStage}/DACX.app"`);
  run(`ln -s /Applications "${dmgStage}/Applications"`);

  // Create DMG
  run(
    `hdiutil create -volname "DACX" -srcfolder "${dmgStage}" ` +
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
  const tarName = "DACX-Linux-x86_64.tar.gz";
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

  const debName = "DACX-Linux-amd64.deb";
  const debPath = path.join(releaseDir, debName);
  removeIfExists(debPath);
  run(`dpkg-deb --build --root-owner-group "${debRoot}" "${debPath}"`);

  // Cleanup
  fs.rmSync(debRoot, { recursive: true });
  console.log(`  ✓ ${debName}`);
}

function buildRpm(buildDir, desktopFile, iconFile) {
  if (!hasCommand("rpmbuild")) {
    console.warn("  ⚠ rpmbuild not found — skipping .rpm");
    return;
  }

  const rpmRoot = path.join(root, "build", "rpm-stage");
  if (fs.existsSync(rpmRoot)) fs.rmSync(rpmRoot, { recursive: true });

  // rpmbuild directory structure
  const buildroot = path.join(rpmRoot, "BUILDROOT", `dacx-${VERSION}-1.x86_64`);
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
    spec = spec.replace(/\{\{VERSION\}\}/g, VERSION);
    fs.writeFileSync(path.join(specsDir, "dacx.spec"), spec);
  }

  const rpmName = "DACX-Linux-x86_64.rpm";
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

  const appImageName = "DACX-Linux-x86_64.AppImage";
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

console.log(`\nPackaging DACX v${VERSION} for ${platform}...\n`);

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
