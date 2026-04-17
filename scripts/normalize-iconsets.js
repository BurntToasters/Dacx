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
  generateLinux();

  console.log("\n✔ All platform icons generated.");
}

main();
