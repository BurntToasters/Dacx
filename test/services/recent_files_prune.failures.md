# Recent Files Prune Failure Inventory

`SettingsService.pruneRecentFiles` must handle these cases safely:

- A deleted file stays in Recents on macOS because a saved bookmark exists for its path.
- A deleted file stays in Recents on macOS because a covering directory bookmark exists.
- A file that exists only inside a sandbox scope is pruned because a plain `stat` is denied.
- A bookmark that no longer resolves (target deleted) keeps the entry alive.
- A security scope started for the existence check is never stopped (scope leak).
- The bookmark bridge is missing (tests, non-macOS) and throws instead of reporting "missing".
- A slow or stale network mount blocks the UI isolate during the existence check.
- A file added to Recents while the async prune is in flight is overwritten and lost.
- A file removed from Recents while the async prune is in flight is written back.
- Stream URL entries are dropped, or tokenized stream URLs are kept.
- The bookmark map keeps entries for pruned paths, or drops a directory bookmark still in use.
- Listeners are notified when nothing changed, or not notified when entries were removed.
- The prefs key is left as `[]` instead of removed when every entry is missing.
