import assert from "node:assert/strict";
import { test } from "node:test";

import {
  assertLibmpvVendored,
  collectCopyPlan,
  ensureBinaryLibRpath,
  isSystemLib,
  ensureBinaryRpath,
  parseLddOutput,
} from "./bundle-linux-native-libs.js";

test("treats glibc, GTK, and GPU driver libs as system", () => {
  assert.equal(isSystemLib("libc.so.6"), true);
  assert.equal(isSystemLib("libstdc++.so.6"), true);
  assert.equal(isSystemLib("libgtk-3.so.0"), true);
  assert.equal(isSystemLib("libGL.so.1"), true);
  assert.equal(isSystemLib("libnvidia-glcore.so.1"), true);
  assert.equal(isSystemLib("ld-linux-x86-64.so.2"), true);
});

test("treats desktop text/crypto/mount libs as system (runtime provides them)", () => {
  assert.equal(isSystemLib("libfontconfig.so.1"), true);
  assert.equal(isSystemLib("libfreetype.so.6"), true);
  assert.equal(isSystemLib("libharfbuzz.so.0"), true);
  assert.equal(isSystemLib("libharfbuzz-subset.so.0"), true);
  assert.equal(isSystemLib("libpcre2-8.so.0"), true);
  assert.equal(isSystemLib("libffi.so.8"), true);
  assert.equal(isSystemLib("libmount.so.1"), true);
  assert.equal(isSystemLib("libblkid.so.1"), true);
  assert.equal(isSystemLib("libssl.so.3"), true);
  assert.equal(isSystemLib("libcrypto.so.3"), true);
  assert.equal(isSystemLib("libcurl.so.4"), true);
  assert.equal(isSystemLib("libexpat.so.1"), true);
  assert.equal(isSystemLib("libz.so.1"), true);
  assert.equal(isSystemLib("libdbus-1.so.3"), true);
});

test("does not treat libmpv or FFmpeg as system", () => {
  assert.equal(isSystemLib("libmpv.so.2"), false);
  assert.equal(isSystemLib("libavcodec.so.61"), false);
  assert.equal(isSystemLib("libayatana-appindicator3.so.1"), false);
  assert.equal(isSystemLib("libass.so.9"), false);
});

test("parseLddOutput maps sonames, skips vdso, flags not-found", () => {
  const deps = parseLddOutput(`
	linux-vdso.so.1 (0x00007ffe)
	libmpv.so.2 => /lib/x86_64-linux-gnu/libmpv.so.2 (0x0001)
	libavcodec.so.61 => /lib/x86_64-linux-gnu/libavcodec.so.61 (0x0002)
	libmissing.so.1 => not found
	libc.so.6 => /lib/x86_64-linux-gnu/libc.so.6 (0x0003)
	/lib64/ld-linux-x86-64.so.2 (0x0004)
`);
  assert.deepEqual(
    deps.map((d) => d.soname),
    [
      "libmpv.so.2",
      "libavcodec.so.61",
      "libmissing.so.1",
      "libc.so.6",
      "ld-linux-x86-64.so.2",
    ],
  );
  assert.equal(
    deps.find((d) => d.soname === "libmpv.so.2").resolved,
    "/lib/x86_64-linux-gnu/libmpv.so.2",
  );
  assert.equal(deps.find((d) => d.soname === "libmissing.so.1").resolved, null);
});

test("collectCopyPlan walks ldd, skips system and already-bundled names", () => {
  const lddMap = {
    "/bundle/dacx": `
	libflutter_linux_gtk.so => /bundle/lib/libflutter_linux_gtk.so (0x1)
	libmpv.so.2 => /usr/lib/libmpv.so.2 (0x2)
	libc.so.6 => /lib/libc.so.6 (0x3)
`,
    "/usr/lib/libmpv.so.2": `
	libavcodec.so.61 => /usr/lib/libavcodec.so.61 (0x1)
	libc.so.6 => /lib/libc.so.6 (0x2)
`,
    "/usr/lib/libavcodec.so.61": `
	libc.so.6 => /lib/libc.so.6 (0x1)
`,
  };
  const plan = collectCopyPlan({
    seeds: ["/bundle/dacx"],
    existingNames: ["libflutter_linux_gtk.so"],
    ldd: (file) => lddMap[file] || "",
  });
  assert.deepEqual(
    plan.toCopy.map((e) => e.soname).sort(),
    ["libavcodec.so.61", "libmpv.so.2"],
  );
  assert.deepEqual(plan.missing, []);
});

test("collectCopyPlan records unresolved non-system deps", () => {
  const plan = collectCopyPlan({
    seeds: ["/plugin.so"],
    existingNames: [],
    ldd: () => "\tlibmpv.so.2 => not found\n",
  });
  assert.deepEqual(plan.toCopy, []);
  assert.deepEqual(plan.missing, ["libmpv.so.2"]);
});

test("assertLibmpvVendored accepts a copy plan or an already-bundled SONAME", () => {
  assert.doesNotThrow(() =>
    assertLibmpvVendored({
      existingNames: [],
      toCopy: [{ soname: "libmpv.so.2", source: "/usr/lib/libmpv.so.2" }],
    }),
  );
  assert.doesNotThrow(() =>
    assertLibmpvVendored({
      existingNames: ["libmpv.so.2"],
      toCopy: [],
    }),
  );
  assert.throws(
    () => assertLibmpvVendored({ existingNames: ["libfoo.so"], toCopy: [] }),
    /libmpv\.so\.2/,
  );
});

test("treats font, text-stack, and container libs as system", () => {
  for (const name of [
    "libfontconfig.so.1",
    "libfreetype.so.6",
    "libharfbuzz.so.0",
    "libharfbuzz-subset.so.0",
    "libfribidi.so.0",
    "libgraphite2.so.3",
    "libthai.so.0",
    "libdatrie.so.1",
    "libpcre2-8.so.0",
    "libffi.so.8",
    "libexpat.so.1",
    "libpng16.so.16",
    "libpixman-1.so.0",
    "libbrotlidec.so.1",
    "libbrotlicommon.so.1",
  ]) {
    assert.equal(isSystemLib(name), true, name);
  }
});

test("treats mount, TLS, compression, and IPC libs as system", () => {
  for (const name of [
    "libmount.so.1",
    "libblkid.so.1",
    "libuuid.so.1",
    "libselinux.so.1",
    "libssl.so.3",
    "libcrypto.so.3",
    "liblzma.so.5",
    "libzstd.so.1",
    "libz.so.1",
    "libdbus-1.so.3",
    "libICE.so.6",
    "libSM.so.6",
    "libxkbfile.so.1",
    "libudev.so.1",
    "libsystemd.so.0",
    "libcap.so.2",
    "libgcrypt.so.20",
    "libgpg-error.so.0",
    "liblz4.so.1",
    "libcurl.so.4",
    "libnghttp2.so.14",
    "libpsl.so.5",
    "libxml2.so.2",
    "libsqlite3.so.0",
    "libxcb-render.so.0",
    "libxcb-shm.so.0",
    "libxcb-shape.so.0",
    "libxcb-xkb.so.1",
    "libxcb-icccm.so.4",
    "libxcb-image.so.0",
    "libxcb-keysyms.so.1",
    "libxcb-util.so.1",
    "libxcb-cursor.so.0",
  ]) {
    assert.equal(isSystemLib(name), true, name);
  }
});

test("keeps media and helper libs vendored", () => {
  for (const name of [
    "libmpv.so.2",
    "libavcodec.so.61",
    "libavformat.so.61",
    "libavutil.so.59",
    "libswscale.so.8",
    "libswresample.so.5",
    "libass.so.9",
    "libplacebo.so.349",
    "libluajit-5.1.so.2",
    "libuchardet.so.0",
    "librubberband.so.2",
    "libarchive.so.13",
    "libvulkan.so.1",
    "libva.so.2",
  ]) {
    assert.equal(isSystemLib(name), false, name);
  }
});

test("ensureBinaryRpath adds $ORIGIN/lib to the launcher binary", () => {
  const calls = [];
  const patchelf = (args) => {
    calls.push(args);
    if (args[0] === "--print-rpath") {
      return { status: 0, stdout: "", stderr: "" };
    }
    return { status: 0, stdout: "", stderr: "" };
  };
  const next = ensureBinaryRpath("/bundle/dacx", { patchelf });
  assert.equal(next, "$ORIGIN/lib");
  assert.deepEqual(calls[1], ["--set-rpath", "$ORIGIN/lib", "/bundle/dacx"]);
});

test("ensureBinaryRpath keeps an existing binary rpath", () => {
  const calls = [];
  const patchelf = (args) => {
    calls.push(args);
    if (args[0] === "--print-rpath") {
      return { status: 0, stdout: "$ORIGIN/lib", stderr: "" };
    }
    return { status: 0, stdout: "", stderr: "" };
  };
  assert.equal(
    ensureBinaryRpath("/bundle/dacx", { patchelf }),
    "$ORIGIN/lib",
  );
  assert.equal(calls.length, 1);
});

test("collectCopyPlan skips desktop-stack libs from the media closure", () => {
  const plan = collectCopyPlan({
    seeds: ["/bundle/dacx"],
    existingNames: [],
    ldd: () => `
\tlibmpv.so.2 => /usr/lib/libmpv.so.2 (0x1)
\tlibfontconfig.so.1 => /usr/lib/libfontconfig.so.1 (0x2)
\tlibfreetype.so.6 => /usr/lib/libfreetype.so.6 (0x3)
\tlibssl.so.3 => /usr/lib/libssl.so.3 (0x4)
\tlibc.so.6 => /lib/libc.so.6 (0x5)
`,
  });
  assert.deepEqual(
    plan.toCopy.map((e) => e.soname),
    ["libmpv.so.2"],
  );
});

test("ensureBinaryLibRpath adds $ORIGIN/lib without dropping existing entries", () => {
  let current = "/app/lib";
  const calls = [];
  const fake = (args) => {
    calls.push(args);
    if (args[0] === "--print-rpath") {
      return { status: 0, stdout: `${current}\n`, stderr: "" };
    }
    current = args[1];
    return { status: 0, stdout: "", stderr: "" };
  };
  const next = ensureBinaryLibRpath("/bundle/dacx", { patchelf: fake });
  assert.equal(next, "/app/lib:$ORIGIN/lib");
  const again = ensureBinaryLibRpath("/bundle/dacx", { patchelf: fake });
  assert.equal(again, "/app/lib:$ORIGIN/lib");
  assert.equal(calls.filter((c) => c[0] === "--set-rpath").length, 1);
});
