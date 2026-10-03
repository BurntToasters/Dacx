# Manual QA checklist (pre-stable)

## Platform and package E2E failure inventory

Write and run these checks before changing dependency or packaging code. A platform
check fails closed: skipped host tools are reported as skipped, never as proof.

- Dependency resolution can select an incompatible `dbus`, `file_picker`, or
  `tray_manager` API while the lockfile still looks valid.
- Tray initialization can compile but fail at runtime because icon paths,
  listener callbacks, menu constructors, or destroy calls changed.
- Linux MPRIS and idle-inhibit calls can compile but lose D-Bus connection
  lifetime, property types, or command dispatch after a `dbus` upgrade.
- File-picker open, directory, multi-file, and save flows can return changed
  path/URI shapes or platform exceptions.
- A package can contain the app binary but omit native media libraries, runtime
  DLLs, update helper, desktop metadata, licenses, or Flatpak permissions.
- A candidate package can have the wrong version, stale hash, missing signature,
  invalid signature, or an artifact from another platform.
- A release artifact can use a canonical unversioned filename while a harness
  incorrectly treats the filename as the version source; version proof must
  come from the required release argument plus checksum/manifest metadata.
- A supplied executable can be unrelated to the inspected package, or a
  Flatpak wrapper can lose repeated command arguments, producing a misleading
  launch result.
- Windows MSI can fail to install, launch, open a deterministic fixture, or pass
  Authenticode/Ed25519 verification.
- macOS DMG/ZIP can fail to mount, launch, pass codesign/Gatekeeper checks, or
  open a deterministic fixture.
- Linux AppImage/Flatpak can fail to launch without host `libmpv`, expose an
  incorrect desktop entry, or lack required D-Bus/media permissions.
- Smoke tooling can report success after a timeout, missing executable, missing
  fixture, skipped trust command, child process crash, or process-tree leak.
- An app can write a passing receipt and immediately crash, or report a later
  playback error after initial success; both must invalidate package proof.
- A process can remain alive without opening the fixture or entering a playing
  state; process survival is not playback proof. A playback receipt must be
  produced by the env-gated probe inside the candidate app and bound to this
  run/version/fixture. Normal launches never activate the probe.
- A macOS DMG can remain mounted after an extraction/copy failure if detach is
  not in a finally path; a tarball can write outside staging through traversal
  entries if archive paths are not checked before extraction.
- E2E output can omit command lines, host/version data, fixture hashes, logs, or
  failure exit codes, preventing repeatable release audit.
- Repeated smoke runs can overwrite evidence or mix artifacts from different
  versions/platforms.

The deterministic fixture and platform smoke harness below must emit a JSON
report plus raw command logs under `test-results/e2e/<os>/` or
`test-results/release-proof/<version>/`.

## Repeatable desktop E2E commands

Generate one stable WAV/SRT pair per platform runner:

```powershell
node scripts/platform-release-smoke.js fixtures `
  --output test-results/e2e/windows/fixtures `
  --report test-results/e2e/windows/fixture-report.json
```

Run real-player proof on each desktop host. Set `DACX_E2E_REPORT` to a unique
OS/version path; do not reuse another host's report.

```text
DACX_E2E_FIXTURE=<fixture>/release-smoke.wav
DACX_E2E_VERSION=<version>
DACX_E2E_RUN_ID=<unique-run-id>
DACX_E2E_REPORT=test-results/e2e/<os>/desktop-playback.json
fvm flutter test integration_test/platform_release_smoke_test.dart -d <windows|macos|linux>
```

Run package candidate smoke only with an executable extracted or installed
from that exact candidate. `--no-launch` is inspection only and returns exit
code 2. It never produces release proof.

```text
node scripts/platform-release-smoke.js package --platform <win|mac|linux> \
  --artifact <release-artifact> \
  --extract \
  --fixture <fixture>/release-smoke.wav \
  --expected-sha256 <64-hex-digest> \
  --signature <detached-signature-if-required> \
  --checksums <sha256sum-file> \
  --proof-metadata <release-proof.json> \
  --version <version> \
  --playback-report test-results/e2e/<os>/desktop-playback.json \
  --report test-results/release-proof/<version>/<os>.json
```

Use `--executable` instead of `--extract` when package installation happens
outside the harness. Use `--launcher flatpak` plus repeated `--launch-arg`
values for a Flatpak wrapper. A supplied external executable must be bound by
the proof metadata executable hash; extracted binaries are bound to staging.

Harness report records top-level version/schema, artifact bytes/hash, fixture
hash, child command/output, process-tree cleanup, playback receipt, required
runtime paths, and host trust commands. Windows runs PowerShell Authenticode
validation; macOS runs `codesign` and `spctl`; Linux runs GPG validation when
`--signature` is supplied. Missing host tools, missing trust inputs, or a
process that merely survives the timeout leave report `incomplete`, not
`passed`. Only a fresh receipt from the candidate app's env-gated probe, with
duration, playing state, matching version/run ID/fixture, and no error, can
complete playback proof.

`--extract` prepares MSI administrative installs, macOS DMG/ZIP bundles, and
Linux tarballs into report-local staging. Linux AppImage launches directly on
Linux. Flatpak requires an explicit wrapper executable such as
`flatpak run run.rosie.dacx`; deb/rpm install policy stays outside harness.

Current dependency boundary: `dbus` remains on 0.7.15 because `desktop_drop`
0.8.4 requires `dbus ^0.7.10`. Upgrade `dbus` only after a compatible
`desktop_drop` release exists; do not force an override in release builds.

Run on **Windows (MSI or debug)**, **macOS 15+**, and **Linux**: prefer **AppImage** (ideally via [AppManager](https://github.com/kem-a/AppManager)) plus optionally one deb/rpm. Use a short local audio file, a video file, and an `.m3u` / `.pls` with 2+ entries.

Tick items as you go before a stable cut. Fix failures as they surface rather than stacking features.

## Playback

- [ ] Open File / Open Folder / Open Playlist from UI (and macOS File menu where applicable)
- [ ] Empty state: ⋯ more menu **Open URL** works **without** media; `Ctrl/Cmd+U` opens URL dialog
- [ ] Drag-and-drop a supported file onto the empty state
- [ ] Play / pause / stop / seek / mute / volume
- [ ] Cycle playback speed from transport chip and `[` / `]` / `\`; OS Now Playing / SMTC / MPRIS reflects rate
- [ ] Loop modes; queue prev/next wraps or stops as expected (tooltips: Shift+P / Shift+N)
- [ ] Reopen Last restores the previous file (Ctrl/Cmd+R)
- [ ] With **Resume from last position** on: seek into a file, quit or stop, reopen the same file (or Reopen Last) and land near the saved position
- [ ] With resume on: seek near the end, reopen; resume should clear / start near the beginning (no stuck near-end seek)
- [ ] Load external audio / subtitle from the more menu when media is open
- [ ] Sleep timer (⋯ menu): set 15/30/45/60 → playback stops when it fires; Off cancels

## Queue / playlists

- [ ] Multiple files enqueue; drag-reorder works (handle visible; screen reader mentions reorder)
- [ ] Shuffle toggle on drawer **and** more menu (OS shuffle stays in sync); quit/relaunch keeps preference
- [ ] Clear queue
- [ ] Save Playlist exports `.m3u`; re-open that playlist and a `.pls`
- [ ] Quit and relaunch shows empty home (no auto-loaded queue/media)

## OS chrome

- [ ] Media session / Now Playing / SMTC / MPRIS shows title + artwork and responds to play/pause
- [ ] Media-session artwork: play a file with embedded cover art; OS chrome shows art (not blank/stale from a prior track)
- [ ] Display does not sleep while video plays (idle inhibit); leave playing ≥1-2 min
- [ ] Windows: Jump List recents + taskbar progress while playing
- [ ] macOS: File menu + Dock menu New Window / Open; Open Recent → Clear Menu
- [ ] Linux AppImage: Check for Updates mentions AppManager and/or replacing the AppImage; deb/rpm shows package guidance (not “portable”)
- [ ] Linux AppImage/tar/Flatpak play a local file **without** installing distro libmpv. deb/rpm still need the distro package.
- [ ] Windows: second launch with no file restores the existing window (does not spawn a second instance). Open With / file argument while tray-hidden also restores and focuses.
- [ ] macOS: Dock click restores a tray-hidden window
- [ ] Fullscreen: chrome + cursor auto-hide; mouse/key reveals; click pauses; scroll changes volume
- [ ] Clear queue asks for confirmation; confirming stops playback if something is playing
- [ ] Linux MPRIS: lock-screen scrubber does not jitter from Seeked spam while playing
- [ ] Minimize to tray (Appearance, off by default): close hides; tray icon is visible on Windows and macOS; tray Show restores; tray Quit exits

## Settings / updates

- [ ] Escape from Settings returns to the player (same as back)
- [ ] Escape closes the play queue drawer; a second Escape exits fullscreen when active (including OS/title-bar fullscreen)
- [ ] Keybind capture: Escape cancels without saving a binding
- [ ] Opening an unrecognized extension warns with a snackbar (playback may still be attempted)
- [ ] Failed external audio/subtitle load shows a snackbar
- [ ] Flatpak (if tested): dropping inaccessible files mentions sandbox / inaccessible paths
- [ ] Appearance: theme, accent; Win/mac blur + opacity without Experimental master switch
- [ ] Turning **Experimental off** on Win/mac does **not** clear Appearance blur / opacity
- [ ] Hardware decode change applies without requiring app restart (copy matches behavior)
- [ ] Settings → Keyboard shortcuts opens the full editable F1 keybinds dialog
- [ ] Experimental section: Linux compositor blur appears when master is on (WIP lane; expected unstable). Multi-audio mix must **not** appear.
- [ ] Seek thumbnails toggle lives under Playback settings (not the more menu)
- [ ] Check for Updates opens a sensible path (self-update on Win MSI / macOS Applications; Linux package guidance)
- [ ] Windows MSI self-update burn-in: `dacx-update-helper.exe` next to `dacx.exe`; after Apply, no `.ps1` under `%LOCALAPPDATA%\Dacx\updates`; `helper.log` shows wait → sha256 → msiexec → `relaunched …\dacx.exe`; app returns like macOS update & restart
- [ ] Windows recovery boundary: `v0.11.0` / `v0.11.1-beta.1` requires one manual `v0.11.1` MSI install; test a later in-app update from `v0.11.1`
- [ ] Force a self-update failure: dialog retains the diagnostic error and **Download the update manually** opens the Rosie update page for stable builds or the exact GitHub prerelease page for beta builds
- [ ] Flatpak (if tested): empty-state copy mentions picker; update guidance mentions reinstalling the `.flatpak` (not Flathub / `flatpak update`)

## Trust smoke

- [ ] Unsupported / unsafe paths (e.g. credential URLs) are refused with feedback
- [ ] Screenshot save works when media is playing
- [ ] Media Info shows title / artist / album when tags are present
- [ ] macOS: updated app remains Developer ID signed / Gatekeeper-happy after self-update
- [ ] Windows release build: MSI passes Ed25519 manifest, SHA-256, and configured Artifact Signing publisher checks
