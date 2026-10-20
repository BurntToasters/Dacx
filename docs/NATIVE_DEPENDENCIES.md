# Native runtime dependencies

Dacx ships as a Flutter desktop app with platform-specific native pieces. In
addition to the Dart packages listed in `build/THIRD_PARTY_NOTICES.txt`, builds
typically bundle or depend on:

| Component | Role | Typical license |
| --------- | ---- | ---------------- |
| **libmpv** (via media_kit) | Playback engine | GPLv2+ / LGPL (build-dependent) |
| **FFmpeg** (via libmpv) | Demux/decode | LGPL/GPL (build-dependent) |
| **Flutter engine** | UI runtime | BSD-style (see Flutter SDK) |
| **nativeapi** (Linux tray) | System tray via StatusNotifier over D-Bus | MIT |
| **Mozilla CA bundle** (`assets/cacert.pem`) | Extra TLS roots on Windows (with OS store) via `trusted_http.dart` | MPL-2.0 (Mozilla roots; see PEM header) |

Refresh the CA bundle from [curl.se’s CA extract](https://curl.se/docs/caextract.html) **manually** when you intend to (`npm run cacert:update`). The script validates the download before overwriting; it is **not** run automatically by `release:*`. Optional: `npm run check:cacert` (strict) or the advisory step in `test:all`.

## libmpv / FFmpeg pinning and refresh

Dacx plays files from anywhere, so the bundled decoders are security-relevant.

| Platform | Source | Pinned build |
| -------- | ------ | ------------ |
| Windows | `media_kit_libs_windows_video` from the official [media-kit](https://github.com/media-kit/media-kit) repository, pinned by commit in `pubspec.yaml` `dependency_overrides` | `mpv-dev-x86_64-20241021-git-0f78584.7z` (mpv v0.39.0-179, FFmpeg N-117622) |
| macOS | `media_kit_libs_macos_video` from the same commit | `libmpv-darwin-build` v0.7.2 |
| Linux | System libmpv (`.deb` depends on the distro package; the tarball and Flatpak vendor the build host's copy) | Refreshed with the release VM's distro updates |

The published pub.dev packages still bundle 2023 builds (FFmpeg n6.0), which is
why the override exists. Checks:

- `npm run check:native-libs` verifies the downloaded Windows archive against
  the SHA-256 in `scripts/check-native-libs.js` (upstream only checks MD5).
  Windows packaging runs it and fails on an unpinned or altered archive.
- `integration_test/libmpv_contract_test.dart` reads `ffmpeg-version` from the
  running library and fails on Windows/macOS when it is older than
  `NativeLibPolicy` (FFmpeg 7.1 or git revision 117622).
- After changing the pin, delete `build/windows/x64/libmpv` and old
  `mpv-dev-*.7z` files; the plugin does not re-extract over an existing folder.

Refresh routine (at least every six months, and on any FFmpeg security
advisory): move the override to a newer official media-kit commit, update the
SHA-256 pin and `NativeLibPolicy` minimums, run the contract and release smoke
tests on all three platforms, and update the table above. Use only official
media-kit sources; if Windows needs a newer build than media-kit publishes,
build it with media-kit's own `libmpv-win32-video-cmake` tooling and pin the
result the same way.

## Plugin health

| Package | Status | Plan |
| ------- | ------ | ---- |
| `anni_mpris_service` 0.1.0 | Last release 2022-09 (Linux media controls) | Replace with an in-repo MPRIS service on the existing `dbus` package when it next needs changes. |
| `flutter_acrylic` 1.1.4 | Last release 2024-06 (window blur) | Keep while it works; macOS blur already uses `macos_window_utils` directly. |
| `tray_manager` 0.7.0 | 0.8.0 (2026-10-08) changes the API and adds C build hooks | Adopt after it has aged and the tray code is migrated. |
| `dbus` 0.7.x | 0.8 blocked by `desktop_drop`'s constraint | Move when `desktop_drop` allows it. |

Preferences on Windows and Linux are one JSON file rewritten in place by
`shared_preferences`. Dacx moves an unreadable file aside at startup
(`PreferencesRecovery`) and keeps high-churn resume positions in its own
atomically written, merge-on-write `resume_positions.json`. With multiple
instances, other settings still follow last-writer-wins.

## Linux packaging notes

`media_kit_video` **links** libmpv (`DT_NEEDED`). Official **AppImage, tar, and
Flatpak** builds copy `libmpv.so.2` and its non-system DT_NEEDED deps (FFmpeg,
libass, …) into `bundle/lib` and set `$ORIGIN` RPATH so the loader finds them
without a host SONAME. **deb / rpm** do **not** vendor those libs; they declare
Depends/`Requires` on distro `libmpv2` / `mpv-libs`. GTK, X11/XI, glibc, D-Bus,
and GPU/audio server libraries stay on the host (or the Flatpak runtime).
`flutter run` / unpackaged bundles still need host libmpv.

If a portable artifact is missing its vendored copy, the process can still
abort in the dynamic loader before Dart. The in-app “Playback engine not found”
screen appears when the process starts and `MediaKit.ensureInitialized` fails.

| Package | libmpv | Tray (StatusNotifier) |
| ------- | ------ | -------------------- |
| **AppImage / tar.gz** | **Bundled** into `bundle/lib` (`libmpv.so.2` + playback deps) | Host GTK/D-Bus panel provides tray host |
| **Flatpak** | **Bundled** into `/app/lib/dacx/lib` (same vendor pass as AppImage/tar) | `--talk-name=org.kde.StatusNotifierWatcher` permission |
| **deb / rpm** | Declared Depends/`Requires` on `libmpv2` / `mpv-libs` | Host GTK/D-Bus panel provides tray host |

### Building from source (apt)

`npm run setup` (Linux) and CI install `libmpv-dev`, `libgtk-3-dev`,
`libx11-dev`, `libxi-dev`, and `patchelf` so plugins link and portable packages
can vendor the SONAMEs. That is why CI never sees a missing-SONAME launch
failure for unpackaged `flutter test` builds.

Linux **Flatpak** builds use the Freedesktop Platform/SDK runtimes (GTK, Mesa,
PulseAudio/PipeWire, etc.) from Flathub for the sandbox, plus the vendored
libmpv tree from the Linux bundle. Flatpak is GitHub sideload only (not
published on Flathub).

Windows/macOS **release bundles** include the Flutter engine and media_kit
prebuilt libraries produced by `flutter build`. Exact versions match the pinned
Flutter SDK (`.fvmrc`) and `pubspec.lock` at build time.

Flutter's macOS Swift Package Manager path may warn when a third-party plugin
does not yet publish SwiftPM metadata. Dacx currently relies on Flutter's
CocoaPods fallback for `media_kit_video` / `media_kit_libs_macos_video`; this is
expected until those upstream plugins add SwiftPM support. Build smoke checks
may allow that warning, but a SwiftPM build error is release-blocking.

Windows release artifacts also bundle required MSVC runtime files
(`vcruntime`/`msvcp`) app-local so clean machines can launch without manually
installing the Visual C++ Redistributable first.

For the full text of third-party Dart/Flutter package licenses, see
`THIRD_PARTY_NOTICES.txt` in the release artifact or run `npm run licenses` when
building from source.
