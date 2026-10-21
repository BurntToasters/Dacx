# Draft Release Target Failure Inventory

`npm run release:draft` (Windows, creator) and `npm run release:wait-draft`
(macOS/Linux, waiters) must fail safely for these cases:

- Stable version run from any branch other than `main`.
- Beta/alpha version run from any branch other than `beta`.
- Detached HEAD, so there is no branch to release from.
- Local HEAD is behind `origin/<branch>`, so the draft would not target the latest commit.
- Local HEAD has commits not pushed to `origin/<branch>`, so GitHub cannot target them.
- `origin/<branch>` cannot be fetched, so "latest" cannot be proven.
- Draft is created without `target_commitish`, so GitHub tags the default branch on publish.
- Creator finds an existing draft that targets a different commit and silently reuses it.
- Waiter finds a draft that targets a different commit and uploads assets built from other sources.
- `FORCE_UPLOAD=1` bypass is used without a visible warning.
- Release notes refresh (PATCH) drops or changes the draft's target commit.
- A failed branch or target check still creates or modifies a GitHub release.
