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
<div align="center">
  
| <img height="20" src="https://github.com/user-attachments/assets/340d360e-79b1-4c70-bfab-d944085f75df" /> Windows | <img height="20" src="https://github.com/user-attachments/assets/42d7e887-4616-4e8c-b1d3-e44e01340f8c" /> MacOS | <img height="20" src="https://github.com/user-attachments/assets/e0cc4f33-4516-408b-9c5c-be71a3ac316b" /> Linux |
| :--- | :--- | :--- |
| **MSI:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.msi) | **DMG:** [Universal](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-macOS.dmg) | **DEB:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-amd64.deb) |
| <!--**Portable ZIP:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Windows-x64.zip)--> | **ZIP:** [Universal](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-macOS.zip) | **RPM:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.rpm) |
| | | **TAR.GZ:** [x64](https://github.com/BurntToasters/Dacx/releases/latest/download/Dacx-Linux-x86_64.tar.gz) |

</div>

## Platforms

- Windows
- macOS
- Linux

## Features

- Audio + video playback for MP3, FLAC, WAV, OGG, AAC, Opus, MP4, MKV, AVI, WebM, and more (anything libmpv handles).
- 10-band equalizer with presets.
- Multi-audio-track mixing via `lavfi-complex` (experimental and currently unstable).
- Resume playback from where you left off.
- Compact mode and always-on-top window.
- System media-session integration: lock-screen / Now Playing / SMTC controls, artwork, and scrubbing.
- File associations + custom document icon on Windows and Linux.
- Built-in update checker against GitHub releases.
- Notarized & Signed DMG and ZIP for macOS; signed installers via GPG for Windows and Linux.

## Development

> [!NOTE]
> This project uses Flutter/Dart but also NodeJS. Its a little bit messy and not the best of practices I know, im just the most familiar and confident with js scripting and node so thats how the project is controlled. Sorry :P

```bash
# Install Node.js dependencies (build scripts)
npm install

# Install Flutter dependencies
flutter pub get

# Run in development mode
npm run dev

# Run tests
npm run test:all

# Build for current platform
npm run build:win   # Windows
npm run build:mac   # macOS
npm run build:linux # Linux
```

### Local dev builds without signing credentials

Release builds bake the code-signing identity into the binary so self-update can pin against it. The build scripts now fail fast if those secrets are missing:

- `scripts/flutter-build-macos.js` requires `APPLE_TEAM_ID` (from `.env`).
- `scripts/flutter-build-windows.js` requires `WINDOWS_SIGNING_CERT_THUMBPRINT` (or `DACX_WINDOWS_SIGNER_THUMBPRINT`).

For local development builds where you don't have those credentials, set an override env var to skip the check:

```bash
DACX_BUILD_DEV_NO_TEAM_ID=1 npm run build:mac
DACX_BUILD_DEV_NO_THUMBPRINT=1 npm run build:win
```

Builds produced this way **will not be able to self-update** — Authenticode / team-id verification is disabled at compile time. They're fine for manual testing.

### macOS support

The macOS build targets **macOS 15 (Sequoia) or newer**. Older macOS versions are not supported.

## License

[GPLv3](LICENSE)
