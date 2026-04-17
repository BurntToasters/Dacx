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
 *   release/DACX-Windows-x64.msix   (MSIX installer via `dart run msix:create`)
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
  run(
    `powershell -NoProfile -Command "Compress-Archive -Path '${buildDir}\\*' -DestinationPath '${zipPath}'"`,
  );
  console.log(`  ✓ ${zipName}`);

  // 2. MSIX installer
  try {
    run("dart run msix:create");
    // msix package outputs to build/windows/x64/runner/Release/*.msix
    const msixFiles = fs.readdirSync(buildDir).filter((f) => f.endsWith(".msix"));
    if (msixFiles.length > 0) {
      const msixDest = path.join(releaseDir, "DACX-Windows-x64.msix");
      removeIfExists(msixDest);
      fs.copyFileSync(path.join(buildDir, msixFiles[0]), msixDest);
      console.log(`  ✓ DACX-Windows-x64.msix`);
    }
  } catch (err) {
    // msix output may land in build/windows/x64/runner/Release or build/windows/runner/Release
    // Also check the standard output path
    const altMsixDir = path.join(root, "build", "windows", "x64", "runner", "Release");
    const altFiles = fs.existsSync(altMsixDir)
      ? fs.readdirSync(altMsixDir).filter((f) => f.endsWith(".msix"))
      : [];
    if (altFiles.length > 0) {
      const msixDest = path.join(releaseDir, "DACX-Windows-x64.msix");
      removeIfExists(msixDest);
      fs.copyFileSync(path.join(altMsixDir, altFiles[0]), msixDest);
      console.log(`  ✓ DACX-Windows-x64.msix`);
    } else {
      console.warn(`  ⚠ MSIX creation failed — skipping. Install 'msix' dev dependency to enable.`);
    }
  }
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
