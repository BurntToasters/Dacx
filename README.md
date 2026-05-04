# Dacx

Quick, lightweight cross-platform media player.

Built with Flutter + [media_kit](https://github.com/media-kit/media-kit) (libmpv).

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
