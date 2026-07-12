> [!NOTE]
> 🅱️ This is a Beta build.

# ⬇️ Downloads

| <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/windows.png" /> Windows | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/mac.png" /> macOS | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/linux.png" /> Linux |
| :--- | :--- | :--- |
| **MSI:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Windows-x64.msi) <!-- / [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Windows-arm64.msi) --> | **[Universal DMG](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-macOS.dmg)** | **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-x86_64.AppImage) <!-- / [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-arm64.AppImage) --> |
| | **[Universal ZIP](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-macOS.zip)** | **DEB:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-amd64.deb) <!-- / [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-arm64.deb) --> |
| | | **RPM:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-x86_64.rpm) <!-- / [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-aarch64.rpm) --> |
| | | **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-x86_64.flatpak) <!-- / [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-aarch64.flatpak) --> |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.0-beta.4/Dacx-Linux-x86_64.tar.gz) |

> [!IMPORTANT]
> The `.asc` files are my normal GPG signatures which you can verify using my GPG Public Key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc.
>
> This is a pre-1.0 beta — expect rough edges. Arm64 Linux and Windows binaries are *not* available yet.

### ℹ️ Enjoying Dacx? Consider [❤️ Supporting Me! ❤️](https://rosie.run/support)

## Changes in `v0.11.0-beta.4:`
- **Ver:** Bumped version to `v0.11.0-beta.4`.
- **Updater:** After a successful MSI self-update, `dacx-update-helper.exe` relaunches Dacx (update & restart), matching the macOS updater.
- **NEW - Sleep timer:** ⋯ more menu presets (15 / 30 / 45 / 60 minutes) stop playback when the timer fires.
- **NEW - Minimize to tray:** Optional Appearance setting; close hides to tray, tray Show / Quit restore or exit.
- **PKG:** Windows portable ZIP is no longer packaged (MSI only). WiX v3 fallback removed (WiX v4+ / v7 required).
- **Misc:** Documented Flatpak as GitHub-sideload-only (no Flathub plans); Linux install guidance prefers AppImage + [AppManager](https://github.com/kem-a/AppManager); Experimental Features kept as a long-lived WIP lane past `1.0`; dropped unused `release:guard` script.

## Changes in `v0.11.0-beta.3:`
- **Testing:** This update is purely to test the new windows updater helper.

## Changes in `v0.11.0-beta.2:`

- **Ver:** Bumped version to `v0.11.0-beta.2`.
- **Shortcuts:** Escape goes back from Settings, closes the play queue drawer before exiting fullscreen (and reconciles OS/title-bar fullscreen via WindowListener), and cancels keybind capture instead of binding Escape.
- **UI:** Removed the empty-state Open URL button — Open URL stays in the ⋯ more menu (and macOS File → Open URL) plus `Ctrl/Cmd+U`.
- **UI:** Unsupported extensions and Flatpak-inaccessible drops now show clear snackbars; failed external audio/subtitle loads surface a snackbar in addition to the OSD tip.
- **Security:** Windows self-update now launches a native `dacx-update-helper.exe` via a short in-memory WMI bootstrap (no on-disk `apply-update.ps1` / `spawn-watchdog.ps1`) so the helper survives the app Job Object, re-checks SHA-256 (and optional Authenticode), then elevates `msiexec`. After a successful install the helper relaunches Dacx (update & restart). Trust stays Ed25519-first.
- **Testing:** Expanded the headless `PlayerScreen` harness and Windows self-update tests around Escape reconcile, snacks, session restore, external tracks, and the native helper launch path.
- **Misc:** Updated `docs/QA.md`, `SECURITY.md`, and the README Windows signing notes for the helper binary.

## Changes in `v0.11.0-beta.1:`

- **Ver:** Bumped version to `v0.11.0-beta.1`.
- **NEW - Playlist files:** Added open/import for `.m3u` / `.pls` (file picker, empty state, and drag-drop) plus save/export of the play queue as `.m3u`. HLS `.m3u8` still opens as a stream for mpv.
- **NEW - Session queue restore:** I now restore the last session queue (paths + index) on launch, prune missing files, and keep shuffle via the existing preference.
- **NEW - Playback speed:** Added a transport speed chip that cycles presets, plus `[` / `]` / `\` shortcuts.
- **NEW - External tracks:** You can load external audio or subtitle files from the more menu.
- **macOS:** Expanded File / Dock menus (Open Folder / Playlist / URL / Reopen Last / New Window / Open Recent → Clear Menu / Save Playlist), Preferences… (⌘,), Check for Updates…, display-sleep inhibit while playing, Now Playing playback rate, and richer Launch Services types including playlists.
- **Windows:** Added Jump Lists from recents, taskbar playback progress, idle inhibit while playing, SMTC rate updates, playlist Open With ProgIDs, and expanded media extensions. Fixed an issue where App Search registered an unquoted Open With command alongside the file-assoc entry.
- **Linux:** Idle/screensaver inhibit while playing now uses a persistent D-Bus session so it actually sticks. Update guidance is package-aware (Flatpak / AppImage / deb·rpm / portable). Fixed an issue where deb/rpm installs under `/opt/dacx` were mislabeled as portable. MPRIS `desktopEntry` matches the packaged `.desktop`; fuller icons / MIME / AppStream coverage; Flatpak ScreenSaver talk-name.
- **UI:** Moved Open URL into the ⋯ more menu (macOS File → Open URL stays), and the more menu now works on the empty state so Win/Linux can still open streams. Added an empty-state Open URL button plus `Ctrl/Cmd+U`. Grouped the menu with dividers. Mute toggles from the volume icon. Prev/next tooltips now match `Shift+P` / `Shift+N`. Media Info shows title / artist / album when tags are present. Empty-state Reopen Last tip mentions Ctrl/Cmd+R.
- **UI:** Single-file Open / Open With / URL loads sync into the play queue; Open With on the same path restarts when already playing; queue drag-reorder + shuffle on the drawer (shuffle now persists and stays in sync with Settings / media session / OS chrome).
- **Settings:** Graduated window blur / opacity to Appearance on Windows and macOS (Linux compositor blur stays experimental). Turning Experimental off no longer clears Win/mac blur. Experimental children (visualizer, multi-audio mix, Linux blur) live under the Experimental section. Seek thumbnails stay in Playback settings only. Hardware decode changes re-apply at runtime. Settings → Keyboard shortcuts opens the full editable F1 keybinds dialog (⌘ labels on macOS). Expanded folder-scan extensions (`ts` / `m2ts` / `mpg` / …).
- **Misc:** Rebuilt the experimental audio visualizer as real multiband lavfi analysis (4 bands → 32 bars) with a safer filter lifecycle, mutual exclusion with multi-audio mix, and a capability probe with OSD. Still experimental and off by default.
- **Shortcuts:** Custom keybinds now overlay defaults instead of replacing the entire map.
- **Updater:** Linux Check for Updates copy is package-aware; Flatpak empty state is picker-first with a Reopen Last tip.
- **Misc:** Media session now passes title / artist / album from tags and exports embedded album art for OS Now Playing.
- **Security:** Reject UNC / unsafe open paths and URLs with embedded credentials; hardened macOS update zip containment and Now Playing remote artwork hosts; clarified that Windows self-update trust is Ed25519-first with optional Authenticode pin.
- **Codebase:** Extracted `PlayerAudioSession` from `PlayerScreen`; limited CI / release guard to `main` and `beta`. Linux install-kind path checks use POSIX normalization so detection stays correct when unit-tested on Windows hosts.
- **Testing:** Expanded VM tests and the headless `PlayerScreen` harness around playback policies and recent UI wiring.
- **Misc:** Documented the support contract in the README (en-only, macOS 15+, x64), Flatpak sideload update guidance, and a manual QA checklist in `docs/QA.md`.
- **PKG:** Updated packages.

## Changes in `v0.10.1-beta.1:`

- **NEW - Audio visualizer:** Added a new audio-reactive bar visualizer for audio playback (experimental).
- **UI:** More work on window transparency / blur — closer to graduating out of Experimental!
- **Codebase:** Updated the pinned Flutter version to `v3.44.5`.
- **Testing:** Expanded `npm run test:all` with a headless `PlayerScreen` harness (transport, queue, settings, drag-drop, shortcuts, media session, screenshots, and more) plus extracted playback-policy unit coverage.
- **Misc:** `IPlayerService` injection and load-generation guards reduce stale UI after rapid queue changes; self-update redirect allowlist and Windows manifest validation covered by direct tests.
- **PKG:** Updated packages.

<details>
<summary>Full changelog</summary>

## Changes in `v0.9.0:`
### UI - Major UI Overhaul!
The UI has been revamped to provide a way better user experience and UI moving forward.
  * **Playhead and controllers:** The playhead and controller buttons for video/audio has been center aligned.
  * **Queue:** Added a dedicated QUEUE UI instead of it being in the overflow menu.
  * **Settings:** Minor tweaks and fixes to the UI.
  * **Misc:** Color scheme improvements, animation updates, general cleanup.

* **NEW - Linux AppImage and Flatpak:** Added AppImage and Flatpak support!
  * **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.1-beta.1/Dacx-Linux-x86_64.AppImage) — portable, no installation needed.
  * **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.1-beta.1/Dacx-Linux-x86_64.flatpak) — sandboxed package for app-store distributions (Flathub support planned).
- **NEW - Localization completeness:** Nearly all user-facing strings are now localized via `flutter gen-l10n`. Covered: transport control tooltips; folder + URL button and dialog labels; media info metadata labels; folder scan and queue-truncation error feedback; update progress dialog (installing/progress/failure states and all error-outcome messages); post-update result snackbars; debug log panel UI; accessibility `Semantics` labels (seek bar, accent color picker, mini-player exit button); keyboard shortcut action names; equalizer preset labels; chapter and track fallback labels. Previously orphaned `snackDebugLogCopied`/`snackDebugLogCleared` keys are now used.
- **Testing:** 352+ tests passing. Code verified clean with zero lint issues.
- **Codebase:** All l10n keys auto-generated via `flutter gen-l10n`.
* **Stability:** Reset player track and multi-audio mix state on each new media load so stale audio/video IDs cannot leak into the next file.
* **Stability:** Window position restore now validates against display bounds; off-screen positions are reset to center.
* **MacOS:** Added a launch warning when packaged Dacx is run outside `/Applications/Dacx.app`; the self-updater still targets `/Applications/Dacx.app`.
* **MacOS:** Self-update XPC helper now fails closed when own Team ID cannot be resolved.
* **Windows:** Added a timeout around certificate-store hydration used by update HTTP requests.
* **Windows:** Named-pipe IPC now fails closed if per-user DACL setup fails (defense-in-depth).
* **Windows:** SMTC media-session channels properly detached on window close (prevents latent use-after-free).
* **Linux:** Cold-launch with multiple files now forwards all files to the queue, not just the first.
* **Codebase:** Hardened Node command runners for newer Node versions, refreshed GitHub Actions pins, and added GitHub Actions Dependabot coverage.
* **Compliance:** Improved license generation for Flutter SDK runtime packages and documented the current macOS Swift Package Manager plugin fallback.
* **PKG:** Updated packages.

## Changes in `v0.8.0:`
*Dacx like my other projects now has two update channels: `STABLE` and `BETA`.*

### Important breaking change in v0.8.0: Windows EXE installers are REMOVED in favor of .msi installers.
*If you installed DACX via the exe installers previously, please uninstall dacx and re-install via the MSI installer.*
* **Windows:** `.EXE` Installers have been **REMOVED**.
  * For now I have made the decision to remove the exe installer as for the new self-updater function to work in the best way, `.MSI` is the best choice. If a user installs Dacx via .exe and then updates via .msi, there will be multiple entries in the registry and install list and could create conflict issues in the future.
  * The portable exe remains for now; but it is deprecated and NOT supported any longer.

* **NEW - Self updater:** Added a new experimental custom self updater for Windows and macOS
  * **Windows:** Verifies new json signature file when downloading and verifies .msi SHA256SUM and then launches `msiexec`.
  * **MacOS:** Helper spawns in, closes Dacx, downloads .zip from github, verifies SHA256 sum and unzips .zip, verifies code signature for unzipped .app, overwrites current app in /Applications/.
* **NEW - Update channels:** Added the ability for users to switch between `STABLE` and `BETA` updates for Dacx!
  * The default setting is `AUTO` which keeps a user on `STABLE` if they are on a stable version, or keeps a user on `BETA` if they are on a beta version.
* **Windows:** Fixes issues with the windowing system for multiple Dacx windows on Windows (mouthful lol).
* **Stability:** Settings screen wraps list tiles in `Material` (fixes widget tests on Flutter 3.44); `npm run test:all` uses FVM-pinned Flutter/Dart; VS Code SDK path aligned with `.fvmrc`; dropped flaky device-bound `integration_test` (307 VM tests remain).
* **Compliance:** `THIRD_PARTY_NOTICES.txt` + `LICENSE` bundled in Windows/macOS/Linux/Flatpak releases (`npm run licenses`); Flatpak drops `--filesystem=host` and broad XDG document/desktop mounts.
* **Tests:** Added more test coverage.
* **PKG:** Updated packages.

## Changes in `v0.7.0:`
*`v0.7.0` is a quality and stability-focused release branch of DACX.*
* **Window Behavior:** Changed default opening behavior of another file is DACX is already open.
    * On all platforms, if a user opens a audio/video file with DACX via the `Open With` menu on their OS or sets DACX as a default player and double-clicks the file, DACX will now stop the current playing file and start playing the new one.
* **NEW - Window shortcut:** Added the `CTRL`/`CMD`+N which spawns a new DACX window.
* **Settings:** Migrated settings to a new schema.
* **NEW - Localization:** Dacx has moved *most* of its hard-coded English languages to `l10n`, making it easier for contributors in the future to add localization support for other languages.
* **Logo:** Tweaked logo.
* **PKG:** Updated packages.
* **Misc:**
  * Major behind-the-scenes fixes and improvements to the custom title bar UI for Windows.
  * Major fixes to app launch time.
  * Fixed multiple issues with `MKV` video containers.
  * Other misc bug fixes and improvements to the codebase.

## Changes in `v0.6.0:`
### v0.6.0 is a large feature packed update :) I hope you enjoy this project getting close to my vision of 1.0!
* **NEW - Resume from position:** Dacx will now remember the last area of a video a user was last on and will resume where they were last when they re-open it.
* **NEW - Playback options::** A new menu (vertical 3 dots) has been added with a large amount of options for video and audio playback!
* **NEW - Playlist / queue:** Dacx now supports playlist creation and queues!
* **NEW - Mini-player / compact mode:** Dacx now has a mini player that can be activated via the playback options menu!
  * The mini player behavior uses the always on top OS API to stay above all windows whilst giving the user a mini player experience.
* **NEW - Now Playing:** Added Windows, Linux, and macOS operating system media API support so when something is playing via Dacx, the OS will show it in its media menu.
* **NEW - Video thumbnail scrubbing support:** Dacx now supports a "YouTube-like" thumbnail preview when hovering over the play-head.
  * This is disabled by default but can be enabled via the playback options.
* **Metadata:** Improved the metadata extraction from media files.
* **Testing:** Added more testing to the repo.
* **PKG:** Updated packages.
* **Misc:** Various bug fixes and UI improvements!

## Changes in `v0.5.0:`
### Dacx now is officially listed on the ROSI project site! Check it out! [https://rosie.run/dacx](https://rosie.run/dacx).
* **Album Art:** Dacx now fully supports showing album art when playing audio files!
* **UI:** Fixed issues with the Flutter UI on windows.
* **Settings:** Added a support and help button to settings.
* **PKG:** Updated packages.
* **Codebase:**
  - Update links forced validated HTTPS URLs.
  - Redacted sensitive local path data from copied debug log exports.
  - Added more env options to `.env.example` and improved Flatpak manifest.

## Changes in `v0.4.0:`
* **Windows:** Fixed race conditions with custom title bar UI that would cause graphical corruption.
* **Codebase:** More fixes for cross-platform initialization and hardware acceleration.
* **PKG:** Updated packages.

## Changes in `v0.3.0:`
Welcome to the first beta build of Dacx! I've pruned through the codebase enough to confidently call it `BETA` at the very least. See my long list of changes below :)
* **NEW - Debug:** A hidden debug mode has now been added (easier for me and other techy people to look for issues).
  * To show the debug mode, press the "About Dacx" text at the bottom of settings.
* **UI:** Tweaked UI for better UI and UX :)
* **NEW - Experimental Settings:** Added a new experimental settings toggle in settings so users can try out certain options I am playing with.
  * **NOTE** These settings as per the name, are unstable and experimental. It is also very possible those options do *not* get fully implemented into Dacx and are silently removed later.
* **Player:** Fixed multiple issues with playing audio files on Linux.
* **Logo:** YALC (Yet Another Logo Change) Updated the logo :P 
* **MISC:**
  * Codebase improvements for scripting.
  * Misc bug fixes and improvements to the flutter codebase.
  * PKG updates.
	

</details>

## ℹ️ Release Info

- **GPG Signed:** My public key is attached to every release to ensure authenticity.
- **GPG Key:** Public key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc .
- **Code Signing:** macOS releases are fully signed and notarized. Windows MSIs are not Authenticode-signed by default; trust the GPG `.asc` plus the Ed25519-signed update manifest for self-update. Linux packages are GPG-signed the same way.
- **Windows package:** Dacx ships MSI (not EXE) on Windows, including betas — that is intentional for the self-updater.
- **More info:** See the [README](https://github.com/BurntToasters/Dacx/blob/main/README.md), [FAQ](https://help.rosie.run/dacx/en-us/faq), and [BCLS](https://github.com/BurntToasters/BCLS).
