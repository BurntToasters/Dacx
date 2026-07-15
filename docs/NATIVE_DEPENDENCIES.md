# Native runtime dependencies

Dacx ships as a Flutter desktop app with platform-specific native pieces. In
addition to the Dart packages listed in `build/THIRD_PARTY_NOTICES.txt`, builds
typically bundle or depend on:

| Component | Role | Typical license |
| --------- | ---- | ---------------- |
| **libmpv** (via media_kit) | Playback engine | GPLv2+ / LGPL (build-dependent) |
| **FFmpeg** (via libmpv) | Demux/decode | LGPL/GPL (build-dependent) |
| **Flutter engine** | UI runtime | BSD-style (see Flutter SDK) |
| **libayatana-appindicator** (Linux tray) | System tray via `tray_manager` | LGPL |

## Linux packaging notes

| Package | libmpv | Tray (appindicator) |
| ------- | ------ | ------------------- |
| **AppImage / Flatpak** | Bundled with the Flutter release tree via `media_kit_libs_linux` (see `LD_LIBRARY_PATH` in the Flatpak launcher) | Bundled / linked from the build host where possible; tray still needs a StatusNotifier/AppIndicator host |
| **deb / rpm** | System package (`libmpv2` / `mpv-libs`) | Runtime Depends/`Requires` on ayatana/appindicator shared libraries |

### Building from source (apt)

`npm run setup` (Linux) and CI install `libmpv-dev` and
`libayatana-appindicator3-dev` so `tray_manager` can compile against AppIndicator.

Linux **Flatpak** builds use the Freedesktop Platform/SDK runtimes (GTK, Mesa,
PulseAudio/PipeWire, etc.) from Flathub for the sandbox; they do **not** pull
libmpv from Flathub as a separate module. Playback libraries come from the
copied Flutter bundle. Flatpak is GitHub sideload only (not published on Flathub).

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
