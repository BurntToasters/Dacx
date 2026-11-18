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

Modes: pending.

## Finding 4: mini-player toggle state

Modes: pending.

## Finding 5: batch load failure flood

Modes: pending.

## Finding 6: macOS install warning never shows

Modes: pending.

## Finding 7: screenshot folder bookmark pruned

Modes: pending.

## Finding 8: fullscreen dock hides while in use

Modes: pending.

## Finding 9: scroll volume per event

Modes: pending.

## Finding 10: Windows blur nudge on focus

Modes: pending.

## Finding 11: previous and next always enabled

Modes: pending.

## Finding 12: advanced playback per-tick notify

Modes: pending.

## Finding 13: per-tick preference writes

Modes: pending.

## Finding 14: app-wide rebuild on settings writes

Modes: pending.

## Finding 15: sync filesystem calls on UI isolate

Modes: pending.

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

Modes: pending.

## Finding 25: settings rows at narrow widths

Modes: pending.

## Finding 26: updater notes and cancel

Modes: pending.

## Finding 27: tray controls

Modes: pending.

## Finding 28: fixed-width dialogs

Modes: pending.

## Finding 31: dead and constant members

Modes: pending.

## Finding 32: missing media extensions

Modes: pending.

## Finding 33: duplicated duration formatters

Modes: pending.

## Finding 34: stale media overlay artist and album

Modes: pending.

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
