# Resume Position On Exit Failure Inventory

Resume playback must keep the last position for these exits:

- Window close calls `windowManager.destroy()`; `PlayerScreen.dispose` never runs and the position is not saved.
- Tray Quit calls `windowManager.destroy()` with the same result.
- macOS Cmd+Q terminates the app without a window close event.
- The position is saved but sits in the debounce timer, and the process ends before the write.
- The prefs write starts but the process ends before it completes.
- Pause, seek while paused, then quit: the pre-seek position is restored.
- Pause, then quit: up to one save interval of progress is lost.
- An exit hook throws or hangs and blocks the app from quitting.
- An exit hook from a disposed `PlayerScreen` still runs after dispose.
- Close with minimize-to-tray enabled runs exit hooks although the app keeps running.
- A pause event during a file load saves the old file's position under the new file.
