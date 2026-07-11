# Manual QA checklist (pre-stable)

Run on **Windows (MSI or debug)**, **macOS 15+**, and **Linux packages**: prefer **AppImage plus one deb/rpm** (deb/rpm update guidance differs from portable). Use a short local audio file, a video file, and an `.m3u` with 2+ entries.

## Playback

- [ ] Open File / Open Folder / Open Playlist from UI (and macOS File menu where applicable)
- [ ] Empty state: ⋯ more menu opens **without** media; **Open URL** loads a stream (Win/Linux; macOS File → Open URL also OK)
- [ ] Drag-and-drop a supported file onto the empty state
- [ ] Play / pause / stop / seek / mute / volume
- [ ] Cycle playback speed from transport chip and `[` / `]` / `\`
- [ ] Loop modes; queue prev/next wraps or stops as expected (tooltips: Shift+P / Shift+N)
- [ ] Reopen Last restores the previous file (Ctrl/Cmd+R)

## Queue / playlists

- [ ] Multiple files enqueue; drag-reorder works
- [ ] Shuffle toggle on drawer **and** more menu; quit/relaunch keeps shuffle preference
- [ ] Clear queue
- [ ] Save Playlist exports `.m3u`; re-open that playlist
- [ ] Quit and relaunch: queue + index restore (missing files pruned)

## OS chrome

- [ ] Media session / Now Playing / SMTC / MPRIS shows title and responds to play/pause
- [ ] Display does not sleep while video plays (idle inhibit) — leave playing ≥1–2 min
- [ ] Windows: Jump List recents + taskbar progress while playing
- [ ] macOS: File menu + Dock menu New Window / Open; Open Recent → Clear Menu
- [ ] Linux deb/rpm: Settings → Check for Updates shows **deb/rpm** guidance (not “portable”)

## Settings / updates

- [ ] Appearance: theme, accent; Win/mac blur + opacity without Experimental master switch
- [ ] Hardware decode change applies without requiring app restart (next open / property apply)
- [ ] Experimental: visualizer / multi-audio mix stay gated and off by default
- [ ] Check for Updates opens a sensible path (self-update on Win MSI / macOS Applications; Linux package guidance)
- [ ] Flatpak (if tested): empty-state copy mentions picker; update guidance mentions reinstalling the `.flatpak`, not Flathub `flatpak update`

## Trust smoke

- [ ] Unsupported / unsafe paths (e.g. credential URLs) are refused with feedback
- [ ] Screenshot save works when media is playing
- [ ] Media Info shows title / artist / album when tags are present
