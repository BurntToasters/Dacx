<!-- > [!NOTE]
> 🅱️ This is a Beta build. -->

# ⬇️ Downloads

| <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/windows.png" /> Windows | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/mac.png" /> macOS | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/linux.png" /> Linux |
| :--- | :--- | :--- |
| **MSI:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Windows-x64.msi) | **[Universal DMG](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-macOS.dmg)** | **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Linux-x86_64.AppImage) |
| | **[Universal ZIP](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-macOS.zip)** | **DEB (Deprecated):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Linux-amd64.deb) |
| | | **RPM (Deprecated):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Linux-x86_64.rpm) |
| | | **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Linux-x86_64.flatpak) |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.11.3/Dacx-Linux-x86_64.tar.gz) |

> [!IMPORTANT]
> The `.asc` files are my normal GPG signatures which you can verify using my GPG Public Key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc.
>
> ⚠️ Arm64 Linux and Windows Binaries are NOT available at the moment. Its something I may get around to in the future but its not a priority.

### ℹ️ Enjoying Dacx? Consider [❤️ Supporting Me! ❤️](https://rosie.run/support)

## Changes in `v0.11.3:`
* **PKG:** Updated dependencies.

## Changes in `v0.11.2:`
- **NEW - Paused video frame stepping:** `Ctrl/Cmd+Left/Right Arrow` moves backward or forward by one frame. During playback, the same shortcuts keep navigating chapters.
- **Flutter:** Updated flutter to `3.47.2`.
- **DEB/RPM Binaries:** DEB and RPM binaries are now deprecated. In this modern era of linux, users don't usually sideload `deb` or especially `rpm` binaries anymore. AppImage and Flatpak are more favorable due to their universal compatibility with distros.
  - `DEB` and `RPM` binaries will still be available as of now, but they are officially deprecated and may be removed in the future.
- **Fix - Windows taskbar icon after update:** After an MSI upgrade, a pinned Dacx could show the generic document glyph until unpin/re-pin. The updater now refreshes Explorer and existing taskbar shortcuts; the window sets relaunch icon properties. The Start Menu shortcut no longer uses the MSI Icon table (pins resolve from `dacx.exe`). Add/Remove Programs still uses `ARPPRODUCTICON`.
- **Fix - Test suite green on load failures:** `test-all` no longer treats `flutter test` as passed when files fail to compile/load or the log never prints `All tests passed`. The coverage gate is skipped when tests already failed.
- **Fix - Pending-update snackbar JSON:** `UpdatePendingMarker.readAndClear` accepts the `Map` `jsonDecode` actually returns.
- **Fix - Credential stream URLs:** Open With / IPC no longer treats `http(s)` URLs with embedded userinfo as local files.
- **Fix - Open With window targeting:** A second instance only forwards to a titled Dacx window, not any untitled Flutter runner.
- **Update - Linux/Flatpak drag-and-drop:** `desktop_drop` 0.8.4 registers the portal FileTransfer target so sandboxed drops yield openable paths.
- **Fix - Open With no longer wipes the queue:** Missing or unsafe files are validated before `setPlayingSource`, so a bad Open With path cannot replace a live queue.
- **Fix - Load follow-ups honor generation:** Resume, mix, chapters, album-art track select, and audio filters abort when a newer open starts.
- **Fix - Stop is one path:** UI Stop, media-session Stop, and the sleep timer persist resume, clear mix/filters, stop mpv, clear the OS media session, and reset the surface.
- **Fix - Queue Next/completed race:** Playlist index advances inside the same load queue task; `completed` is ignored while a load is in flight.
- **Fix - Windows singleton restore:** A second launch with no file now activates the existing window (`__DACX_ACTIVATE__`) instead of exiting or spawning a second instance. Open With / file payloads also restore a tray-hidden window. The secondary process calls `AllowSetForegroundWindow` so restore can take focus.
- **Fix - Windows updater helper:** `dacx-update-helper.exe` is copied to `%LOCALAPPDATA%\\Dacx\\updates` before msiexec so the helper is not locked inside Program Files during the upgrade.
- **Fix - Stop vs load races:** Stop bumps the load generation, runs on the same load queue as open, and ignores `completed` while stopping so mix/resume/EQ/queue-advance cannot land on a stopped surface.
- **Fix - macOS covering bookmarks:** Folder/playlist bookmarks are kept when a child file becomes a recent, and opens resolve through the covering directory instead of pruning it.
- **Fix - CLI / Open With URLs:** `http(s)` paths open as streams instead of missing local files. Unsafe playlist paths are refused before parse.
- **UX:** Fullscreen chrome flags update via `setState`; keyboard volume/mute show an OSD and reveal fullscreen chrome. Fullscreen auto-hides chrome; empty home Open URL; seek-preview setting applies live; keybind Escape no longer saves; compact mode checks `mounted` after awaits; sleep remaining chip on the dock.
- **Fix - Windows SMTC:** Commands marshal onto the platform thread; SMTC binds to the Flutter HWND; Clear resets timeline caches.
- **Fix - macOS bookmarks / Dock:** Folder pick and drops capture bookmarks; Dock reopen shows a hidden window; `NSNumber` duration/position parsing; New Window spawns a process like Win/Linux.
- **Fix - Linux portable libmpv:** AppImage, tar, and Flatpak **vendor `libmpv.so.2`** (plus non-system DT_NEEDED deps, including ayatana) into `bundle/lib` with `$ORIGIN` RPATH so they start without a host libmpv. deb/rpm still Depends/`Requires` distro `libmpv2` / `mpv-libs`. Desktop `StartupWMClass` matches `run.rosie.dacx`. Flatpak talks to StatusNotifierWatcher. MPRIS no longer emits Seeked every 400ms.
- **Change - Multi-audio mix withdrawn from UI:** Settings and the ⋯ menu no longer offer mix. Implementation and stored pref stay; `PlaybackMixPolicy.userFacingEnabled` is the restore switch (`docs/ideas/multi-audio-mix.md`).
- **Fix - file_picker 12.0:** Open/save/enqueue use `PlatformFile` / save `Uri` and platform lock options after the stable 12.0 API. Save URIs keep POSIX vs Windows path shape so Windows tests and `C:` paths round-trip.
- **Docs:** One Windows signing story (Azure Artifact Signing + `SKIP_WIN_CODESIGN=1`).

<details>
<summary>Full changelog</summary>

## Changes in `v0.11.0:`
- **NEW - Windows code signing:** WOO HOO!! Windows Codesigning is here!
  - After a good while of not having it, Windows Binaries are now signed by Azure Artifact Signing!
- **NEW - Playlist files:** Open/import `.m3u` and `.pls` playlists from the file picker or drag-and-drop, and save/export the play queue as `.m3u`. HLS `.m3u8` files still open as streams for mpv.
- **NEW - Playback speed:** A transport speed chip cycles presets, with `[` / `]` / `\` shortcuts.
- **NEW - External tracks:** Load external audio or subtitle files from the more menu.
- **NEW - Sleep timer:** The ⋯ menu offers 15 / 30 / 45 / 60 minute presets that stop playback when the timer fires.
- **NEW - Minimize to tray:** An optional Appearance setting lets close hide Dacx to the tray; tray Show / Quit restore or exit the app.
- **Windows:** Added Jump Lists from recents, taskbar playback progress, idle inhibit while playing, SMTC rate updates, playlist Open With ProgIDs, and expanded media extensions. Fixed an unquoted App Search Open With command.
- **PKG - Windows:** Windows releases are now MSI-only. The portable x64 ZIP is no longer built or listed in downloads.
- **macOS:** Expanded File and Dock menus, added Preferences, Check for Updates, display-sleep inhibit, Now Playing playback rate, and richer playlist file associations.
- **Linux:** Idle/screensaver inhibit now uses a persistent D-Bus session. Update guidance is package-aware, package detection handles `/opt/dacx`, MPRIS/AppStream/MIME support is expanded, and Flatpak has ScreenSaver access.
- **UI:** Open URL lives in the ⋯ menu (and macOS File menu) with `Ctrl/Cmd+U`; single-file, Open With, and URL loads sync to the play queue; queue reorder and shuffle persist; media info includes title, artist, and album metadata.
- **Settings:** Window blur and opacity are Appearance settings on Windows/macOS; experimental settings remain isolated; hardware-decoding changes re-apply at runtime; and Keyboard Shortcuts opens the editable F1 keybind dialog.
- **Shortcuts:** Escape returns from Settings, closes the queue drawer before leaving fullscreen, and cancels keybind capture. Custom keybinds now overlay defaults instead of replacing them.
- **Updater:** Windows self-update uses a native helper that re-checks SHA-256 and optional Authenticode before elevating MSI installation, then relaunches Dacx. Linux update guidance is package-aware.
- **Fix - Windows updater:** Creates the update cache directory before downloading the MSI so self-update works on a clean installation.
- **Security:** Rejects UNC and unsafe open paths plus URLs with embedded credentials; hardens macOS update-zip containment and remote artwork; and keeps Windows updater trust Ed25519-first with optional Authenticode pinning.
- **Media session:** Passes title, artist, album, and embedded album artwork to operating-system Now Playing integrations.
- **Codebase:** Extracted `PlayerAudioSession` from `PlayerScreen`; Linux install-kind checks use POSIX normalization; and the Windows updater helper has dedicated test coverage.
- **Testing:** Expanded headless PlayerScreen, updater, shortcuts, queue, settings, drag-drop, media-session, and playback-policy coverage.
- **Docs:** Documented the support contract, Flatpak sideload guidance, per-file resume, the manual QA checklist, and bundled-versus-system native dependencies.
- **PKG:** Added version sync checks for `package-lock.json` and Flatpak metadata; added Linux tray build/runtime dependencies; and removed the obsolete release guard.
- **Misc:** Removed the experimental audio spectrum visualizer; its future reintroduction notes live in `docs/ideas/visualizer.md`.
- **Change:** Quit no longer restores the last session queue; relaunch opens the empty home state. (Per-file resume position when reopening a file is unchanged.)
- **Fix:** Failed experimental multi-audio mix now shows OSD + snackbar and turns the toggle back off (no silent “on but not mixing”).
- **Fix:** Hardened media-session album-art export against stale screenshot races and cleans up superseded temporary artwork.
- **Fix:** Verify `lavfi-complex` writes, including clears, so unsupported native mix graphs fail visibly instead of appearing enabled.
- **Fix:** Mix-triggered reloads preserve the saved playback position without applying per-file resume a second time.
- **Fix:** MPRIS `SetPosition` ignores stale/mismatched track IDs; M3U export/import round-trips query URLs; audio/subtitle track switches no longer show success OSD after a failed set; screenshot filenames keep milliseconds to avoid same-second overwrites.
- **Fix:** Sleep timer snack includes minutes and the ⋯ menu countdown ticks live; periodic resume persist skips while paused; mini-player restores a previously maximized window; Flatpak drop snacks no longer blame the sandbox for every skipped path.
- **UI:** Empty-state tip mentions per-file Resume; accent color swatches gain tooltips.
- **Docs:** Clarified per-file resume, empty relaunch behavior, Flatpak sideload status, and the Ed25519-first Windows signing model.
- **Docs:** Expanded `docs/QA.md` for per-file resume, Reopen Last + resume, media-session artwork, and mix failure feedback.
- **Docs/PKG:** Version sync checks `package-lock.json` and Flatpak `# x-version:`; Linux tray build dep (`libayatana-appindicator3-dev`) in setup/CI; deb/rpm runtime Depends for appindicator; `NATIVE_DEPENDENCIES.md` clarifies bundled vs system libmpv.

## Changes in `v0.9.0:`
### UI - Major UI Overhaul!
The UI has been revamped to provide a way better user experience and UI moving forward.
  * **Playhead and controllers:** The playhead and controller buttons for video/audio has been center aligned.
  * **Queue:** Added a dedicated QUEUE UI instead of it being in the overflow menu.
  * **Settings:** Minor tweaks and fixes to the UI.
  * **Misc:** Color scheme improvements, animation updates, general cleanup.

* **NEW - Linux AppImage and Flatpak:** Added AppImage and Flatpak support!
  * **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.9.0/Dacx-Linux-x86_64.AppImage); portable, no installation needed.
  * **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v0.9.0/Dacx-Linux-x86_64.flatpak); sandboxed package for GitHub sideload (not Flathub).
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
- **Code Signing:** macOS releases are fully signed and notarized. Windows MSIs are fully signed using Azure Artifact Signing. Linux packages are signed with my GPG signature.
- **Windows package:** Dacx ships MSI (not EXE) on Windows, including betas; that is intentional for the self-updater.
- **More info:** See the [README](https://github.com/BurntToasters/Dacx/blob/main/README.md), [FAQ](https://help.rosie.run/dacx/en-us/faq), and [BCLS](https://github.com/BurntToasters/BCLS).
