<!-- > [!NOTE]
> 🅱️ This is a Beta build. -->

# ⬇️ Downloads

| <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/windows.png" /> Windows | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/mac.png" /> macOS | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/linux.png" /> Linux |
| :--- | :--- | :--- |
| **MSI:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-Windows-x64.msi) | **[Universal DMG](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-macOS.dmg)** | **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-Linux-x86_64.AppImage) |
| | **[Universal ZIP](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-macOS.zip)** | **DEB (Deprecated):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-Linux-amd64.deb) |
| | | **RPM (Deprecated):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-Linux-x86_64.rpm) |
| | | **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-Linux-x86_64.flatpak) |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.1.0/Dacx-Linux-x86_64.tar.gz) |

> [!IMPORTANT]
> The `.asc` files are my normal GPG signatures which you can verify using my GPG Public Key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc.
>
> ⚠️ Arm64 Linux and Windows Binaries are NOT available at the moment. Its something I may get around to in the future but its not a priority.

### ℹ️ Enjoying Dacx? Consider [❤️ Supporting Me! ❤️](https://rosie.run/support)

## Changes in `v1.1.0:`
- **NEW - Fullscreen controls:** In fullscreen, the title bar and controls now slide in over the video, so the video no longer resizes. They stay visible while you hover or drag on them, while a menu or the queue is open, and while playback is paused. Otherwise they hide after 3 seconds, and the cursor hides with them.
- **NEW - Mini-player:** The mini-player has its own compact layout with no title bar. Drag anywhere to move the window. Hover to show the title, previous / play-pause / next, and a seek bar. Audio shows its cover art, and video windows keep the video's aspect ratio. Double-click to leave the mini-player.
- **NEW - More menu:** The ⋯ menu opens instantly next to its button. Sleep timer and track options are in submenus, and items show their keyboard shortcuts.
- **NEW - Shortcuts:** `Q` toggles the play queue, `Shift+S` stops, `Ctrl/Cmd+,` opens Settings, `I` shows media info, and `Shift+Left/Right` seeks 30 seconds. You can rebind all of them.
- **NEW - Remaining time:** Click the duration next to the seek bar to switch between total and remaining time. The choice is remembered.
- **NEW - Tray controls:** The tray menu now has Play/Pause, Next and Previous. The tray tooltip shows what is playing. On Windows, left-clicking the tray icon restores the window.
- **NEW - Updates:** Before an update installs, Dacx shows what's new in that release and links to the full release notes. You can cancel a Windows update download.
- **NEW - Network paths:** Files on network shares (`\\server\share`) now open when you pick them in a dialog, drop them, or reopen them from Recents or the queue. Network paths from the command line, Open With, playlist files and media controls are still refused.
- **NEW - Formats:** Folder scans, drops and pickers now accept `m4b`, `oga`, `mka`, `ac3`, `eac3`, `dts`, `amr`, `weba`, `3gp` and `f4v` files.
- **Update - Empty state:** Open File is now the main action. Reopen Last only appears when there is a recent file, and your most recent files are listed for one-click opening.
- **Update - Audio view:** The now-playing view adapts to small windows and the mini-player instead of overflowing. It shows the album name when the file has one.
- **Update - Transport:** Previous and Next are disabled when there is nothing to go to. The volume icon shows muted, low and high levels.
- **Update - Settings:** Wide controls move under their label in narrow windows. You can reach and select accent colors with the keyboard.
- **Update - Playback speed:** The speed chip and on-screen message show the exact rate instead of the nearest preset.
- **Update - Messages:** A new message now replaces the one on screen instead of waiting in a queue. Loading a folder or playlist with missing files shows one summary instead of one message per file.
- **Fix - Add files to queue:** The picker now shows audio files on Windows and Linux, opens in your last folder, and reports errors.
- **Fix - Track title:** The audio view and Media Info show the title and artist even when system media controls are turned off. They no longer keep the previous file's title.
- **Fix - System media controls:** Windows and macOS media overlays no longer keep the previous track's artist or album when the new track has none.
- **Fix - Window size:** Dacx no longer saves the window size while maximized, fullscreen, minimized or in the mini-player. A maximized window reopens maximized, and an invalid saved size falls back to the default.
- **Fix - Mini-player toggle:** Toggling the mini-player twice quickly no longer loses the previous window size. If the resize fails, Dacx stays in the normal layout. Always-on-top returns to your current setting.
- **Fix - macOS install location:** The warning shown when Dacx runs outside `/Applications` now appears instead of failing silently.
- **Fix - macOS screenshot folder:** A custom screenshot folder keeps its access permission after you open files or clear Recents.
- **Fix - Scroll volume:** Trackpads and high-resolution mouse wheels now change volume by one step per notch instead of jumping to 0 or 100.
- **Fix - Click to pause:** Clicking the video pauses or resumes immediately instead of after about half a second.
- **Fix - Windows blur:** Focusing the window no longer re-applies blur and nudges the window size when blur is off, maximized or fullscreen.
- **Fix - Performance:** Volume, equalizer, subtitle and appearance sliders and window moves now save settings after you stop changing them, instead of rewriting the settings file on every step. Playback position updates no longer rebuild the controls on every tick, and changing a setting no longer rebuilds the whole app.
- **Fix - Dialogs:** Advanced playback and Media Info dialogs now fit small windows.
- **Codebase:** The player screen is split from one 5,400-line file into focused controllers and widgets. Light and dark themes share one builder, and unused code is removed.
- **Testing:** Audit 9 adds documented failure modes and E2E tests for every change above, each writing a JSON report under `test-results/e2e/<os>/`.

## Changes in `v1.0.2:`
- **PKG:** Updated Dependency & Packages.

## Changes in `v1.0.1:`
- **Flutter:** Updated Flutter to `3.47.9`.
- **PKG:** Dependency & Package updates.
- **CA CERT:** Updated CA Cert.

## Changes in `v1.0.0:`
- **NEW - Opt-in advanced playback tools:** Per-file audio/subtitle sync, A-B repeat, playback markers, and subtitle appearance controls are available behind a disabled-by-default setting, preserving Dacx's minimalist default experience.
- **Fix - Resume after quit:** Closing the window, quitting from the tray, or pressing `Cmd+Q` now saves the current position before exit. Pausing also saves it, so pause → seek → quit resumes at the seek target instead of an older position.
- **Fix - Window size and position on quit:** A resize or move made just before quitting is now saved.
- **Fix - macOS Recents:** Deleted or moved files no longer stay in Recents because a saved file-access bookmark exists. Dacx now resolves the bookmark and checks the file is really there.
- **Fix - Playlist import encodings:** `.m3u` / `.pls` files in Latin-1 / Windows-1252 or UTF-16 now import instead of failing. A UTF-8 byte-order mark no longer ends up in the first entry.
- **Fix - Stalled update downloads:** An update download that stops receiving data now fails after 60 seconds instead of hanging the progress dialog. Partial downloads are deleted.
- **Fix - Windows update cancelled:** If the UAC prompt is cancelled or the installer fails, Dacx now reopens the installed version instead of staying closed.
- **Fix - Log privacy:** Copied debug logs now fully redact paths that contain spaces (such as `C:\Users\Jane Doe\…`), quoted paths, and local paths in stack traces. URLs with embedded credentials are stripped instead of shown raw.
- **Fix - macOS startup:** The hardware-acceleration check no longer runs a second time on the UI thread before the first frame.
- **Fix - Linux media artwork:** Artwork for system media controls is now stored in your cache folder (`~/.cache/dacx`) instead of a shared `/tmp` folder, and multiple windows no longer overwrite each other's artwork.
- **Fix - Responsiveness on slow drives:** Opening, dropping, and checking Recents no longer freeze the window while a slow or disconnected network drive is checked.
- **Fix - Hardware decoding setting:** Changing hardware decoding at runtime now updates mpv's `hwdec` property instead of recreating the video controller, which media_kit cannot do mid-playback.
- **Fix - Relative file paths:** Relative paths passed on the command line or forwarded from a second Dacx instance (including Windows Open With) now resolve against the launching process's working directory.
- **Fix - Marker rename dialog:** The rename text field is no longer disposed while the dialog's exit animation is still running.
- **Fix - Window visuals:** Blur, opacity, theme, and minimize-to-tray are reapplied only when those settings actually change, instead of on every settings update.
- **Fix - macOS custom shortcuts:** Custom keybinds recorded with `Cmd` now trigger their action. Before, they never matched, and the action's default shortcut also stopped working.
- **Fix - Open With batches:** If opening a batch of files forwarded from another Dacx instance fails, the error is now logged instead of escaping as an unhandled error. Later Open With requests still open.
- **Fix - Linux media controls shutdown:** Closing Dacx while the MPRIS name probe is running no longer initializes the media session after shutdown.
- **Update - Error log:** Errors are now kept in `errors.log` in Dacx's app data folder (redacted, capped at 512 KB) so they survive a crash or quit. Copying the debug log includes errors from earlier sessions; **Clear** deletes the file.
- **Update - Windows update hardening:** The update helper keeps the verified installer locked until installation finishes, so it cannot be swapped after verification. Opening files from a second Dacx instance can no longer be blocked by a stalled sender.
- **Update - Naming:** Linux media controls now show "Dacx". New screenshots go to `Pictures/Dacx`; an existing `Pictures/DACX` folder keeps being used.
- **PKG:** The unused JNI bridge (`libdartjni`) is no longer built or bundled on Windows and Linux; packaging now fails if it appears.
- **Release safety:** `npm run u` now synchronizes versioned download URLs and creates the next blank changelog section. Release notes, artifact names, checksums, Ed25519/GPG signatures, remote bytes, and platform playback receipts are verified before publication. `test-all` now reads Flutter's final summary and explicit failure markers, handling CRLF output and stale progress counts.
- **Platform E2E:** Windows, macOS, and Linux runners generate deterministic media fixtures and retain repeatable JSON evidence. Packaged smoke requires real duration/playing proof from the exact versioned candidate; process survival alone cannot pass. The macOS packaged smoke test setup is fixed.
- **Dependencies:** Updated Flutter/Dart package baselines, `file_picker`, and `tray_manager` 0.8.0; added `nativeapi_flutter`; kept `dbus` on the newest 0.7 release because `anni_mpris_service` (MPRIS) does not yet support 0.8; refreshed bundled CA certificates (`cacert.pem`).
- **Flutter:** Updated flutter to `3.47.7`.

## ℹ️ Release Info

- **GPG Signed:** My public key is attached to every release to ensure authenticity.
- **GPG Key:** Public key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc .
- **Code Signing:** macOS releases are fully signed and notarized. Windows MSIs are fully signed using Azure Artifact Signing. Linux packages are signed with my GPG signature.
- **Windows package:** Dacx ships MSI (not EXE) on Windows, including betas; that is intentional for the self-updater.
- **More info:** See the [README](https://github.com/BurntToasters/Dacx/blob/main/README.md), [FAQ](https://help.rosie.run/dacx/en-us/faq), and [BCLS](https://github.com/BurntToasters/BCLS).
