# Dacx: Cross-Platform Music and Video Player

Fast, lightweight, open source media player for Windows, macOS, and Linux.

Built with Flutter + [media_kit](https://github.com/media-kit/media-kit) (libmpv).

[![Latest Release](https://img.shields.io/github/v/release/BurntToasters/Dacx?display_name=tag&label=release)](https://github.com/BurntToasters/Dacx/releases/latest)
[![Downloads](https://img.shields.io/github/downloads/BurntToasters/Dacx/total?label=downloads)](https://github.com/BurntToasters/Dacx/releases)
[![Tests](https://img.shields.io/github/actions/workflow/status/BurntToasters/Dacx/test.yml?branch=main&label=tests)](https://github.com/BurntToasters/Dacx/actions/workflows/test.yml)
[![License: GPLv3](https://img.shields.io/github/license/BurntToasters/Dacx)](LICENSE)

Dacx is a desktop music and video player focused on speed and low overhead, with modern playback controls, media session integration, and broad format support.

<div align="center">
  <table>
    <tr>
      <td valign="middle" align="center" width="220">
        <img src="assets/icon/icon.png"
             alt="Dacx logo" width="140" />
      </td>
      <td valign="middle" align="center">
        <p align="center">
  <img width="85%" height="1012" alt="Dacx screenshot" src="assets/screenshots/dacx_sc.png" />
&nbsp;
</p>
      </td>
    </tr>
  </table>
</div>

<h1 align="center">⬇️ Download Dacx</h1>
<p align="center">Need assistance? Check out the <b><u><a href="./docs/INSTALL.md">Installation Documentation</a></u></b>!</p>
<div align="center">
  
| <img height="20" src="https://github.com/user-attachments/assets/340d360e-79b1-4c70-bfab-d944085f75df" /> Windows | <img height="20" src="https://github.com/user-attachments/assets/42d7e887-4616-4e8c-b1d3-e44e01340f8c" /> MacOS | <img height="20" src="https://github.com/user-attachments/assets/e0cc4f33-4516-408b-9c5c-be71a3ac316b" /> Linux |
| :--- | :--- | :--- |
| **MSI:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.msi) | **DMG:** [Universal](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-macOS.dmg) | **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.AppImage) |
| | **ZIP:** [Universal](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-macOS.zip) | **DEB:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-amd64.deb) |
| | | **RPM:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.rpm) |
| | | **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.flatpak) |
| | | **TAR.GZ:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.tar.gz) |

</div>

## Platforms

- Windows
- macOS
- Linux

## Features

- Audio + video playback for MP3, FLAC, WAV, OGG, AAC, Opus, MP4, MKV, AVI, WebM, and more (anything libmpv handles).
- Playlist files (`.m3u` / `.pls` import + save queue as `.m3u`); HLS `.m3u8` streams via mpv.
- Playback speed control (transport chip + `[` / `]` / `\` shortcuts).
- External audio / subtitle track load from the more menu.
- 10-band equalizer with presets.
- Optional multi-audio-track mixing via `lavfi-complex` (Experimental Features; unstable).
- Optional seek thumbnails (Playback settings; uses extra memory).
- Window transparency / background blur on Windows and macOS (Appearance settings). Linux compositor blur remains experimental.
- Resume a file from its previous position when you reopen it; relaunch starts at the empty home screen.
- Compact mode and always-on-top window.
- System media-session integration: lock-screen / Now Playing / SMTC / MPRIS controls, artwork, rate, and scrubbing.
- File associations + custom document icon on Windows, macOS, and Linux.
- Built-in update checker: in-app self-update on **Windows (MSI)** and **macOS** (`/Applications`). On **Linux**, prefer the **AppImage** managed with [AppManager](https://github.com/kem-a/AppManager) for install + updates (no in-app Linux installer).
- Notarized & signed DMG/ZIP for macOS; Windows/Linux packages carry **GPG** detached signatures. Windows MSI is not Authenticode-signed by default (SmartScreen may warn); optional Authenticode is a release-machine concern (see `SECURITY.md`).

## Support contract (v1 readiness)

- **UI language:** English only (`lib/l10n`).
- **macOS:** 15 (Sequoia) or newer.
- **CPU arch:** Windows/Linux ship **x64** only (arm64 not a priority).
- **Linux (recommended):** [AppImage](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.AppImage) + [AppManager](https://github.com/kem-a/AppManager) for desktop install and updates. deb/rpm/Flatpak/tar remain available; Flatpak is GitHub-sideload only (not Flathub).
- **Experimental Features:** Long-lived opt-in lane (off by default) for unfinished / in-progress ideas (multi-audio mix, Linux compositor blur, …). Features may graduate to stable settings (like Win/mac blur) or stay experimental indefinitely; not a blocker for `1.0`.
- **Windows portable ZIP:** No longer shipped; use the MSI.

## Development

> [!NOTE]
> This project uses Flutter/Dart but also NodeJS. Its a little bit messy and not the best of practices I know, im just the most familiar and confident with js scripting and node so thats how the project is controlled. Sorry :P

```bash
# Install Node.js dependencies (build scripts)
npm install

# Install Flutter dependencies through FVM
fvm flutter pub get

# Run in development mode
npm run dev

# Run tests
npm run test:all

# Build for current platform
npm run build:win   # Windows
npm run build:mac   # macOS
npm run build:linux # Linux
```

### Signing model

Only the macOS build is code-signed end-to-end (Apple Developer ID + notarization). Windows MSIs and Linux DEB/RPM/TAR.GZ artifacts are signed with a **GPG detached signature** (the project's release key). Default GitHub Windows MSIs are not Authenticode-signed, so SmartScreen may warn; Ed25519 remains the primary self-update trust, and optional Authenticode is an additional release-machine pin (see `SECURITY.md`).

This means:

- `scripts/flutter-build-macos.js` requires `APPLE_TEAM_ID` in `.env`. Self-update pins against the team id. Set `DACX_BUILD_DEV_NO_TEAM_ID=1` to skip for local dev:
  ```bash
  DACX_BUILD_DEV_NO_TEAM_ID=1 npm run build:mac
  ```
- `scripts/flutter-build-windows.js` accepts `WINDOWS_SIGNING_CERT_THUMBPRINT` (or `DACX_WINDOWS_SIGNER_THUMBPRINT`) *optionally*. If unset, the MSI is unsigned at the OS level and **self-update trust is the Ed25519-signed update manifest** (Authenticode is not required). When set, the MSI is Authenticode-signed and the thumbprint is baked in as an **extra** runtime pin. On **release VMs that have a cert**, set the thumbprint and `DACX_REQUIRE_WINDOWS_SIGNER=1` so `npm run build:win` fails if it is missing (see `SECURITY.md`). The Windows build also ships `dacx-update-helper.exe` next to `dacx.exe` for post-exit MSI install (no on-disk PowerShell watchdog scripts).
- `scripts/flutter-build-linux` is not affected by either.

### macOS support

The macOS build targets **macOS 15 (Sequoia) or newer**. Older macOS versions are not supported.

## License

[GPLv3](LICENSE)
