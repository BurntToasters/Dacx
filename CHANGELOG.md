> [!NOTE]
> 🅱️ This is a Beta build.

### ℹ️ Enjoying Dacx? Consider [❤️ Supporting Me! ❤️](https://rosie.run/support)

# ⬇️ Downloads

| <img height="20" src="https://github.com/user-attachments/assets/340d360e-79b1-4c70-bfab-d944085f75df" /> Windows | <img height="20" src="https://github.com/user-attachments/assets/42d7e887-4616-4e8c-b1d3-e44e01340f8c" /> MacOS | <img height="20" src="https://github.com/user-attachments/assets/e0cc4f33-4516-408b-9c5c-be71a3ac316b" /> Linux |
| :--- | :--- | :--- |
| **MSI: [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Windows-x64.msi)**<!-- / [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Windows-arm64.msi)** -->| **[Universal DMG](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-macOS.dmg)** | **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-x86_64.AppImage) |
| <!-- <div align="center"><a href="https://apps.microsoft.com/detail/9pkgd6lkcl5j?referrer=appbadge&mode=full"><img src="https://get.microsoft.com/images/en-us%20light.svg" width="150"/></a></div>--> | **[Universal ZIP](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-macOS.zip)** | **DEB:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-amd64.deb) <!--/ [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-arm64.deb)--> |
| <!--*See MSI note below*--> | | **RPM:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-x86_64.rpm) <!--/ [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-aarch64.rpm)--> |
| | | **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-x86_64.flatpak) |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-x86_64.tar.gz) <!--/ [arm64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-aarch64.flatpak)--> |

> [!IMPORTANT]
The `.asc` files are my normal GPG signatures which you can verify using my GPG Public Key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc.
⚠️ Arm64 Linux and Windows Binaries are *NOT* available at the moment. Its something I may get around to in the future but its not a priority.

## Changes in `v0.10.0-beta.8 (RC2):`
* **Misc:** General fixes to the audio visualizer and UI.
* **Audio Visualizer:** Changed from a generic animation to an experimental spectrum visualizer.

## Changes in `v0.10.0-beta.7 (RC):`
* **UI:** Fixed an issue where the blur UI was being applied to the normal ui.

## Changes in `v0.10.0-beta.6:`
* **Updater:** Added new error messages for when updates fail rather than a generic error or the updater saying the user is up-to-date.

## Changes in `v0.10.0-beta.5:`
* **UI:** More fixes to the Blur UI.

## Changes in `v0.10.0-beta.4:`
* **Blur:** Finally fixes blurred app backgrounds! (Issue since the beginning lol).
* **Misc:** Fixes to the codebase, moved the audio visualizer behind the experimental features toggle for the time being.

## Changes in `v0.10.0-beta.3:`
- **Misc:** General fixes to the window rendering system and audio visualizer.

## Changes in `v0.10.0-beta.2:`
- **Misc:** General fixes.

## Changes in `v0.10.0-beta.1:`
* **Audio Visualizer:** Added a new audio-reactive bar visualizer for audio playback.
* **Window Transparency/Blurring:** Started more work on the neglected experimental window customization settings for blurring and transparency.
* **Backend:** Updated base flutter version to `v3.44.5`.

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
  * **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-x86_64.AppImage) — portable, no installation needed.
  * **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.10.0-beta.8/Dacx-Linux-x86_64.flatpak) — sandboxed package for app-store distributions (Flathub support planned).
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
    * On all platforms, if a user opens a audio/video file with DACX via the `Open With` menu on their OS or sets DACX as a default player and double-clicks the file, DACX will now stop the current playing file and start playing the new one. This can be changed in settings.
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

Hello everyone its me again releasing another app/tool I developed for my own niche but of course love to share :)
This is intended to be a light-weight music and video player just meant to launch quick and play media without any extra nonsense!

## Info
More information about Dacx is available via the [README](https://github.com/BurntToasters/Dacx/blob/main/README.md) and also via: [https://help.rosie.run/dacx/en-us/faq](https://help.rosie.run/dacx/en-us/faq).

[i] This changelog is made using the BCLS standard: https://github.com/BurntToasters/BCLS
