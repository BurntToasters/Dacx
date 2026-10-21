# Debug Log Redaction Failure Inventory

`DebugLogService.exportText` must never leak these into a copied log:

- A user name or folder name from a POSIX path with spaces (`/Users/John Smith/...`).
- A user name or folder name from a Windows path with spaces (`C:\Users\Jane Doe\...`).
- A quoted path inside an exception message (`path = '/Users/John Smith/a b.mp3'`).
- A double-quoted path inside an exception message.
- A UNC path (`\\server\share\Jane Doe\...`).
- A path followed by an OS error suffix (`... (OS Error: ..., errno = 2)`), where only part of the path is redacted.
- A URL with credentials or a token query, rewritten as a path instead of a safe URL.
- A path in a `details` value whose key is not path-like.

Redaction must also not:

- Swallow the non-path text that follows a quoted path.
- Turn a whole sentence with no path into `<path:...>`.
