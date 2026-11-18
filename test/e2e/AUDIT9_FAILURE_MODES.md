# Audit 9 E2E failure inventory

Each mode id `M<finding>.<k>` below maps to a test in one of the
`test/e2e/audit9_*_e2e_test.dart` files. Each test file writes a JSON report
via `test/support/audit9_report.dart`, and the report lists every mode id that
passed. The regression tests must fail if the corresponding lib fix is
reverted.

## Finding 1: enqueue picker excludes audio

Modes: pending.

## Finding 2: display metadata tied to media session

Modes: pending.

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

## Finding 4: mini-player toggle state

Modes: pending.

## Finding 5: batch load failure flood

Modes: pending.

## Finding 6: macOS install warning never shows

Modes: pending.

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

Modes: pending.

## Finding 10: Windows blur nudge on focus

Modes: pending.

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

## Finding 15: sync filesystem calls on UI isolate

Settings part only; consumers (player and settings screens) validate existence
where the value is used and are handled by a later package.

- M15.1 The `lastOpenDirectory` setter must store a path that does not exist
  and must not create any `Directory` object (no `existsSync` on the UI
  isolate), while still rejecting NUL and `..` segments.
- M15.2 The `screenshotDir` getter and setter must not create any `Directory`
  object and must return a stored path that does not exist, while the setter
  still rejects NUL and `..` segments.

## Finding 16: click-to-pause delay

Modes: pending.

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
