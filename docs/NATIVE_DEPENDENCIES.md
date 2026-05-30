# Native runtime dependencies

Dacx ships as a Flutter desktop app with platform-specific native pieces. In
addition to the Dart packages listed in `build/THIRD_PARTY_NOTICES.txt`, builds
typically bundle or depend on:

| Component | Role | Typical license |
| --------- | ---- | ---------------- |
| **libmpv** (via media_kit) | Playback engine | GPLv2+ / LGPL (build-dependent) |
| **FFmpeg** (via libmpv) | Demux/decode | LGPL/GPL (build-dependent) |
| **Flutter engine** | UI runtime | BSD-style (see Flutter SDK) |

Linux **Flatpak** builds use the Freedesktop Platform/SDK runtimes (GTK, Mesa,
PulseAudio/PipeWire, etc.) from Flathub; those licenses are not duplicated here.

Windows/macOS **release bundles** include the Flutter engine and media_kit
prebuilt libraries produced by `flutter build`. Exact versions match the pinned
Flutter SDK (`.fvmrc`) and `pubspec.lock` at build time.

Windows release artifacts also bundle required MSVC runtime files
(`vcruntime`/`msvcp`) app-local so clean machines can launch without manually
installing the Visual C++ Redistributable first.

For the full text of third-party Dart/Flutter package licenses, see
`THIRD_PARTY_NOTICES.txt` in the release artifact or run `npm run licenses` when
building from source.
