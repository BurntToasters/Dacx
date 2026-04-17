#!/usr/bin/env node

import fs from "fs";
import path from "path";
import crypto from "crypto";
import { execSync, spawnSync } from "child_process";
import https from "https";
import { fileURLToPath } from "url";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(__dirname, "..");
const releaseDir = path.join(root, "release");
const pkg = JSON.parse(fs.readFileSync(path.join(root, "package.json"), "utf-8"));

const VERSION = pkg.version;
const TAG = `v${VERSION}`;
const IS_PRERELEASE = /-(?:beta|alpha|rc)(?:[.-]?\d+)?/i.test(VERSION);

const GPG_KEY_ID = process.env.GPG_KEY_ID;
const GPG_PASSPHRASE = process.env.GPG_PASSPHRASE;
const GH_TOKEN = process.env.GH_TOKEN || process.env.GITHUB_TOKEN;
const REPO_OWNER = process.env.GH_REPO_OWNER || "BurntToasters";
const REPO_NAME = process.env.GH_REPO_NAME || "DACX";
const TAG_DOWNLOAD_BASE_URL = `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${encodeURIComponent(TAG)}`;
const RELEASE_DOWNLOAD_BASE_URL = (
  process.env.RELEASE_DOWNLOAD_BASE_URL || TAG_DOWNLOAD_BASE_URL
).replace(/\/+$/, "");
const RELEASE_NOTES = process.env.RELEASE_NOTES || "";
const RELEASE_PUB_DATE = process.env.RELEASE_PUB_DATE || new Date().toISOString();
const ALLOW_ASSET_REPLACE = !/^(0|false|no|off)$/i.test(
  String(process.env.ALLOW_ASSET_REPLACE || "true").trim(),
);

// ── Artifact detection ───────────────────────────────────────

const ext = (e) => (n) => n.toLowerCase().endsWith(e);
const rx = (r) => (n) => r.test(n);
const isChecksumTextName = rx(/^SHA256SUMS(?:-[a-z0-9_]+(?:-[a-z0-9_]+)?)?\.txt$/i);

const ARTIFACT_RULES = [
  rx(/^DACX-.*\.exe$/i),
  ext(".msix"),
  ext(".dmg"),
  ext(".zip"),
  ext(".deb"),
  ext(".rpm"),
  ext(".flatpak"),
  rx(/\.appimage$/i),
  rx(/\.tar\.gz$/i),
  rx(/\.(?:exe|msix|dmg|deb|rpm|flatpak|appimage|zip)\.sig$/i),
  rx(/\.tar\.gz\.sig$/i),
];

const SIGN_RULES = [
  ext(".exe"),
  ext(".msix"),
  ext(".dmg"),
  ext(".deb"),
  ext(".rpm"),
  ext(".flatpak"),
  rx(/\.appimage$/i),
  rx(/\.zip$/i),
  rx(/\.tar\.gz$/i),
];

const isArtifact = (name) => ARTIFACT_RULES.some((r) => r(name));
const isSignable = (name) => SIGN_RULES.some((r) => r(name));

// Flutter build output locations
const SEARCH_DIRS = [
  path.join(root, "build"),
  path.join(root, "release"),
];

// ── Artifact naming ──────────────────────────────────────────

function cleanArtifactBaseName(name) {
  // macOS
  if (/\.app\.tar\.gz$/i.test(name)) return "DACX-macOS.app.tar.gz";
  if (/\.dmg$/i.test(name)) return "DACX-macOS.dmg";
  if (/^dacx.*\.zip$/i.test(name) && /mac/i.test(name)) return "DACX-macOS.zip";

  // Windows
  if (/x64.*\.exe$/i.test(name) || /\.exe$/i.test(name)) return "DACX-Windows-x64.exe";
  if (/\.msix$/i.test(name)) return "DACX-Windows-x64.msix";

  // Linux
  if (/amd64\.deb$/i.test(name) || /x86_64\.deb$/i.test(name)) return "DACX-Linux-amd64.deb";
  if (/aarch64\.deb$/i.test(name) || /arm64\.deb$/i.test(name)) return "DACX-Linux-arm64.deb";

  if (/x86_64\.rpm$/i.test(name) || /amd64\.rpm$/i.test(name)) return "DACX-Linux-x86_64.rpm";
  if (/aarch64\.rpm$/i.test(name) || /arm64\.rpm$/i.test(name)) return "DACX-Linux-aarch64.rpm";

  if (/x86_64\.appimage$/i.test(name) || /amd64\.appimage$/i.test(name))
    return "DACX-Linux-x86_64.AppImage";
  if (/aarch64\.appimage$/i.test(name) || /arm64\.appimage$/i.test(name))
    return "DACX-Linux-arm64.AppImage";

  if (/x86_64\.flatpak$/i.test(name) || /amd64\.flatpak$/i.test(name))
    return "DACX-Linux-x86_64.flatpak";
  if (/aarch64\.flatpak$/i.test(name) || /arm64\.flatpak$/i.test(name))
    return "DACX-Linux-aarch64.flatpak";

  // Generic zip (Linux bundle)
  if (/linux.*\.zip$/i.test(name)) return "DACX-Linux-x64.zip";

  // Linux tarball
  if (/linux.*\.tar\.gz$/i.test(name) || /x86_64.*\.tar\.gz$/i.test(name))
    return "DACX-Linux-x86_64.tar.gz";
  if (/aarch64.*\.tar\.gz$/i.test(name) || /arm64.*\.tar\.gz$/i.test(name))
    return "DACX-Linux-arm64.tar.gz";

  // Windows zip
  if (/windows.*\.zip$/i.test(name)) return "DACX-Windows-x64.zip";

  return name;
}

function cleanArtifactName(name) {
  if (name.endsWith(".sig")) {
    return `${cleanArtifactBaseName(name.slice(0, -4))}.sig`;
  }
  return cleanArtifactBaseName(name);
}

function shouldUploadReleaseEntry(name) {
  return isArtifact(name) || name.endsWith(".asc") || isChecksumTextName(name);
}

// ── Version matching ─────────────────────────────────────────

function artifactMatchesVersion(name) {
  const versions = name.match(/\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?(?:\+[0-9A-Za-z.-]+)?/g);
  if (!versions || versions.length === 0) return true;
  return versions.some((v) => v === VERSION || v.startsWith(VERSION + "-"));
}

// ── File collection ──────────────────────────────────────────

function clearReleaseStaging() {
  if (!fs.existsSync(releaseDir)) return;
  for (const name of fs.readdirSync(releaseDir)) {
    const fullPath = path.join(releaseDir, name);
    let isFile = false;
    try {
      isFile = fs.statSync(fullPath).isFile();
    } catch {
      continue;
    }
    if (!isFile) continue;
    if (isArtifact(name) || name.endsWith(".asc") || isChecksumTextName(name)) {
      fs.rmSync(fullPath, { force: true });
    }
  }
}

function pickNewestByBasename(paths) {
  const latest = new Map();
  for (const filePath of paths) {
    const name = path.basename(filePath);
    let stat;
    try {
      stat = fs.statSync(filePath);
    } catch {
      continue;
    }
    const current = latest.get(name);
    if (!current || stat.mtimeMs > current.mtimeMs) {
      latest.set(name, { filePath, mtimeMs: stat.mtimeMs });
    }
  }
  return Array.from(latest.values()).map((entry) => entry.filePath);
}

function walk(dir, results = []) {
  if (!fs.existsSync(dir)) return results;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full, results);
    } else if (entry.isFile() && isArtifact(entry.name)) {
      results.push(full);
    }
  }
  return results;
}

function normalizePreStagedArtifacts(staged) {
  const selected = new Map();

  for (const filePath of staged) {
    const originalName = path.basename(filePath);
    const cleanName = cleanArtifactName(originalName);
    let stat;
    try {
      stat = fs.statSync(filePath);
    } catch {
      continue;
    }

    const current = selected.get(cleanName);
    if (!current || stat.mtimeMs > current.mtimeMs) {
      selected.set(cleanName, {
        filePath,
        mtimeMs: stat.mtimeMs,
        originalName,
      });
    }
  }

  const canonicalPaths = new Set();
  for (const [cleanName, entry] of selected) {
    const dest = path.join(releaseDir, cleanName);
    canonicalPaths.add(path.resolve(dest));
    if (path.resolve(entry.filePath) !== path.resolve(dest)) {
      fs.copyFileSync(entry.filePath, dest);
      console.log(`  + ${entry.originalName} → ${cleanName}`);
    }
  }

  for (const filePath of staged) {
    if (!canonicalPaths.has(path.resolve(filePath))) {
      fs.rmSync(filePath, { force: true });
    }
  }

  return Array.from(selected.keys())
    .sort((a, b) => a.localeCompare(b))
    .map((name) => path.join(releaseDir, name));
}

function collectArtifacts() {
  fs.mkdirSync(releaseDir, { recursive: true });

  const discovered = SEARCH_DIRS.flatMap((d) => walk(d));
  const found = discovered.filter((filePath) =>
    artifactMatchesVersion(path.basename(filePath)),
  );

  if (found.length > 0) {
    clearReleaseStaging();
    if (found.length < discovered.length) {
      console.log(`  ~ Skipped ${discovered.length - found.length} artifact(s) not matching ${VERSION}`);
    }

    const selected = pickNewestByBasename(found);
    const collected = [];
    for (const src of selected) {
      const originalName = path.basename(src);
      const cleanName = cleanArtifactName(originalName);
      const dest = path.join(releaseDir, cleanName);
      fs.copyFileSync(src, dest);
      if (cleanName !== originalName) {
        console.log(`  + ${originalName} → ${cleanName}`);
      } else {
        console.log(`  + ${originalName}`);
      }
      collected.push(dest);
    }
    return collected;
  }

  const staged = fs
    .readdirSync(releaseDir)
    .filter(
      (n) =>
        isArtifact(n) &&
        artifactMatchesVersion(n) &&
        !n.endsWith(".asc") &&
        !isChecksumTextName(n),
    )
    .map((n) => path.join(releaseDir, n));

  if (staged.length === 0) {
    console.error("No build artifacts found in:", SEARCH_DIRS.join(", "));
    console.error("  Build the project first, or place artifacts in release/");
    process.exit(1);
  }

  console.log(`  Found ${staged.length} pre-staged artifact(s) in release/`);
  return normalizePreStagedArtifacts(staged);
}

// ── Checksums ────────────────────────────────────────────────

function sha256(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function generateChecksums(files) {
  const candidates = files.filter((f) => {
    const name = path.basename(f);
    return !name.endsWith(".asc") && !isChecksumTextName(name);
  });

  if (candidates.length === 0) return [];

  const entries = candidates
    .sort((a, b) => path.basename(a).localeCompare(path.basename(b)))
    .map((f) => `${sha256(f)}  ${path.basename(f)}`);

  const fileName = "SHA256SUMS.txt";
  const out = path.join(releaseDir, fileName);
  fs.writeFileSync(out, entries.join("\n") + "\n");
  console.log(`  + ${fileName} (${entries.length} entries)`);
  return [out];
}

// ── GPG signing ──────────────────────────────────────────────

function signFile(filePath) {
  const asc = `${filePath}.asc`;
  const args = ["--batch", "--yes", "--armor", "--detach-sign"];
  if (GPG_KEY_ID) {
    args.push("--local-user", GPG_KEY_ID);
  }
  const usePassphraseStdin = Boolean(GPG_PASSPHRASE);
  if (usePassphraseStdin) {
    args.push("--pinentry-mode", "loopback", "--passphrase-fd", "0");
  }
  args.push("--output", asc, filePath);

  const result = spawnSync("gpg", args, {
    stdio: "pipe",
    input: usePassphraseStdin ? `${GPG_PASSPHRASE}\n` : undefined,
  });
  if (result.error) throw result.error;
  if (result.status !== 0) {
    throw new Error(`GPG signing failed: ${result.stderr?.toString() || "unknown error"}`);
  }
  return asc;
}

function signArtifacts(files) {
  const ascFiles = [];
  for (const f of files) {
    if (isSignable(path.basename(f))) {
      ascFiles.push(signFile(f));
      console.log(`  + ${path.basename(f)}.asc`);
    }
  }
  return ascFiles;
}

// ── GitHub API ───────────────────────────────────────────────

function ghRequest(method, endpoint, body) {
  return new Promise((resolve, reject) => {
    const opts = {
      hostname: "api.github.com",
      path: endpoint,
      method,
      headers: {
        Authorization: `Bearer ${GH_TOKEN}`,
        "User-Agent": "DACX-Release",
        Accept: "application/vnd.github.v3+json",
        "X-GitHub-Api-Version": "2022-11-28",
      },
    };
    if (body) opts.headers["Content-Type"] = "application/json";

    const req = https.request(opts, (res) => {
      let data = "";
      res.on("data", (c) => (data += c));
      res.on("end", () => {
        try {
          const json = data ? JSON.parse(data) : {};
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(json);
          } else {
            reject(new Error(`GitHub ${res.statusCode}: ${json.message || data}`));
          }
        } catch {
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(data);
          } else {
            reject(new Error(`GitHub ${res.statusCode}: ${data || "Non-JSON error response"}`));
          }
        }
      });
    });
    req.on("error", reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

async function getOrCreateRelease() {
  try {
    return await ghRequest(
      "GET",
      `/repos/${REPO_OWNER}/${REPO_NAME}/releases/tags/${TAG}`,
    );
  } catch (err) {
    if (!String(err?.message ?? err).includes("404")) throw err;
  }

  try {
    const releases = await ghRequest(
      "GET",
      `/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=30`,
    );
    const draft = releases.find((r) => r.draft && r.tag_name === TAG);
    if (draft) return draft;
  } catch (err) {
    if (!String(err?.message ?? err).includes("404")) throw err;
  }

  return await ghRequest("POST", `/repos/${REPO_OWNER}/${REPO_NAME}/releases`, {
    tag_name: TAG,
    name: `DACX ${VERSION}`,
    draft: true,
    prerelease: IS_PRERELEASE,
  });
}

async function uploadAsset(uploadUrl, filePath) {
  const fileName = path.basename(filePath);
  const content = fs.readFileSync(filePath);
  const url = new URL(uploadUrl.replace("{?name,label}", ""));
  url.searchParams.set("name", fileName);

  const isText = /\.(asc|txt|json)$/i.test(fileName);

  await new Promise((resolve, reject) => {
    const req = https.request(
      {
        hostname: url.hostname,
        path: url.pathname + url.search,
        method: "POST",
        headers: {
          Authorization: `Bearer ${GH_TOKEN}`,
          "User-Agent": "DACX-Release",
          Accept: "application/vnd.github.v3+json",
          "Content-Type": isText ? "text/plain" : "application/octet-stream",
          "Content-Length": content.length,
        },
      },
      (res) => {
        let data = "";
        res.on("data", (c) => (data += c));
        res.on("end", () => {
          if (res.statusCode < 300) {
            resolve(true);
          } else if (res.statusCode === 422) {
            let detail = data;
            try {
              const parsed = JSON.parse(data);
              if (parsed && typeof parsed.message === "string") {
                detail = parsed.message;
              }
            } catch {}
            reject(
              new Error(
                `Upload ${fileName} was rejected (422): ${detail}. Remove the conflicting release asset and retry.`,
              ),
            );
          } else {
            reject(new Error(`Upload ${fileName} failed ${res.statusCode}: ${data}`));
          }
        });
      },
    );
    req.on("error", reject);
    req.write(content);
    req.end();
  });
}

async function listReleaseAssets(releaseId) {
  const assets = await ghRequest(
    "GET",
    `/repos/${REPO_OWNER}/${REPO_NAME}/releases/${releaseId}/assets?per_page=100`,
  );
  return Array.isArray(assets) ? assets : [];
}

async function uploadAssetWithReplace(release, filePath) {
  try {
    await uploadAsset(release.upload_url, filePath);
  } catch (err) {
    const message = err instanceof Error ? err.message : String(err);
    if (!message.includes("(422)")) throw err;

    const fileName = path.basename(filePath);
    const assets = await listReleaseAssets(release.id);
    const existing = assets.find(
      (a) => a?.name === fileName && typeof a.id === "number",
    );
    if (!existing) throw err;

    if (!release.draft && !ALLOW_ASSET_REPLACE) {
      throw new Error(
        `Refusing to replace existing asset "${fileName}" on published release ${TAG}. ` +
          "Set ALLOW_ASSET_REPLACE=true to override.",
      );
    }

    await ghRequest(
      "DELETE",
      `/repos/${REPO_OWNER}/${REPO_NAME}/releases/assets/${existing.id}`,
    );
    await uploadAsset(release.upload_url, filePath);
  }
}

// ── Main ─────────────────────────────────────────────────────

async function main() {
  console.log(`\nDACX ${VERSION} — release pipeline\n`);

  console.log("[1/4] Checking GPG...");
  if (!GPG_KEY_ID) {
    console.error("GPG_KEY_ID is required. Set it in your environment or .env file.");
    process.exit(1);
  }
  if (!GPG_PASSPHRASE) {
    console.error("GPG_PASSPHRASE is required. Set it in your environment or .env file.");
    process.exit(1);
  }
  try {
    execSync("gpg --version", { stdio: "pipe" });
  } catch {
    console.error("gpg not found. Install GnuPG and try again.");
    process.exit(1);
  }

  console.log("[2/4] Collecting artifacts...");
  const artifacts = collectArtifacts();

  console.log("[3/4] Generating checksums & signing...");
  const checksumFiles = generateChecksums(artifacts);
  const ascFiles = signArtifacts(artifacts);
  for (const checksumFile of checksumFiles) {
    ascFiles.push(signFile(checksumFile));
    console.log(`  + ${path.basename(checksumFile)}.asc`);
  }

  if (!GH_TOKEN) {
    console.log("\n[4/4] GH_TOKEN not set — skipping GitHub upload.");
    console.log(`Artifacts staged in: ${releaseDir}\n`);
    return;
  }

  console.log("[4/4] Uploading to GitHub...");
  const release = await getOrCreateRelease();
  console.log(`  Release: ${release.html_url || TAG}`);

  const everything = fs
    .readdirSync(releaseDir)
    .filter((name) => shouldUploadReleaseEntry(name))
    .map((n) => path.join(releaseDir, n));

  for (const f of everything) {
    await uploadAssetWithReplace(release, f);
    console.log(`  ^ ${path.basename(f)}`);
  }

  console.log(`\nDone — ${TAG} uploaded as ${release.draft ? "draft" : "published"}.\n`);
}

main().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
