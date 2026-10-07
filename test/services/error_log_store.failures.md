# Persistent Error Log Failure Inventory

The on-disk error log must handle these cases:

- A Flutter framework error (build, layout, paint) is not recorded at all.
- An uncaught async error is recorded in memory only and lost on exit or crash.
- Info or warning entries are persisted, so the file fills with noise.
- An unredacted path, URL token, or user name is written to disk.
- The file grows without bound across sessions.
- Rotation deletes the only copy of the most recent errors.
- The log directory is missing or not writable, and logging throws or crashes the app.
- An error during error logging recurses into the error handler.
- Two instances append at once and corrupt each other's lines.
- Errors from a previous session are not available when the user copies the debug log.
- The existing FlutterError handler (keyboard state recovery, console output) stops running.
