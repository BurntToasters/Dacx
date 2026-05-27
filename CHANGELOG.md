> [!NOTE]
> 🅱️ This is a BETA build.
### ℹ️ Enjoying Dacx? Consider [❤️ Supporting Me! ❤️](https://rosie.run/support)

# ⬇️ Downloads

| <img height="20" src="https://github.com/user-attachments/assets/340d360e-79b1-4c70-bfab-d944085f75df" /> Windows | <img height="20" src="https://github.com/user-attachments/assets/42d7e887-4616-4e8c-b1d3-e44e01340f8c" /> MacOS | <img height="20" src="https://github.com/user-attachments/assets/e0cc4f33-4516-408b-9c5c-be71a3ac316b" /> Linux |
| :--- | :--- | :--- |
| **MSI (Recommended): [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.8.0-beta.11/Dacx-Windows-x64.msi)**<!-- / [arm64](https://github.com/BurntToasters/S3-Sidekick/releases/download/v0.9.1/S3-Sidekick-Windows-arm64.msi)** -->| **[Universal DMG](https://github.com/BurntToasters/Dacx/releases/download/v0.8.0-beta.11/Dacx-macOS.dmg)** | <!--**AppImage:** [x64](https://github.com/BurntToasters/S3-Sidekick/releases/download/v0.9.1/S3-Sidekick-Linux-x64.AppImage)--> <!--/  [arm64](https://github.com/BurntToasters/IYERIS/releases/download/v1.0.4/IYERIS-Linux-arm64.AppImage) --> |
| <!-- <div align="center"><a href="https://apps.microsoft.com/detail/9pkgd6lkcl5j?referrer=appbadge&mode=full"><img src="https://get.microsoft.com/images/en-us%20light.svg" width="150"/></a></div>--> | **[Universal ZIP](https://github.com/BurntToasters/Dacx/releases/download/v0.8.0-beta.11/Dacx-macOS.zip)** | **DEB:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.8.0-beta.11/Dacx-Linux-amd64.deb) <!--/ [arm64](https://github.com/BurntToasters/IYERIS/releases/download/v1.0.4/IYERIS-Linux-arm64.deb)--> |
| <!--*See MSI note below*--> | | **RPM:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.8.0-beta.11/Dacx-Linux-x86_64.rpm) <!--/ [arm64](https://github.com/BurntToasters/IYERIS/releases/download/v1.0.4/IYERIS-Linux-aarch64.rpm)--> |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.8.0-beta.11/Dacx-Linux-x86_64.tar.gz) <!--/ [arm64](https://github.com/BurntToasters/IYERIS/releases/download/v1.0.4/IYERIS-Linux-aarch64.flatpak)--> |

> [!IMPORTANT]
The `.asc` files are my normal GPG signatures which you can verify using my GPG Public Key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc.
⚠️ Arm64 Linux and Windows Binaries are *NOT* available at the moment. Its something I may get around to in the future but its not a priority.
*This app is currently unstable. Bugs, issues, and rough edges are expected.*

## Changes in `v0.8.0-beta.11:`
* **Win:** Fixed malformed exe manifest.

## Changes in `v0.8.0-beta.10:`
* **Win:** Addressed an issue where the MSVC runtime DLLs were not included in the latest MSI beta installers.
* **PKG:** Updated packages.

## Changes in `v0.8.0-beta.9:`
* **Self-Update (Windows):** Fixed critical regression where updater spawned watchdog via conhost.exe but watchdog never ran (silent fail on Windows 10); reverted to plain powershell.exe. Extended watchdog timeout from 2 min → 10 min to handle slow Windows shutdowns. Fixed watchdog bare exception catch to distinguish "process-already-gone" from other errors (now exits with error code on unexpected failures). Added watchdog logging to `%LOCALAPPDATA%\Dacx\updates\watchdog.log`. Fixed `-Verb RunAs -UseShellExecute` to properly trigger UAC elevation on msiexec spawn.
* **Self-Update (Windows & macOS):** Added manifest field validation (`app="Dacx"`, `platform="windows-x64"`). Windows manifest now includes `released_at` timestamp (defense-in-depth). Added process-wide install guard to prevent concurrent update spawns. Fixed TLS root cert hydration to retry on failure instead of permanently failing for session lifetime.
* **Update Service:** Beta channel now fetches both stable and prerelease endpoints in parallel (reduced API calls). Fixed version comparison to pick newer stable release when it's available to beta users. Both platforms now verify manifest signatures before proceeding.
* **macOS:** Self-update verification uses `codesign` only (removed deprecated `spctl`); fixes false "internal error in Code Signing subsystem" when assessing bundles inside the sandbox container (beta 6+).
* **Stability:** Settings screen wraps list tiles in `Material` (fixes widget tests on Flutter 3.44); `npm run test:all` uses FVM-pinned Flutter/Dart; VS Code SDK path aligned with `.fvmrc`; dropped flaky device-bound `integration_test` (307 VM tests remain).
* **Compliance:** `THIRD_PARTY_NOTICES.txt` + `LICENSE` bundled in Windows/macOS/Linux/Flatpak releases (`npm run licenses`); Flatpak drops `--filesystem=host` and broad XDG document/desktop mounts.

## Changes in `v0.8.0-beta.8:`
* **Win:** Addressed multiple issues with the new self-updater on windows:
  * Updater spawned a visible terminal window that was broken.
  * Updater wasn't cleanly launching.
  * TLS issues with Dart.
* **Codebase:** Misc fixes to the build pipeline and general stability fixes.

## Changes in `v0.8.0-beta.7:`
* **Codebase:** Lots of general stabilization to the app (especially macOS).
* **PKG:** Updated packages.

## Changes in `v0.8.0-beta.6:`
* **macOS:** Added Sparkle/Apple sandbox permissions back with a permissive rule for the updater helper.
  * Testing this feature.
  * This addresses a bug from beta 5 on macOS where users couldn't use the file picker as flutter expected a sandbox permission (I didn't want to fully remove the sandbox permanently).

## Changes in `v0.8.0-beta.5:`
* **MacOS:** Self-updater deemed stable-ish.
* **Windows:** Fixed an issue with the .MSI installers where beta string names were being passed to it (MSI installs don't support version #s with strings).
* **Windows:** `.EXE` Installers have been **REMOVED**.
  * For now I have made the decision to remove the exe installer as for the new self-updater function to work in the best way, `.MSI` is the clear choice. If a user installs Dacx via .exe and then updates via .msi, there will be multiple entries in the registry and install list and could create conflict issues in the future.
  * The portable exe remains for now; but it is deprecated and NOT supported any longer.

## Changes in `v0.8.0-beta.4:`
* **Mac:** Fixed an issue where incorrect sandbox permissions caused the app to crash.

## Changes in `v0.8.0-beta.3:`
* **Mac:** Fixed an issue with MacOS beta number versioning that made the updater think beta users were on a stable release.
* **Tests:** Added more test coverage.
* **PKG:** Updated packages.

## Changes in `v0.8.0-beta.2:`
* **NEW - Self updater:** Added a new experimental custom self updater for Windows and macOS
  * **Windows:** Verifies new json signature file when downloading and verifies .msi SHA256SUM and then launches `msiexec`.
  * **MacOS:** Helper spawns in, closes Dacx, downloads .zip from github, verifies SHA256 sum and unzips .zip, verifies code signature for unzipped .app, overwrites current app in /Applications/.

## Changes in `v0.8.0-beta.1:`
*Welcome to the first REAL beta of Dacx! Dacx like my other projects now has two update channels: `STABLE` and `BETA`.*
* **NEW - Update channels:** Added the ability for users to switch between `STABLE` and `BETA` updates for Dacx!
  * The default setting is `AUTO` which keeps a user on `STABLE` if they are on a stable version, or keeps a user on `BETA` if they are on a beta version.
* **Windows:** Fixes issues with the windowing system for multiple Dacx windows on Windows (mouthful lol).
* **PKG:** Updated packages.

<details>
<summary>Full changelog</summary>

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