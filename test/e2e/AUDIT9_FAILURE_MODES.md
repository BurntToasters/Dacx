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

Mini-player part (`test/e2e/audit9_feedback_e2e_test.dart`).

- M3.11 `PlayerScreen.onCompactModeChanged` reports true once entering the
  mini-player has committed and false once leaving it has committed; a failed
  entry or a failed restore must report nothing.
- M3.12 Disposing the screen while in the mini-player must report false; a
  screen disposed outside the mini-player must report nothing.
- M3.13 In `DacxApp`, a resize or move event while in the mini-player (480x320)
  must not save size or position and must not change `windowMaximized` (the
  stored normal size stays).
- M3.14 After leaving the mini-player, a resize event saves the restored real
  size and position again (no permanent save suppression).

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

Exercised by `test/e2e/audit9_fullscreen_e2e_test.dart` on a real
`PlayerScreen` with the mocked fullscreen flag. In fullscreen the title bar and
the dock are overlays (`FullscreenChromeOverlay`) that fade and slide and use
`IgnorePointer` when hidden.

- M8.1 With playback running and the pointer idle, the controls are visible
  just before 3 s after the last movement, then hidden after it (overlays report
  hidden and ignore pointers).
- M8.2 A mouse pointer resting over the dock keeps the controls visible
  indefinitely; once it leaves, they hide 3 s after the last movement.
- M8.3 A pointer held down inside the dock (seek or volume drag, touch so no
  hover is involved) keeps the controls visible; after release they hide 3 s
  later.
- M8.4 While playback is paused the controls never hide; once playback resumes
  they hide.
- M8.5 While a dialog route is above the player the controls never hide; after
  it closes they hide 3 s later.
- M8.6 While the queue drawer is open the controls never hide; after it closes
  they hide.
- M8.7 Moving the mouse over the media area (far from the dock) while the
  controls are hidden reveals them, and the hide timer restarts.
- M8.8 Hidden overlays do not take pointer input (ignore-pointer on both) and
  shown ones do.
- M8.9 Keyboard shortcuts still work with the controls hidden (play/pause
  space, Escape leaves fullscreen and shows the controls again).
- M8.10 The mouse cursor over the media area is hidden while the controls are
  hidden and shown while they are visible; windowed mode never hides it.

Event-driven holds (`test/e2e/audit9_wiring_e2e_test.dart`). The hold on the
controls (paused, queue drawer open, route above the player) is driven by
events instead of a 250 ms recheck. Timers created in the test zone are logged.

- M8.11 Paused in fullscreen for 10 s: the controls stay visible, and after the
  first 3 s hide timer no periodic timer and no timer shorter than 3 s is
  created (no 250 ms recheck).
- M8.12 Pause then resume: resuming creates the 3 s hide timer at that moment
  (controls still visible 2.5 s later, hidden after 3.5 s), and pausing again
  shows the controls at once and holds them.
- M8.13 Queue drawer: open for 10 s keeps the controls with no recheck timer;
  closing it (Escape) starts the 3 s hide timer at the close, and the controls
  hide 3 s after it.
- M8.14 A dialog above the player holds the controls for 10 s with no recheck
  timer; closing the dialog starts the 3 s hide timer and the controls hide 3 s
  later.

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

Covered in `test/e2e/audit9_transport_settings_e2e_test.dart`. `advancePlaylist`
never restarts the current track and does nothing on an empty queue or at a
queue edge without wrap, so Previous and Next are enabled exactly when that call
would move. Wrap only happens in loop-all mode.

- M11.1 Policy: an empty queue disables both buttons in every loop mode (loop
  all included, since the advance is a no-op).
- M11.2 Policy: a one-item queue disables both buttons with loop off or single,
  and enables both with loop all (the advance wraps onto the same item).
- M11.3 Policy: with loop off or single, a next-less position (last item)
  disables only Next and a previous-less position (first item) disables only
  Previous; a middle item enables both. Loop all enables both at every position
  of a non-empty queue.
- M11.4 Policy with a real `PlaylistService`: its `hasNext`/`hasPrevious` drive
  the policy at first, middle and last position, and with shuffle on at the
  start and end of the shuffle order.
- M11.5 `TransportControls` in the full and the compact layout: `canGoPrevious`
  or `canGoNext` false disables only that button and its callback never runs;
  true enables it and the callback runs once.
- M11.6 `TransportControls` without `canGoPrevious`/`canGoNext` keeps today's
  behavior (enabled with media, disabled without) and no media disables both
  buttons even when `canGoNext` and `canGoPrevious` are true.
- M11.7 `PlayerBottomDock` with a playlist computes the flags from the queue and
  loop mode, rebuilds when the queue changes, and without a playlist keeps
  today's `hasMedia` behavior.
- M11.8 Volume icon: 0 shows `volume_off`, 1 to 49 `volume_down`, 50 and above
  `volume_up`, in both layouts; the mute tooltip and the semantics label still
  follow `volume == 0`.

Wiring part (`test/e2e/audit9_wiring_e2e_test.dart`, real `PlayerScreen`).

- M11.9 The screen passes its playlist to the dock: with a single-item queue and
  loop off, both Previous and Next are disabled (callbacks never run); loop all
  enables both; a two-item queue at its first item enables only Next; the
  buttons follow the queue when it changes. Wide and compact layouts agree.

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

- M17.1 The media content `AnimatedSwitcher` child is keyed by surface kind:
  `media-drop-zone`, `media-audio`, `media-audio-with-art` and `media-video`
  are four different keys, and each stays findable by `find.byKey`.
- M17.2 Switching from the drop zone to a loaded source cross-fades: part way
  through the transition both the outgoing and incoming surfaces are in the
  tree, and after it only the incoming one remains.
- M17.3 Switching between two loaded surface kinds (audio to video, audio to
  audio with art) also cross-fades.
- M17.4 Gesture handling is intact during and after the transition: one tap in
  the middle of a transition and one after it each toggle play/pause exactly
  once (no duplicate or missing handler), and a double tap toggles fullscreen.

## Finding 18: fullscreen chrome relayouts video

- M18.1 In fullscreen the media surface fills the whole window (same size as
  the scaffold) with the controls shown, and has exactly the same size and
  position after they hide and after they show again.
- M18.2 In fullscreen the dock overlay lies inside the media surface rect (an
  overlay, not a sibling that takes space), anchored to the bottom edge.
- M18.3 Windowed layout is unchanged: no overlay wrapper exists, the dock is
  below the surface and the surface is shorter than the window.
- M18.4 Entering and leaving fullscreen does not remount the media surface
  (same element before, during and after).

## Finding 19: mini-player layout

Modes: pending.

## Finding 20: audio view overflow

Covered in `test/e2e/audit9_audio_empty_e2e_test.dart`.

- M20.1 The audio view never overflows at 1280x720, 800x600, 480x320, 480x190,
  300x150 or 200x120, with and without album art, with and without artist and
  album, and with very long title, artist and album text.
- M20.2 Layout adapts to the available height: tall is stacked (art above
  text), medium and wide-short is side by side (art left, text right), very
  short is text only with no art.
- M20.3 Layout also adapts to width: a narrow area never gets side by side.
- M20.4 The scroll fallback absorbs content that still does not fit: at
  200x120 with long text the content scrolls and nothing overflows.
- M20.5 A non-empty album replaces the static "Audio playback" caption; a
  missing or empty album keeps the caption.
- M20.6 The title and artist are always present in every layout mode.
- M20.7 `media-audio` and `media-audio-with-art` stay on the wrappers in
  `media_surface.dart` (source scan).

Wiring part (`test/e2e/audit9_wiring_e2e_test.dart`, real `PlayerScreen`).

- M20.8 A loaded audio file whose tags carry an album shows that album as the
  caption (`audio-caption`) with the media session setting off and on; a file
  without an album tag keeps the "Audio playback" caption.
- M20.9 The album never outlives its track: switching to another source clears
  it at once (not shown while the next metadata is pending), metadata that
  resolves after a newer load started is never shown, and after Stop the next
  load does not show the earlier album.

## Finding 21: more menu

Covered in `test/e2e/audit9_menu_e2e_test.dart`.

- M21.1 With a chapter refresh that never completes, tapping More on a real
  `PlayerScreen` must show the menu within two pumps; the menu must not wait
  for the refresh.
- M21.2 When the chapter refresh completes while the menu is open, the Tracks
  submenu with the Chapters entry must appear without reopening; before that
  it must be absent. Completing the refresh after the menu was closed must
  not throw.
- M21.3 Two open requests in the same frame must produce exactly one menu.
  After the menu closes, a new request must open it again (the guard is
  released on every close path).
- M21.4 The menu must open next to the anchor rect it was given: below it when
  there is room, above it when there is not, with its right edge on the
  anchor's right edge and always on screen. Two different anchors must give
  two different positions.
- M21.5 Without an anchor the menu must fall back to the bottom-right corner
  (right margin 12, bottom margin 64) and stay on screen.
- M21.6 The sleep timer entry must be a submenu whose items are exactly
  `SleepTimerController.presetMinutes`, in order, with the "Off" item shown
  only while a timer is active; no sleep action may be hard-coded (source
  scan).
- M21.7 Shortcut hints must be shown for Open URL, Take screenshot and
  Mini-player using the user's current bindings (default, rebound and
  unbound), formatted through
  `PlayerShortcutsService.formatAcceleratorForDisplay`.
- M21.8 Item labels must use the theme text styles: no `fontSize` literal in
  the menu sources, and the resolved label size must follow the theme's label
  style.
- M21.9 The menu must be keyboard navigable: the first item is focused on
  open, Enter activates it, Arrow Down moves to the next item, Arrow Right
  opens a submenu, and Escape closes the menu with no action.
- M21.10 Every action available before the rework must still be reachable and
  return the same action id: open URL, audio, subtitle, external audio,
  external subtitle, chapters, equalizer, advanced playback, screenshot,
  sleep off and each preset, keyboard shortcuts, queue, add files, mini-player.
  The existing `advanced-playback-entry` key must stay on the advanced
  playback item and the item must follow its opt-in gate.
- M21.11 `dispatchPlayerMoreMenuResult` must map every action id to exactly
  one callback, including every sleep preset and sleep off, and ignore unknown
  ids and `null`.
- M21.12 The shuffle switch must toggle without closing the menu and the
  mini-player switch must close it and return `compact`.
- M21.13 On a real `PlayerScreen`, choosing Keyboard shortcuts from the menu
  must still open that dialog.
- M21.14 On a real `PlayerScreen`, the menu opened from the More button is
  anchored to that button (menu right edge on the button's right edge, menu
  above the button, not the bottom-right fallback), in the wide and in the
  compact transport layout, and closes again with Escape.

## Finding 22: empty state

Covered in `test/e2e/audit9_audio_empty_e2e_test.dart`.

- M22.1 The empty state never overflows at 1280x720, 800x600, 480x320, 300x300
  and 200x200, with and without recent files, with the tip shown or dismissed.
- M22.2 Open file is the only filled primary button; Open folder, Open
  playlist, Open URL and Reopen last are lighter (text buttons, never filled).
- M22.3 All existing keys stay on their buttons (`open-folder-empty-button`,
  `open-playlist-empty-button`, `open-url-empty-button`,
  `reopen-last-empty-button`, `empty-state-tip-dismiss`) and each fires its
  own callback.
- M22.4 Reopen last is shown only when there is at least one recent file.
- M22.5 The recent list shows at most 5 entries, in order, each row keyed
  `empty-recent-<index>` with the file name as text and the full path as
  tooltip; extra entries beyond 5 are not rendered.
- M22.6 Tapping a recent row calls the open callback with that row's full
  path and no other callback fires.
- M22.7 With no recent files the list and its heading are absent.
- M22.8 The tip is shown until dismissed, the dismiss button fires its
  callback, and a dismissed tip is gone.
- M22.9 At 480x320 the primary action is on screen without scrolling.

Wiring part (`test/e2e/audit9_wiring_e2e_test.dart`, real `PlayerScreen`).

- M22.10 With no recent files the real empty state shows no Reopen last button
  and no recent rows; with recent files it shows the button and a row per
  entry (up to 5), from the live settings.
- M22.11 Tapping a recent row opens that file through the recents origin: a UNC
  recent (allowed only for explicit origins such as recents) reaches the player
  and no invalid-path message appears; Reopen last opens the first recent.

## Finding 23: snackbar queueing

Covered in `test/e2e/audit9_feedback_e2e_test.dart`.

- M23.1 On a real `PlayerScreen`, a second message raised right after a first
  one must replace it: once the exit animation has run only the second text is
  on screen and the first never comes back.
- M23.2 A burst of three messages must show only the last one and leave nothing
  queued: after its duration has passed no snackbar remains and no earlier text
  ever reappears.
- M23.3 Action and duration are preserved: a message with an action shows the
  label and the action callback runs when tapped; a custom duration is the
  duration of the shown `SnackBar`; with no duration the default stays 4 s.
- M23.4 The `ScaffoldMessengerState` entry point (used where a messenger is
  captured before an `await`) replaces the current snackbar identically and
  keeps a passed duration.
- M23.5 Source scan: no `showSnackBar(` call remains anywhere in `lib/` outside
  `lib/widgets/app_snackbar.dart`.

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

Covered in `test/e2e/audit9_transport_settings_e2e_test.dart`.

- M25.1 `SettingsRow` stacks the control under the title below its width
  threshold and puts the control beside the title above it (title right edge
  before control left edge, vertical bands overlapping); the control is never
  pushed outside the row.
- M25.2 `SettingsScreen` at the 480 px minimum window, scrolled from top to
  bottom: no overflow or layout exception, with every wide-control row (speed,
  loop, screenshot folder, screenshot format, hardware acceleration, theme,
  update channel, recent files) reachable.
- M25.3 At 480 px the titles of those rows get usable width: each title is laid
  out on one line (not wrapped per word) and is wider than 120 px, and its
  control sits below it.
- M25.4 At 1280 px the same rows keep the title and the control side by side.
- M25.5 Every setting keeps its behavior through the new row: loop mode,
  theme, screenshot format and update channel segments change their setting,
  the speed and hardware dropdowns change theirs, the screenshot reset button
  stays disabled with no folder and clears an existing one, and clearing recent
  files still works at 480 px.
- M25.6 Accent swatches are reachable by keyboard: tabbing from the start of the
  accent row reaches a swatch (focus inside a swatch), Enter selects it and
  Space selects another one, and a focused swatch shows a focus ring.
- M25.7 Swatch semantics: the label is the localized "Accent color <name>", the
  current accent exposes `isSelected`, no other swatch does, the swatch is a
  button, and a pointer tap still selects it.

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

UNC paths (`\\server\share\...`) were refused everywhere. They are now accepted
only when the user explicitly picked them (file dialog, folder dialog,
drag-and-drop, recents, play queue). Paths from untrusted origins (command
line, second-instance / Open With forwarding, playlist-file entries, media
session) stay refused. Exercised by `test/e2e/audit9_unc_e2e_test.dart`.

Modes:

- M37.1: `PlayerPathUtils.isUnsafeOpenPath` accepts a UNC path (backslash, forward-slash or `\\?\UNC\`) when `allowUnc` is not passed.
- M37.2: `isUnsafeOpenPath(..., allowUnc: true)` still refuses a UNC path (backslash, forward-slash or `\\?\UNC\`).
- M37.3: `allowUnc: true` weakens another rule: it accepts an empty path, a NUL byte (also inside a UNC path), a protocol URI (`lavfi:`, `ytdl:`, `edl:`), http credentials, or a device path (`\\.\pipe\x`, `\\?\C:\x`, `\\?\GLOBALROOT\x`).
- M37.4: `SourceOrigin` allows UNC for an origin that should not (command line, forwarded, playlist entry, media session, other) or refuses it for a user-picked origin (file dialog, folder dialog, drag-and-drop, recents, queue).
- M37.5: `SourceLoadValidationPolicy.validateRequest` accepts UNC without an origin or for a blocked origin, or refuses it for an allowed origin, or keeps reporting a different failure than `unsafePath` for a refused UNC.
- M37.6: A UNC path picked with the open-file dialog is refused instead of reaching the player.
- M37.7: A UNC path picked with the add-files-to-queue dialog is refused or not queued.
- M37.8: A UNC external audio or subtitle file picked in the dialog is refused, or a UNC external track is accepted without the explicit flag.
- M37.9: A UNC folder picked with the folder dialog is refused as an invalid path instead of being scanned (an unreachable test share must surface the scan-failed message, not the invalid-path one), or files found under a UNC folder are refused when queued (`SourceOrigin.folderDialog` must allow UNC).
- M37.10: A UNC path dropped on the window is skipped, or a dropped batch mixing UNC and local paths loses one of them; `DropPathBatchPolicy` keeps UNC without `allowUnc: true` or drops it with it.
- M37.11: A recents entry that is a UNC path does not reopen from the recent-files menu.
- M37.12: A UNC entry already in the play queue is refused when advancing to it with Next.
- M37.13: The command-line initial file that is a UNC path reaches the player, or is refused without the existing "Invalid file path" message.
- M37.14: A UNC path forwarded by a second instance or Open With (pending files) reaches the player, or a UNC path in a CLI-plus-pending batch is opened instead of being skipped with the existing skipped-file message while the local path still opens.
- M37.15: A UNC entry inside a playlist file picked by dialog is queued, or a relative entry in a playlist file on a UNC share resolves to a UNC path that is queued.
- M37.16: A playlist file that is itself a UNC path picked by dialog is refused as an invalid path instead of being read.
- M37.17: A non-UNC unsafe path picked by dialog (`lavfi://sine`) is accepted because the origin allows UNC.
- M37.18: `IPlayerService.open` hands a UNC path to the engine without the explicit flag, or refuses a UNC path when the flag is set (headless service).
- M37.19: `WindowsShellService.filterJumpListPaths` stops dropping UNC paths (jump list must stay clear of network paths).

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

## Finding 38: instance-mode flag write race

`SettingsService.allowMultipleInstances`, `syncInstanceModeFlag` and `resetAll`
write the on-disk flag file through `InstanceModeService` without ordering, so
a slow earlier write can land after a later one. Exercised by
`test/e2e/audit9_instance_flag_e2e_test.dart`.

Modes:

- M38.1: a slow `true` write followed by `false` and a sync leaves the flag file on disk although the pref is false.
- M38.2: a slow `false` write followed by `true` and a sync leaves no flag file although the pref is true.
- M38.3: many rapid toggles with uneven write latency end with a file that disagrees with the last requested value.
- M38.4: deleting a flag file that is already missing returns failure or logs a `PathNotFoundException`.
- M38.5: two concurrent deletes of the same flag file make one of them fail or log a `PathNotFoundException`.
- M38.6: `resetAll` while a slow `true` write is in flight leaves the flag file on disk.
- M38.7: `syncInstanceModeFlag` completes while an earlier write is still pending, so the file changes after it returns.
