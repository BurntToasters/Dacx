#!/usr/bin/env node
/**
 * Vendors libmpv (and non-system DT_NEEDED deps, including ayatana) into a
 * Flutter Linux bundle's lib/ directory so AppImage / tar / Flatpak can
 * start without a host libmpv.so.2.
 *
 * deb/rpm keep using the unvendored bundle and declare distro Depends.
 */
import fs from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";

/** Host/driver/GTK stack — must come from the OS or Flatpak runtime. */
const SYSTEM_LIB_NAMES = new Set([
  "linux-vdso.so.1",
  "ld-linux-x86-64.so.2",
  "ld-linux-aarch64.so.1",
  "libc.so.6",
  "libm.so.6",
  "libdl.so.2",
  "libpthread.so.0",
  "librt.so.1",
  "libresolv.so.2",
  "libutil.so.1",
  "libanl.so.1",
  "libgcc_s.so.1",
  "libstdc++.so.6",
  "libglib-2.0.so.0",
  "libgobject-2.0.so.0",
  "libgio-2.0.so.0",
  "libgmodule-2.0.so.0",
  "libgthread-2.0.so.0",
  "libgtk-3.so.0",
  "libgdk-3.so.0",
  "libgdk_pixbuf-2.0.so.0",
  "libpango-1.0.so.0",
  "libpangocairo-1.0.so.0",
  "libpangoft2-1.0.so.0",
  "libcairo.so.2",
  "libcairo-gobject.so.2",
  "libatk-1.0.so.0",
  "libatk-bridge-2.0.so.0",
  "libatspi.so.0",
  "libepoxy.so.0",
  "libfontconfig.so.1",
  "libfreetype.so.6",
  "libharfbuzz.so.0",
  "libharfbuzz-subset.so.0",
  "libfribidi.so.0",
  "libpcre2-8.so.0",
  "libpcre2-16.so.0",
  "libpcre2-32.so.0",
  "libffi.so.8",
  "libmount.so.1",
  "libblkid.so.1",
  "libuuid.so.1",
  "libselinux.so.1",
  "libexpat.so.1",
  "libssl.so.3",
  "libcrypto.so.3",
  "libcurl.so.4",
  "libnghttp2.so.14",
  "libpsl.so.5",
  "libxml2.so.2",
  "libsqlite3.so.0",
  "libz.so.1",
  "liblzma.so.5",
  "libzstd.so.1",
  "liblz4.so.1",
  "libbrotlidec.so.1",
  "libbrotlicommon.so.1",
  "libdbus-1.so.0",
  "libdbus-1.so.3",
  "libgpg-error.so.0",
  "libgcrypt.so.20",
  "libgssapi_krb5.so.2",
  "libkrb5.so.3",
  "libk5crypto.so.3",
  "libcom_err.so.2",
  "libkeyutils.so.1",
  "libldap.so.2",
  "liblber.so.2",
  "libsasl2.so.2",
  "libssh.so.4",
  "libunistring.so.2",
  "libidn2.so.0",
  "libGL.so.1",
  "libEGL.so.1",
  "libGLdispatch.so.0",
  "libGLX.so.0",
  "libOpenGL.so.0",
  "libdrm.so.2",
  "libgbm.so.1",
  "libasound.so.2",
  "libpulse.so.0",
  "libpulse-simple.so.0",
  "libpipewire-0.3.so.0",
  "libwayland-client.so.0",
  "libwayland-cursor.so.0",
  "libwayland-egl.so.1",
  "libwayland-server.so.0",
  "libX11.so.6",
  "libX11-xcb.so.1",
  "libXext.so.6",
  "libXau.so.6",
  "libXdmcp.so.6",
  "libXcomposite.so.1",
  "libXcursor.so.1",
  "libXdamage.so.1",
  "libXfixes.so.3",
  "libXi.so.6",
  "libXinerama.so.1",
  "libXrandr.so.2",
  "libXrender.so.1",
  "libXss.so.1",
  "libXtst.so.6",
  "libxcb.so.1",
  "libxcb-dri2.so.0",
  "libxcb-dri3.so.0",
  "libxcb-present.so.0",
  "libxcb-sync.so.1",
  "libxcb-xfixes.so.0",
  "libxkbcommon.so.0",
  "libxkbcommon-x11.so.1",
  "libxkbfile.so.1",
  "libICE.so.6",
  "libSM.so.6",
  "libgraphite2.so.3",
  "libthai.so.0",
  "libdatrie.so.1",
  "libpng16.so.16",
  "libjpeg.so.8",
  "libpixman-1.so.0",
  "libudev.so.1",
  "libsystemd.so.0",
  "libcap.so.2",
  "libxcb-render.so.0",
  "libxcb-shm.so.0",
  "libxcb-shape.so.0",
  "libxcb-xkb.so.1",
  "libxcb-icccm.so.4",
  "libxcb-image.so.0",
  "libxcb-keysyms.so.1",
  "libxcb-render-util.so.0",
  "libxcb-util.so.1",
  "libxcb-cursor.so.0",
]);

const SYSTEM_LIB_PREFIXES = [
  "ld-linux",
  "linux-vdso",
  "libnss_",
  "libnvidia",
  "libcuda",
  "libharfbuzz",
  "libpcre2",
  "libffi.so",
  "libmount.so",
  "libblkid.so",
  "libselinux.so",
  "libfontconfig.so",
  "libfreetype.so",
  "libfribidi.so",
  "libssl.so",
  "libcrypto.so",
  "libcurl.so",
  "libxml2.so",
  "libsqlite3.so",
  "libdbus-1.so",
];

const REQUIRED_SONAMES = ["libmpv.so.2", "libmpv.so"];

export function isSystemLib(soname) {
  const base = path.basename(String(soname || "").trim());
  if (!base) return true;
  if (SYSTEM_LIB_NAMES.has(base)) return true;
  return SYSTEM_LIB_PREFIXES.some((prefix) => base.startsWith(prefix));
}

export function parseLddOutput(text) {
  const deps = [];
  for (const raw of String(text || "").split("\n")) {
    const line = raw.trim();
    if (!line) continue;
    if (line.includes("linux-vdso")) continue;
    const notFound = line.match(/^(\S+)\s+=>\s+not found$/);
    if (notFound) {
      deps.push({ soname: notFound[1], resolved: null });
      continue;
    }
    const mapped = line.match(/^(\S+)\s+=>\s+(\S+)\s+\(/);
    if (mapped) {
      deps.push({ soname: mapped[1], resolved: mapped[2] });
      continue;
    }
    const loader = line.match(/^(\/\S+)\s+\(/);
    if (loader) {
      deps.push({
        soname: path.basename(loader[1]),
        resolved: loader[1],
      });
    }
  }
  return deps;
}

export function collectCopyPlan({
  seeds,
  existingNames = [],
  ldd,
} = {}) {
  if (typeof ldd !== "function") {
    throw new Error("collectCopyPlan requires an ldd(file) function");
  }
  const seen = new Set(
    existingNames.map((name) => path.basename(String(name))),
  );
  const toCopy = [];
  const missing = [];
  const queue = [...(seeds || [])];

  while (queue.length > 0) {
    const file = queue.pop();
    const deps = parseLddOutput(ldd(file));
    for (const dep of deps) {
      if (isSystemLib(dep.soname)) continue;
      if (seen.has(dep.soname)) continue;
      if (!dep.resolved) {
        missing.push(dep.soname);
        seen.add(dep.soname);
        continue;
      }
      seen.add(dep.soname);
      toCopy.push({ soname: dep.soname, source: dep.resolved });
      queue.push(dep.resolved);
    }
  }

  return { toCopy, missing };
}

export function assertLibmpvVendored({ existingNames = [], toCopy = [] } = {}) {
  const names = new Set([
    ...existingNames.map((name) => path.basename(String(name))),
    ...toCopy.map((entry) => entry.soname),
  ]);
  const hasMpv = REQUIRED_SONAMES.some((name) => names.has(name));
  if (!hasMpv) {
    throw new Error(
      "Portable Linux packages need libmpv.so.2 in bundle/lib. " +
        "Install libmpv-dev on the build host and rebuild.",
    );
  }
}

export function defaultLdd(file) {
  const result = spawnSync("ldd", [file], {
    encoding: "utf8",
    windowsHide: true,
  });
  if (result.error) {
    throw new Error(`ldd failed to start: ${result.error.message}`);
  }
  if (result.status !== 0) {
    throw new Error(
      `ldd ${file} failed: ${(result.stderr || result.stdout || "").trim()}`,
    );
  }
  return result.stdout || "";
}

function listSharedObjects(libDir) {
  if (!fs.existsSync(libDir)) return [];
  return fs
    .readdirSync(libDir)
    .filter((name) => name.includes(".so"))
    .map((name) => path.join(libDir, name));
}

function copyLibrary(source, destPath) {
  const real = fs.realpathSync(source);
  fs.copyFileSync(real, destPath);
  fs.chmodSync(destPath, 0o755);
}

export function ensureOriginRpath(file, { patchelf } = {}) {
  const run =
    patchelf ||
    ((args) =>
      spawnSync("patchelf", args, { encoding: "utf8", windowsHide: true }));
  const printed = run(["--print-rpath", file]);
  if (printed.status !== 0) {
    throw new Error(
      `patchelf --print-rpath ${file} failed: ${(printed.stderr || "").trim()}`,
    );
  }
  const current = (printed.stdout || "").trim();
  if (current.split(":").includes("$ORIGIN")) return current;
  const next = current ? `${current}:$ORIGIN` : "$ORIGIN";
  const set = run(["--set-rpath", next, file]);
  if (set.status !== 0) {
    throw new Error(
      `patchelf --set-rpath ${file} failed: ${(set.stderr || "").trim()}`,
    );
  }
  return next;
}

export function ensureBinaryRpath(binary, { patchelf } = {}) {
  const run =
    patchelf ||
    ((args) =>
      spawnSync("patchelf", args, { encoding: "utf8", windowsHide: true }));
  const printed = run(["--print-rpath", binary]);
  if (printed.status !== 0) {
    throw new Error(
      `patchelf --print-rpath ${binary} failed: ${(printed.stderr || "").trim()}`,
    );
  }
  const current = (printed.stdout || "").trim();
  if (current.split(":").includes("$ORIGIN/lib")) return current;
  const next = current ? `${current}:$ORIGIN/lib` : "$ORIGIN/lib";
  const set = run(["--set-rpath", next, binary]);
  if (set.status !== 0) {
    throw new Error(
      `patchelf --set-rpath ${binary} failed: ${(set.stderr || "").trim()}`,
    );
  }
  return next;
}

export function ensureBinaryLibRpath(binary, { patchelf } = {}) {
  const run =
    patchelf ||
    ((args) =>
      spawnSync("patchelf", args, { encoding: "utf8", windowsHide: true }));
  const printed = run(["--print-rpath", binary]);
  if (printed.status !== 0) {
    throw new Error(
      `patchelf --print-rpath ${binary} failed: ${(printed.stderr || "").trim()}`,
    );
  }
  const current = (printed.stdout || "").trim();
  const parts = current ? current.split(":") : [];
  if (parts.includes("$ORIGIN/lib") || parts.includes("$ORIGIN/$ORIGIN/lib")) {
    return current;
  }
  const next = current ? `${current}:$ORIGIN/lib` : "$ORIGIN/lib";
  const set = run(["--set-rpath", next, binary]);
  if (set.status !== 0) {
    throw new Error(
      `patchelf --set-rpath ${binary} failed: ${(set.stderr || "").trim()}`,
    );
  }
  return next;
}

/**
 * Copy host libmpv (and other non-system plugin deps) into [bundleDir]/lib
 * and set `$ORIGIN` RPATH so tar/AppImage/Flatpak resolve DT_NEEDED locally.
 */
export function vendorLinuxNativeLibs(
  bundleDir,
  {
    ldd = defaultLdd,
    patchelf,
    skipPatchelf = false,
    log = console.log,
  } = {},
) {
  const libDir = path.join(bundleDir, "lib");
  const binary = path.join(bundleDir, "dacx");
  if (!fs.existsSync(libDir) || !fs.existsSync(binary)) {
    throw new Error(
      `Linux bundle is missing dacx or lib/: ${bundleDir}`,
    );
  }

  const existingNames = fs.readdirSync(libDir);
  const seeds = [binary, ...listSharedObjects(libDir)];
  const plan = collectCopyPlan({
    seeds,
    existingNames,
    ldd,
  });
  assertLibmpvVendored({ existingNames, toCopy: plan.toCopy });
  if (plan.missing.length > 0) {
    throw new Error(
      `Cannot vendor Linux native libs; ldd reported missing: ${plan.missing.join(", ")}`,
    );
  }

  const copied = [];
  for (const entry of plan.toCopy) {
    const dest = path.join(libDir, entry.soname);
    copyLibrary(entry.source, dest);
    copied.push(entry.soname);
  }

  if (!skipPatchelf) {
    for (const file of listSharedObjects(libDir)) {
      ensureOriginRpath(file, { patchelf });
    }
    ensureBinaryRpath(binary, { patchelf });
  }

  if (typeof log === "function") {
    log(
      `  ✓ Vendored ${copied.length} native librar${copied.length === 1 ? "y" : "ies"} into ${path.basename(bundleDir)}/lib (libmpv + deps)`,
    );
  }
  return { copied, libDir };
}
