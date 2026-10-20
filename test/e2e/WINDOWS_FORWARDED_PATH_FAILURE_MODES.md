# Windows forwarded path E2E failure inventory

These cases are the acceptance boundary for resolving relative file arguments
in the Windows runner before forwarding them to a running Dacx instance. A
Windows E2E check must fail if any case regresses:

- A relative path such as `song.mp3` must be forwarded as an absolute path
  resolved against the sending process's working directory, not the running
  instance's.
- `.` and `..` segments must be normalized in forwarded paths.
- An already-absolute path (for example `C:\Music\song.mp3`) must pass through
  unchanged in meaning.
- A UNC path (`\\server\share\x.mp3`) must keep its server and share prefix and
  must not be altered or broken.
- URLs and URIs (anything containing `://`, or a `file:` / `http:` style scheme)
  must be forwarded untouched, never resolved as local paths.
- A single drive letter (`C:`) must be treated as a path, not as a URI scheme.
- Non-ASCII UTF-8 path names must survive the UTF-8 to UTF-16 to UTF-8 round trip
  without corruption.
- Flags such as `--new-instance` must not be rewritten or resolved.
- Empty arguments and the `__DACX_ACTIVATE__` sentinel must be left as they are.
- A `GetFullPathNameW` failure must leave the original argument in place rather
  than dropping it.
- The change must compile warning-free under MSVC `/W4 /WX` (no narrowing, no
  signed/unsigned mismatch, no unused variables, no deprecated C runtime calls).
