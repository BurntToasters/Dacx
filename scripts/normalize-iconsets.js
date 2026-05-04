#!/usr/bin/env node

/**
 * Generate all platform app icons from a single source PNG.
 *
 * Requires: ImageMagick 7+ (`magick` command).
 *
 * Source:  assets/icon/icon.png  (1024×1024 recommended)
 *
 * Outputs:
 *   Windows — windows/runner/resources/app_icon.ico  (multi-size ICO)
 *   macOS   — macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_*.png
 *   Linux   — linux/packaging/icons/  (hicolor sizes)
 */

import fs from "fs";
import os from "os";
import path from "path";
import { execSync } from "child_process";
import { fileURLToPath } from "url";

const root = path.dirname(path.dirname(fileURLToPath(import.meta.url)));
const SOURCE = path.join(root, "assets", "icon", "icon.png");

// ── Helpers ──────────────────────────────────────────────────

function run(cmd) {
  console.log(`  $ ${cmd}`);
  execSync(cmd, { stdio: "inherit", cwd: root });
}

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function hasMagick() {
  try {
    execSync(
      process.platform === "win32" ? "where magick" : "command -v magick",
      { stdio: "ignore" },
    );
    return true;
  } catch {
    return false;
  }
}

// ── Windows — multi-size .ico via ImageMagick ────────────────

function generateWindows() {
  console.log("\n── Windows ──");
  const outDir = path.join(root, "windows", "runner", "resources");
  ensureDir(outDir);
  const ico = path.join(outDir, "app_icon.ico");

  // ICO embeds 16, 24, 32, 48, 64, 128, 256
  const sizes = [16, 24, 32, 48, 64, 128, 256];
  const resizeArgs = sizes
    .map((s) => `\\( "${SOURCE}" -resize ${s}x${s} \\)`)
    .join(" ");

  // On Windows, magick uses parentheses differently
  if (process.platform === "win32") {
    const winArgs = sizes
      .map((s) => `( "${SOURCE}" -resize ${s}x${s} )`)
      .join(" ");
    run(`magick ${winArgs} "${ico}"`);
  } else {
    run(`magick ${resizeArgs} "${ico}"`);
  }

  console.log(`  ✓ ${path.relative(root, ico)}`);
}

// ── macOS — individual PNGs for AppIcon.appiconset ───────────

function generateMacOS() {
  console.log("\n── macOS ──");
  const outDir = path.join(
    root,
    "macos",
    "Runner",
    "Assets.xcassets",
    "AppIcon.appiconset",
  );
  ensureDir(outDir);

  // Sizes needed by Contents.json (unique pixel sizes)
  const sizes = [16, 32, 64, 128, 256, 512, 1024];

  for (const s of sizes) {
    const outFile = path.join(outDir, `app_icon_${s}.png`);
    run(`magick "${SOURCE}" -resize ${s}x${s} "${outFile}"`);
    console.log(`  ✓ app_icon_${s}.png`);
  }
}

// ── Linux — hicolor icon theme PNGs ──────────────────────────

function generateLinux() {
  console.log("\n── Linux ──");
  const sizes = [16, 32, 48, 64, 128, 256, 512];

  for (const s of sizes) {
    const outDir = path.join(
      root,
      "linux",
      "packaging",
      "icons",
      "hicolor",
      `${s}x${s}`,
      "apps",
    );
    ensureDir(outDir);
    const outFile = path.join(outDir, "dacx.png");
    run(`magick "${SOURCE}" -resize ${s}x${s} "${outFile}"`);
    console.log(`  ✓ ${s}x${s}/apps/dacx.png`);
  }
}

// ── macOS — document type icns ───────────────────────────────

function generateMacOSDocumentIcons() {
  console.log("\n── macOS document icons ──");
  if (process.platform !== "darwin") {
    console.log("  (skipped: requires macOS iconutil)");
    return;
  }

  const docs = [
    {
      source: path.join(root, "assets", "dacx_music_icon.png"),
      out: path.join(root, "macos", "Runner", "dacx_music_icon.icns"),
      label: "dacx_music_icon",
    },
  ];

  const sizes = [
    [16, "icon_16x16.png"],
    [32, "icon_16x16@2x.png"],
    [32, "icon_32x32.png"],
    [64, "icon_32x32@2x.png"],
    [128, "icon_128x128.png"],
    [256, "icon_128x128@2x.png"],
    [256, "icon_256x256.png"],
    [512, "icon_256x256@2x.png"],
    [512, "icon_512x512.png"],
    [1024, "icon_512x512@2x.png"],
  ];

  for (const doc of docs) {
    if (!fs.existsSync(doc.source)) {
      console.warn(`  ! missing source: ${path.relative(root, doc.source)}`);
      continue;
    }
    const tmpDir = fs.mkdtempSync(
      path.join(os.tmpdir(), `${doc.label}-`),
    ) + ".iconset";
    fs.mkdirSync(tmpDir, { recursive: true });
    for (const [sz, name] of sizes) {
      run(`sips -z ${sz} ${sz} "${doc.source}" --out "${path.join(tmpDir, name)}" >/dev/null`);
    }
    run(`iconutil -c icns "${tmpDir}" -o "${doc.out}"`);
    fs.rmSync(tmpDir, { recursive: true, force: true });
    console.log(`  ✓ ${path.relative(root, doc.out)}`);
  }
}

// ── Main ─────────────────────────────────────────────────────

function main() {
  if (!fs.existsSync(SOURCE)) {
    console.error(`Source icon not found: ${SOURCE}`);
    console.error("Place a 1024×1024 PNG at assets/icon/icon.png");
    process.exit(1);
  }

  if (!hasMagick()) {
    console.error("ImageMagick 7+ (magick) is required but not found.");
    console.error("Install it:");
    console.error("  Windows:  winget install ImageMagick.ImageMagick");
    console.error("  macOS:    brew install imagemagick");
    console.error("  Linux:    sudo apt install imagemagick");
    process.exit(1);
  }

  console.log(`Source: ${path.relative(root, SOURCE)}`);

  generateWindows();
  generateMacOS();
  generateMacOSDocumentIcons();
  generateLinux();

  console.log("\n✔ All platform icons generated.");
}

main();
