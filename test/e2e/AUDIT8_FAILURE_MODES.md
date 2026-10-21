# Audit 8 E2E failure inventory

Each mode below maps to a test in `audit8_regressions_e2e_test.dart`. The
regression tests must fail if the corresponding lib fix is reverted.

## Bug 1: custom Cmd (Meta) keybinds never fire

Root cause: `PlayerShortcutsService.resolve` normalizes stored custom
accelerators (`Meta+` becomes `Ctrl+`) but compares them against the live
accelerator, which is not normalized. A Cmd-captured binding therefore never
matches, and because the action is listed in `customBindings`, its default
accelerator is suppressed as well.

- M1.1 A stored `Meta+O` binding must fire `openFile` for a live Cmd+O
  (`KeyDownEvent`, `isMetaPressed: true`).
- M1.2 A stored `Ctrl+O` binding must still fire for live Cmd+O (Ctrl and Cmd
  remain the same binding).
- M1.3 A stored `Meta+O` binding must still fire for live Ctrl+O.
- M1.4 A rebound action must not fall back to its suppressed default: with
  `openFile` bound to `Meta+O`, live Ctrl+O/Cmd+O resolves to the custom
  action and never to a stale default.
- M1.5 A `KeyUpEvent` for a bound Cmd chord must resolve to null (no duplicate
  dispatch on key release).
- M1.6 Modifier order must not matter: stored `Shift+Meta+N` must match a live
  Cmd+Shift+N, and stored `Shift+Ctrl+O` must match a live Ctrl+Shift+O.
- M1.7 Space forms: stored `' '` and `Space` must both match live Space for
  `playPause` when media is loaded, and must not match when no media is loaded.
- M1.8 Space with a primary modifier: stored `Ctrl+ ` (normalizes to
  `Ctrl+Space`) must match a live Cmd+Space when the custom action is
  `playPause` and media is loaded.
- M1.9 Repeat events: a bound Cmd chord for a repeatable action (`seekForward`)
  must fire on `KeyRepeatEvent`, while a non-repeatable action must not.
- M1.10 Unbound Cmd chords keep their defaults (Cmd+S still resolves to
  `screenshot` when no custom binding for it exists).
- M1.11 The audit7 invariant still holds: `normalizeAccelerator('Meta+O')`
  equals `normalizeAccelerator('Ctrl+O')`.

## Bug 2: live Open With batch failures are unhandled

Root cause: `OpenFileBridge._queueLiveRequest` schedules
`unawaited(_deliver(requests))`. If `onOpenBatch` throws, the error escapes as
an uncaught async error instead of being routed through `_deliverSafely` and
logged via `onLog`, as the drain path already does.

- M2.1 A live batch whose `onOpenBatch` throws must be logged through `onLog`
  as `open_file_bridge_failed` with `error: true`.
- M2.2 That failure must not surface as an uncaught zone error (the test zone
  records zero errors).
- M2.3 A later live batch after the failure must still be delivered (the
  bridge keeps working; no permanent poisoning).
- M2.4 A failed live batch must not be retried: `onOpenBatch` runs exactly once
  for the failing batch (no `retry: true` semantics, no duplicate delivery).
- M2.5 A live batch with `isActive() == false` must not invoke `onOpenBatch`.
- M2.6 A single live event (one request in the window) still goes through
  `onOpenRequest` unchanged after the fix.

Out of scope for this audit (noted, not fixed): the single-event live path
`unawaited(handlePlatformPayload(...))` in `_attachEventListener` has the same
unhandled-error shape when `onOpenRequest` throws and no `onOpenBatch` is set.
It is not part of the audit8 fix list.
