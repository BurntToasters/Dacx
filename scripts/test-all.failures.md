# Flutter Test Output Detection Failure Inventory

`node scripts/test-all.js` decides whether `flutter test` passed from its exit
code and output. It must not misreport either way in these cases:

- A passing run logs "failed to load" (any case) from app, plugin, image or
  native-library code, and the run is reported as failed.
- A passing run includes a test name or log line containing "some tests
  failed", and the run is reported as failed.
- A passing progress line carries a stale negative count without `[E]`, and the
  run is reported as failed.
- Windows CRLF output hides the summary or failure markers.
- A real load failure (`Failed to load "<path>":`) is ignored because the
  process exited 0.
- A real failed test line (`-N: ... [E]`) is ignored.
- The final summary reports `-N` or `Some tests failed.` and the run is
  reported as passed.
- "All tests passed!" appears only inside a log line, not as the final summary,
  and the run is reported as passed.
- The output stops before Flutter prints a final summary, and the run is
  reported as passed.
