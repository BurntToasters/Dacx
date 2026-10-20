# Window visuals settings-listener failure inventory

The settings listener in the app shell must re-apply native window visuals and
sync minimize-to-tray only when their inputs change. These cases are the
acceptance boundary for that gate:

- Volume, speed, loop mode, recent files, EQ, and playback marker changes must
  not count as a window visual change.
- Each visual input must count as a change: theme mode, window blur enabled,
  window blur strength, window opacity, experimental features, and Linux
  compositor blur.
- Toggling minimize-to-tray must count for tray sync only, not for visuals.
- Reset Settings after a non-default visual setting must count as a visual
  change and restore the default snapshot.
- Reset Settings while every visual input is already default must not count.
- Repeated notifications with no change to a tracked input must not count.
- Out-of-range values that clamp to the stored value must not count.
- A value A -> B -> A must count on each step, so the snapshot must be updated
  on every notification.
- A snapshot taken from settings must not change when settings later change.
- Snapshots built from the same settings state must be equal with equal hash
  codes; a difference in any single input must make them unequal.
- A recorder created after a visual setting was already changed must not treat
  that earlier change as new.
- The tracked inputs must be read through the same getters the apply path uses,
  so the gate cannot miss a value the native apply reads.
- The gate must not pump the full app or touch window_manager or native
  channels; it is verified against real SettingsService mutations.
