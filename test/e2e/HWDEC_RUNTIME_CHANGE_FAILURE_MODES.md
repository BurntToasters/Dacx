# Hardware decode runtime change E2E failure inventory

Changing the hwdec setting while a source is loaded must only update the mpv
`hwdec` property and must never disturb playback or the video surface. These
cases are the acceptance boundary:

- A hwdec setting change must still reach mpv through `setProperty('hwdec', ...)`.
- Re-applying the same hwdec value repeatedly must not accumulate work or
  produce extra surface changes.
- The startup hwdec value must be applied once when the screen initializes.
- A hwdec change must not restart, reload, or otherwise interrupt the current
  source, position, or playing state.
- The video surface must not be rebuilt or replaced on a hwdec change. The
  headless E2E surface has no real VideoController, so this mode is proven by
  code review of `_applyHwDec` (no `VideoController` construction and no
  `setState` on change), not by these tests.
- A failed `setProperty('hwdec', ...)` must not crash the screen or surface an
  unhandled error; it is logged and the screen keeps working.
- Repeated toggles between hwdec values must keep each change to a single
  property write with no accumulated controllers or listeners.
