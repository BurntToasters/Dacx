# Advanced playback E2E failure inventory

These cases are the acceptance boundary for the opt-in playback bundle. The
desktop E2E test must fail if any case regresses:

- Fresh settings must default the master switch to off.
- Off state must keep the More menu, seek bar, and shortcut surface unchanged:
  no advanced menu item, no markers, and no delay/bookmark/subtitle controls.
- Fresh/off startup must not write any advanced mpv property at all.
- Enabling the master switch must reveal the Advanced playback entry and dialog.
- Disabling it must clear the active A-B loop and restore mpv delay/subtitle
  defaults, but retain saved choices for a later re-enable.
- A-B must cycle Set A -> Set B -> Clear, reject/clear invalid ranges, and
  clear on stop or source change.
- Audio and subtitle delays must apply live, use 100 ms steps, clamp to
  +/-10,000 ms, persist by safe source identity, and not leak between sources.
- Resetting one delay must leave the other delay unchanged; failed mpv writes
  must leave stored values unchanged and expose a concise error.
- Corrupt, unsafe, out-of-range, or oversized adjustment data must be ignored
  without preventing media playback.
- A marker must default to the current timestamp, support rename/seek/delete,
  survive source changes and restart, and be bounded to 50 markers per source
  and 100 LRU sources.
- Marker labels must reject control characters and be capped at 80 characters.
- Corrupt, unsafe, out-of-range, or oversized marker data must fail closed.
- Subtitle controls must clamp to their documented ranges, apply to plain text
  subtitles, preserve authored ASS styling, and explain bitmap limitations.
- Advanced shortcuts must do nothing while off and must perform only their
  advertised action while on (L, Z/Shift+Z, Ctrl/Cmd +/- and Ctrl/Cmd+B).
- Advanced shortcut rows must be absent from the keybind dialog while off and
  present only after opt-in.
- An empty marker list must render the seek slider exactly like the current
  slider, with no layout or semantics regression.
- Reset Settings must remove the new preference stores and restore defaults.
- The E2E runner must emit a repeatable JSON report containing fixture hashes,
  checks, environment, and raw logs for audit; the test must not mark that
  report passed without an explicit runner status.
