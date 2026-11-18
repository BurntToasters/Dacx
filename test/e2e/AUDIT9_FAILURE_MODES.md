# Audit 9 E2E failure inventory

Each mode id `M<finding>.<k>` below maps to a test in one of the
`test/e2e/audit9_*_e2e_test.dart` files. Each test file writes a JSON report
via `test/support/audit9_report.dart`, and the report lists every mode id that
passed. The regression tests must fail if the corresponding lib fix is
reverted.

## Finding 1: enqueue picker excludes audio

- M1.1 The enqueue picker must request `FileType.custom` (never
  `FileType.media`, which is images and videos only on Windows and Linux) with
  allowed extensions covering every `PlayerPathUtils.supportedExtensions` entry
  and the playlist extensions from `M3uPlaylist.extensions`.
- M1.2 It must pass an existing `lastOpenDirectory` as `initialDirectory`.
- M1.3 After a pick, `lastOpenDirectory` must become the directory of the
  first picked file, even when the queue already has items and nothing loads.
- M1.4 A picked audio file must reach the queue (picker result to queue).
- M1.5 A `PlatformException` from the picker must show the "File picker
  failed" snackbar with the platform detail, not fail silently.
- M1.6 Any other picker error must show the "Unable to open file picker"
  snackbar.
- M1.7 A cancelled pick must show no snackbar and leave the queue unchanged.

## Finding 2: display metadata tied to media session

- M2.1 With the media session setting off, the audio view must still show the
  mpv tag title and artist of the loaded track.
- M2.2 With the media session off and no tag title, the title falls back to
  the source display name and no artist is shown.
- M2.3 With the media session on, the OS bridge still receives the title and
  artist (Windows and macOS bridges; Linux uses MPRIS and is skipped); with it
  off, nothing is sent to the OS bridge.
- M2.4 When the source changes, the previous track's title and artist must
  disappear at once and must not be shown while the new track's metadata query
  is still pending.
- M2.5 Metadata that resolves after a newer load started must never be shown
  (load-generation guard).
- M2.6 After stop, loading another source whose metadata is pending must not
  show the artist of the track played before the stop.
- M2.7 With the media session on, one load queries mpv for title and artist
  exactly once each (no second query for the display copy).

## Finding 3: window geometry saved in wrong states

Storage part only (`test/e2e/audit9_storage_e2e_test.dart`); the main.dart
save-gating modes are added later by the app-shell package.

- M3.1 `windowSize` must return null when the stored width or height is NaN
  or infinite.
- M3.2 `windowSize` must return null when the stored width is below 480 or the
  stored height is below 320, checked separately per axis (a minimized or
  collapsed window must never be restored).
- M3.3 `windowSize` must still return a stored size at exactly 480x320 and
  above, and `windowPosition` must still return stored values (no
  over-rejection).
- M3.4 `window_maximized` must default to false, round-trip true and false,
  persist across a new service on the same prefs after a flush, be listed in
  `frozenPreferenceKeys`, and leave `currentSchemaVersion` at 4.

App shell part (`test/e2e/audit9_shell_e2e_test.dart`, `DacxApp` with a mocked
`window_manager`; events are delivered through the plugin channel and the
180 ms save debounce is pumped).

- M3.5 A resize or move event while the window is maximized must not save
  size or position (a previously stored normal size stays), and must record
  `windowMaximized` as true.
- M3.6 A resize or move event while fullscreen must not save size or position
  and must leave `windowMaximized` unchanged.
- M3.7 A resize or move event while minimized must not save size or position
  and must leave `windowMaximized` unchanged.
- M3.8 A resize or move event on a normal window must save the real size and
  position and set `windowMaximized` back to false after it was true.
- M3.9 With `rememberWindow` off, no event may save size, position or the
  maximized flag.
- M3.10 Startup restore: with `rememberWindow` and `windowMaximized` true the
  saved normal position is applied first and the window is then maximized; with
  either one false the window is never maximized and no maximize call is made.

## Finding 4: mini-player toggle state

- M4.1 A second toggle while the first is still running is ignored, so the
  saved pre-mini size is not overwritten and leaving mini mode restores the
  original size.
- M4.2 If the window resize fails on entry, mini mode must not turn on (no exit
  button, no "Mini-player on" message) and the failure must not leave the
  toggle stuck.
- M4.3 After a failed entry, a later toggle must work normally.
- M4.4 If the window restore fails on exit, the player stays in mini mode.
- M4.5 On exit, always-on-top is restored from the current
  `settings.alwaysOnTop`, not from the value captured on entry.

## Finding 5: batch load failure flood

- M5.1 Loading many files that all fail to open from one batch must show a
  single summary message with the count ("N files could not be opened") and
  none of the per-file messages.
- M5.2 When some files fail before one opens, the summary counts only the
  failures and the file that opens is played.
- M5.3 A batch with exactly one failure keeps the specific per-file message.
- M5.4 A single-file open failure keeps today's specific message.
- M5.5 The summary is a plural l10n string: one and many counts read
  correctly.

The missing-file (prune recents) path cannot be reached with the headless
harness because existence probing is skipped for headless media, so the
once-per-batch prune is covered by code review only.

## Finding 6: macOS install warning never shows

`DacxApp` takes an injectable install-location check so the dialog is
testable off macOS.

- M6.1 When the check says to warn, the install-location dialog (localized
  title and message) must be visible after the first frames, with no
  exception raised while building or showing it.
- M6.2 The dialog must close through its Close button, and must show only once
  even when the app rebuilds afterwards (theme change).
- M6.3 When the check says not to warn, no dialog is shown.
- M6.4 Showing the dialog must log exactly one `macos_install_location_warning`
  debug event.
- M6.5 With no injected check, the production default must not show the dialog
  on a non-macOS host.

## Finding 7: screenshot folder bookmark pruned

- M7.1 The bookmark for the current `screenshotDir` must survive
  `addRecentFile` pruning even when no recent file lives under it, while an
  unrelated bookmark is still pruned.
- M7.2 The screenshot bookmark must survive `clearRecentFiles`, which must
  prune to the pinned set instead of removing the whole bookmark pref.
- M7.3 The screenshot bookmark must survive `pruneRecentFiles`.
- M7.4 A bookmark on a parent of the screenshot folder, and a key written with
  a trailing slash or backslashes, must also be kept (covering-directory
  rules from `BookmarkRetentionPolicy`).
- M7.5 After the screenshot folder changes, the old key must no longer be
  protected and the new one must be; after the folder is cleared nothing is
  pinned and the key is pruned.
- M7.6 `clearRecentFiles` with no screenshot folder must still remove every
  bookmark (the pin must not leak or keep unrelated keys).

## Finding 8: fullscreen dock hides while in use

Modes: pending.

## Finding 9: scroll volume per event

- M9.1 Accumulator: a single event of 50 px or more emits exactly one step in
  the scroll direction (up raises, down lowers): a 53 px Linux wheel notch, a
  100 px Windows wheel notch and a 300 px event each give exactly one step.
- M9.2 Accumulator: small deltas accumulate and emit one step only when the
  total reaches 50 px (five 12 px events give one step, four give none), then
  start over.
- M9.3 Accumulator: a direction flip discards the accumulated opposite delta.
- M9.4 Accumulator: a gap of 200 ms or more discards the accumulated delta; a
  gap below 200 ms keeps it.
- M9.5 Accumulator: zero-delta events emit nothing and do not disturb state.
- M9.6 Pumped screen: 53 px and 100 px mouse wheel notches each change volume
  by exactly 5, while fifteen 3 px trackpad events do not change volume at all.
- M9.7 Pumped screen: volume is still clamped to 0..100 when scrolling.

## Finding 10: Windows blur nudge on focus

Windows-specific modes run the real Windows branch on a Windows host; on other
hosts the test asserts the focus path does nothing visual. Native calls are
recorded through mocked `window_manager`, `flutter_acrylic` and window-method
channels.

- M10.1 A focus event with blur enabled on Windows must re-apply the window
  effect once and must send no size change (no `setBounds`) to the window.
- M10.2 A focus event with blur disabled must not touch the window effect,
  opacity or size.
- M10.3 A settings-driven visual change (blur strength) in a normal window
  must still re-apply the effect and nudge the size by one pixel and back.
- M10.4 The same settings-driven change while maximized or fullscreen must
  re-apply the effect but never change the size.
- M10.5 Focus while maximized or fullscreen with blur enabled must send no
  size change.

## Finding 11: previous and next always enabled

Modes: pending.

## Finding 12: advanced playback per-tick notify

- M12.1: position ticks with advanced tools off and a source loaded notify
  listeners zero times.
- M12.2: position ticks with tools on, a source loaded and no A-B loop notify
  listeners zero times, and the latest position is still stored.
- M12.3: A-B loop transitions (A set, B set, cleared) each notify; ticks while
  the loop is active, including a wrap back to A, do not notify and keep the
  loop state and mpv loop properties intact.
- M12.4: duration changes and source changes still notify, and duration
  changes still re-filter markers that lie beyond the duration.
- M12.5: many reads of markers with unchanged state decode once (one settings
  lookup, identical list instance), even across position ticks.
- M12.6: markers are re-read after addMarker, renameMarker and deleteMarker.
- M12.7: markers written to settings outside the controller, and a settings
  reset, invalidate the cache.
- M12.8: switching source returns the new source's markers, and switching back
  returns the first source's current markers.

## Finding 13: per-tick preference writes

Writes are counted with a counting `SharedPreferencesStorePlatform` and fake
time (`fakeAsync`).

- M13.1 A burst of volume setter calls must read back the latest value at
  once, notify listeners per change, perform zero store writes before the
  debounce, and exactly one store write for the volume key after it.
- M13.2 A burst of EQ band and EQ preset changes must read back at once, write
  nothing before the debounce and one write per key after it with the last
  value.
- M13.3 Subtitle font size, position, outline size, text color and outline
  color must be debounced the same way and read back at once.
- M13.4 Window opacity and blur strength must be debounced the same way.
- M13.5 Window size and position set in one tick must not write before the
  debounce and must flush together after a single debounce.
- M13.6 Every new change must restart the debounce and the stored value must
  be the last one set.
- M13.7 `flushPendingWrites` must write every pending key immediately, leave
  nothing pending (no extra writes after the debounce elapses), and complete
  with the values readable from a fresh service on the same prefs.
- M13.8 `AppExitHooks.runAll` must flush pending writes, and `dispose` must
  flush them too.
- M13.9 `resetAll` must drop pending writes so a debounced value is never
  written back after a reset.

## Finding 14: app-wide rebuild on settings writes

Setter equality part only; the main.dart rebuild narrowing is separate.

- M14.1 Bool, enum and string setters must do no store write and no
  `notifyListeners()` when the value equals the current value, including
  defaults that were never stored.
- M14.2 Clamped or rounded numeric setters must compare after normalization
  (volume above 100 when already 100, subtitle position rounding, opacity
  below the minimum when already at the minimum).
- M14.3 Deep equality: setting `eqBands` or `keybinds` to an equal list or map
  must not write or notify; a changed one must still do both.
- M14.4 `addRecentFile` of the current head, `clearRecentFiles` with nothing
  to clear, `resetKeybinds` when empty, and window geometry equal to the
  current value must not write or notify.
- M14.5 A changed value must still write and notify exactly once (the
  short-circuit must not swallow real changes).

App shell part (`test/e2e/audit9_shell_e2e_test.dart`).

- M14.6 Settings writes that no app-level input reads (volume, speed, OSD,
  recent files) must not rebuild the `MaterialApp`.
- M14.7 A theme mode change must rebuild the `MaterialApp` and apply the new
  mode.
- M14.8 An accent color change must rebuild the `MaterialApp` and change the
  theme color scheme.
- M14.9 Window blur enable, blur strength and window opacity changes must
  rebuild the `MaterialApp` and update its themes.
- M14.10 A platform brightness change while following the system theme must
  still rebuild the `MaterialApp`.
- M14.11 The player home must still be rebuilt on every settings write, since
  `PlayerScreen` reads settings in `build` without its own setState.

## Finding 15: sync filesystem calls on UI isolate

Settings part only; consumers (player and settings screens) validate existence
where the value is used and are handled by a later package.

- M15.1 The `lastOpenDirectory` setter must store a path that does not exist
  and must not create any `Directory` object (no `existsSync` on the UI
  isolate), while still rejecting NUL and `..` segments.
- M15.2 The `screenshotDir` getter and setter must not create any `Directory`
  object and must return a stored path that does not exist, while the setter
  still rejects NUL and `..` segments.
- M15.3 Open file, open folder and enqueue pickers must pass the stored
  `lastOpenDirectory` as `initialDirectory` when it exists and null when it
  does not (existence checked asynchronously where the value is used).
- M15.4 Taking a screenshot with a `screenshotDir` that does not exist must
  fall back to the default location exactly like an unset directory and must
  not create the missing directory.
- M15.5 Taking a screenshot with an existing `screenshotDir` must still save
  there.
- M15.6 `player_screen.dart` must never pass `settings.lastOpenDirectory`
  straight to a picker (source scan).

## Finding 16: click-to-pause delay

- M16.1 A single click on the media surface toggles play and pause as soon as
  Flutter's own double-tap wait (300 ms) has elapsed, with no extra timer.
- M16.2 A double click toggles fullscreen and never toggles play and pause.
- M16.3 The media surface no longer owns a tap timer (source scan).

## Finding 17: content switcher never animates

Modes: pending.

## Finding 18: fullscreen chrome relayouts video

Modes: pending.

## Finding 19: mini-player layout

Modes: pending.

## Finding 20: audio view overflow

Modes: pending.

## Finding 21: more menu

Modes: pending.

## Finding 22: empty state

Modes: pending.

## Finding 23: snackbar queueing

Modes: pending.

## Finding 24: speed label shows nearest preset

- M24.1 A rate between presets (1.1) must label as `1.1×`, never the nearest
  preset (`1×` or `1.25×`).
- M24.2 Exact presets keep today's output byte-for-byte: `0.5×`, `0.75×`,
  `1×`, `1.25×`, `1.5×`, `2×`.
- M24.3 Trailing zeros are trimmed and at most two decimals are shown
  (`0.25×`, `1.13×` for 1.126, `2×` for 1.999, `4×`, `1.33×`).
- M24.4 A non-finite rate must not throw and must still produce a non-empty
  label (previous nearest-preset fallback).
- M24.5 The transport speed chip (the only widget caller) shows the real rate
  for an off-preset speed.

## Finding 25: settings rows at narrow widths

Modes: pending.

## Finding 26: updater notes and cancel

Modes: pending.

## Finding 27: tray controls

Modes: pending.

## Finding 28: fixed-width dialogs

- M28.1 Advanced playback dialog in a 400 px window: its content box declares
  a width no larger than `dialogWidth` (352) and lays out with no overflow.
- M28.2 Media info dialog in a 400 px window: same declared-width and
  no-overflow contract, using its default width.
- M28.3 In a 1200 px window both dialogs keep 520 as the content width.
- M28.4 At the 480 px minimum window the advanced dialog declares 432 and
  lays out without overflow; in a 320 px window the media info dialog declares
  the 280 px floor and lays out without overflow exceptions.

## Finding 30: duplicated theme builders

The light and dark themes come from one builder. Expected values are built in
the test with the previous per-brightness logic and compared field by field.

- M30.1 For blur off and blur on, the light `ThemeData` must equal the
  previously produced one (colors, scaffold and canvas colors, divider, popup
  menu, card, snack bar, density, Material 3, brightness) and its `WindowVisuals`
  extension must match every color.
- M30.2 The same equivalence for the dark `ThemeData` and its extension.
- M30.3 With blur on, the card theme must be set and the scaffold background
  transparent; with blur off, the card theme must stay unset.

## Finding 31: dead and constant members

`AccentColor` / `LoopMode` part (`test/e2e/audit9_storage_e2e_test.dart`).
`LoopMode.label` is still read by
`test/screens/settings_screen_general_test.dart`, so it is left in place and
reported.

- M31.1 `AccentColor` must no longer declare a hard-coded English `label`
  (source scan of the enum body).
- M31.2 Removing the label must not change the persisted identity of any
  accent: every `AccentColor` value round-trips by name and keeps its color.

- M31.10 EqPreset (equalizer part): `EqPreset.label` is still read by
  test/services/equalizer_service_test.dart, so it stays. The equalizer
  dropdown must not depend on it: `eqPresetLabel` returns a non-empty
  localized label for every preset id and for an unknown id without throwing.

## Finding 32: missing media extensions

- M32.1 `supportedExtensions` contains m4b, oga, mka, ac3, eac3, dts, amr, weba,
  3gp and f4v, and `isSupportedExtension` accepts them in any case.
- M32.2 The audio set contains the eight audio extensions (so a file with one
  gets the audio surface via `isAudioExtension`, including mka and weba), the
  video set contains 3gp and f4v, and the sets stay disjoint.
- M32.3 The media folder scanner returns files with each new extension and
  skips an unsupported control file.
- M32.4 Drop batch policy keeps a dropped path with each new extension.

## Finding 33: duplicated duration formatters

- M33.1 `PlayerController.formatDuration` output for zero, sub-minute,
  59:59, exactly one hour, 10+ hours and 100+ hours stays `mm:ss` or `h:mm:ss`.
- M33.2 The seek slider semantics value shows the same text as
  `formatDuration` for position and duration (hour case included).
- M33.3 The OSD overlay time text equals `formatDuration` for position and
  duration (hour case included).
- M33.4 The advanced playback dialog marker subtitle equals `formatDuration`
  of the marker position (hour case included).
- M33.5 No private duration formatter remains in seek_slider.dart,
  osd_overlay.dart or advanced_playback_dialog.dart.

## Finding 34: stale media overlay artist and album

Modes:

- M34.1: a full track metadata update (`updateMetadata`) omits `replace: true`, so the native bridges keep the previous track's artist/album.
- M34.2: an untagged track (null artist and album, no art) does not send explicit null/empty artist, album and artUri together with `replace: true`.
- M34.3: a tagged track update drops `replace: true` or its artist/album/title values.
- M34.4: a position/playing-only update (`updatePosition`) sends a `replace` key and wipes metadata that should be left unchanged.
- M34.5: the Linux MPRIS path stops building a fresh `Metadata` per track (stale tags would then leak there too).

The native side is verified manually on Windows (play a tagged track, then an untagged one, check the SMTC overlay) and needs the same manual check on macOS (Now Playing).

## Finding 35: new shortcuts

Modes: pending.

## Finding 36: remaining-time toggle

Modes: pending.

## Finding 37: UNC paths for explicit picks

Modes: pending.

## Report helper

Failure modes for `Audit9Report` in `test/support/audit9_report.dart`,
exercised by `test/e2e/audit9_report_e2e_test.dart`.

- R.1 Every expected id passed: the report status must be `passed` and
  `missing` must be empty.
- R.2 An expected id that never passed must appear in `missing` and the status
  must be `failed`; a report must never claim `passed` with a gap.
- R.3 Two writes of the same report must produce byte-identical files, even
  when ids are recorded in a different order or more than once.
- R.4 Duplicate `pass` calls must be deduplicated in `passed`, and `expected`,
  `passed` and `missing` must all be sorted.
- R.5 Passing an id that is not in `expected` must not hide a missing expected
  id (status stays `failed`).
- R.6 The report directory must be created when absent, and the output path
  must be `audit9-<area>-report.json` inside it.
