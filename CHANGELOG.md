<!-- > [!NOTE]
> 🅱️ This is a Beta build. -->

# ⬇️ Downloads

| <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/windows.png" /> Windows | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/mac.png" /> macOS | <img height="20" src="https://raw.githubusercontent.com/BurntToasters/bcls/main/media/linux.png" /> Linux |
| :--- | :--- | :--- |
| **MSI:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-Windows-x64.msi) | **[Universal DMG](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-macOS.dmg)** | **AppImage:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-Linux-x86_64.AppImage) |
| | **[Universal ZIP](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-macOS.zip)** | **DEB (Deprecated):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-Linux-amd64.deb) |
| | | **RPM (Deprecated):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-Linux-x86_64.rpm) |
| | | **Flatpak:** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-Linux-x86_64.flatpak) |
| | | **TAR (Generic Linux):** [x64](https://github.com/BurntToasters/Dacx/releases/download/v1.0.0/Dacx-Linux-x86_64.tar.gz) |

> [!IMPORTANT]
> The `.asc` files are my normal GPG signatures which you can verify using my GPG Public Key: https://tuxedo.rosie.run/GPG/BurntToasters_0xF2FBC20F_public.asc.
>
> ⚠️ Arm64 Linux and Windows Binaries are NOT available at the moment. Its something I may get around to in the future but its not a priority.

### ℹ️ Enjoying Dacx? Consider [❤️ Supporting Me! ❤️](https://rosie.run/support)

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
