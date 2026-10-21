# Allowlisted GET Failure Inventory

`fetchAllowedGetFollowingRedirects` and its self-update callers must fail safely for these cases:

- The server sends headers, then stalls mid-body, and the download hangs forever.
- The server sends no headers, and the request hangs forever.
- A slow but steady download (large MSI on a slow link) is killed by a total-time cap.
- An idle timeout fires but leaves a half-written MSI that later passes as complete.
- An idle-timeout error is not surfaced as `downloadFailed` and the progress dialog stays open.
- Small text fetches (SHA256SUMS, manifest, signature) stall mid-body without a timeout.
- A redirect points to a non-allowlisted host and is followed.
- A redirect has no `Location` header and is treated as success.
- A redirect loop never ends.
- Response metadata (status, headers, content length) is lost when the body stream is wrapped.
