# CLI initial file E2E failure inventory

A file passed on the command line must reach the player in the same form as
an absolute path, without any other input source changing. The desktop E2E
test must fail if any case regresses:

- A relative CLI path (for example `song.mp3` or `media/song.mp3`) must reach
  the player as the absolute, normalized path resolved against the current
  working directory.
- `./` and `../` segments in a relative CLI path must be normalized away
  before the open request is built.
- An already-absolute CLI path must reach the player unchanged.
- An http or https URL passed as the CLI argument must reach the player
  unchanged, with no path resolution applied.
- A `file:` URI must not be mangled into a filesystem path or otherwise
  rewritten.
- Paths delivered by the native pending-files bridge (second instances, Finder
  or shell open events) must NOT be rewritten, even when they are relative.
- A cold launch with a CLI file plus pending files must still open the CLI
  file first, with the pending files queued after it.
- Empty or whitespace-only CLI input must produce no open request.
