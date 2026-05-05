# Dacx

Quick, lightweight cross-platform media player.

Built with Flutter + [media_kit](https://github.com/media-kit/media-kit) (libmpv).

<div align="center">
  <table>
    <tr>
      <td valign="middle" align="center" width="220">
        <img src="https://github.com/BurntToasters/Dacx/blob/main/assets/icon/icon.png"
             alt="Dacx logo" width="180" />
      </td>
      <td valign="middle" align="center">
        <p align="center">
  <img width="85%" height="1012" alt="Dacx-1" src="https://github.com/BurntToasters/Dacx/blob/main/assets/screenshots/dacx_sc.png" />
&nbsp;
</p>
      </td>
    </tr>
  </table>
</div>

<h1 align="center">⬇️ Downloads</h1>
<div align="center">
  
| <img height="20" src="https://github.com/user-attachments/assets/340d360e-79b1-4c70-bfab-d944085f75df" /> Windows | <img height="20" src="https://github.com/user-attachments/assets/42d7e887-4616-4e8c-b1d3-e44e01340f8c" /> MacOS | <img height="20" src="https://github.com/user-attachments/assets/e0cc4f33-4516-408b-9c5c-be71a3ac316b" /> Linux |
| :--- | :--- | :--- |
| **EXE: [x64](https://github.com/BurntToasters/DACX/releases/latest/download/Dacx-Windows-x64.exe) / MSI: [x64](https://github.com/BurntToasters/DACX/releases/latest/download/v0.6.2/Dacx-Windows-x64.msi)**<!-- / [arm64](https://github.com/BurntToasters/S3-Sidekick/releases/latest/download/v0.9.1/S3-Sidekick-Windows-arm64.exe)** -->| **[Universal DMG](https://github.com/BurntToasters/DACX/releases/latest/download/v0.6.2/Dacx-macOS.dmg)** | <!--**AppImage:** [x64](https://github.com/BurntToasters/S3-Sidekick/releases/latest/download/v0.9.1/S3-Sidekick-Linux-x64.AppImage)--> <!--/  [arm64](https://github.com/BurntToasters/IYERIS/releases/latest/download/v1.0.4/IYERIS-Linux-arm64.AppImage) --> |
| <!-- <div align="center"><a href="https://apps.microsoft.com/detail/9pkgd6lkcl5j?referrer=appbadge&mode=full"><img src="https://get.microsoft.com/images/en-us%20light.svg" width="150"/></a></div>--> | **[Universal ZIP](https://github.com/BurntToasters/DACX/releases/latest/download/v0.6.2/Dacx-macOS.zip)** | **DEB:** [x64](https://github.com/BurntToasters/DACX/releases/latest/download/v0.6.2/Dacx-Linux-amd64.deb) <!--/ [arm64](https://github.com/BurntToasters/IYERIS/releases/latest/download/v1.0.4/IYERIS-Linux-arm64.deb)--> |
| <!--*See MSI note below*--> | | **RPM:** [x64](https://github.com/BurntToasters/DACX/releases/latest/download/v0.6.2/Dacx-Linux-x86_64.rpm) <!--/ [arm64](https://github.com/BurntToasters/IYERIS/releases/latest/download/v1.0.4/IYERIS-Linux-aarch64.rpm)--> |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/DACX/releases/latest/download/v0.6.2/Dacx-Linux-x86_64.tar.gz) <!--/ [arm64](https://github.com/BurntToasters/IYERIS/releases/latest/download/v1.0.4/IYERIS-Linux-aarch64.flatpak)--> |

</div>

## Platforms

- Windows
- macOS
- Linux

## Features

- Audio + video playback for MP3, FLAC, WAV, OGG, AAC, Opus, MP4, MKV, AVI, WebM and more (anything libmpv handles).
- 10-band equalizer with presets.
- Multi-audio-track mixing via `lavfi-complex`.
- Resume playback from where you left off.
- Compact mode and always-on-top window.
- Drag-and-drop and CLI file opening.
- System media-session integration: lock-screen / Now Playing / SMTC controls, artwork, scrubbing, and remote play/pause/next/previous/seek on all three platforms.
- File associations + custom document icon on macOS, Windows installers, and Flatpak.
- Built-in update checker against GitHub releases.
- Notarized + stapled DMG and ZIP for macOS; signed installers for Windows.

## Changelog

See [`run.rosie.dacx.metainfo.xml`](run.rosie.dacx.metainfo.xml) for per-version release notes.

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

## License

[GPLv3](LICENSE)
