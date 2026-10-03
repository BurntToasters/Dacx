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
