# Contributing to Dacx

Thanks for helping improve Dacx.

## Development setup

1. Install Node.js 22+, Dart (for FVM), and platform build deps per [README.md](README.md).
2. `npm ci && npm run setup:flutter` — installs or repairs the global `fvm` CLI, pins and verifies the exact Flutter SDK from `.fvmrc`, then runs one explicit `flutter pub get` and regenerates l10n (`gen-l10n`). Re-run this if you see `Invalid kernel binary format version` from FVM.
3. Run locally: `npm run dev` (or `dev:win` / `dev:mac` / `dev:linux`)

Run every project Flutter or Dart command through FVM: `fvm flutter ...` or
`fvm dart ...`. Never call the system `flutter` or `dart` directly.

VS Code / Cursor uses `"dart.flutterSdkPath": ".fvm/flutter_sdk"` (see `.vscode/settings.json`). That symlink is recreated when you bump `.fvmrc` and run `npm run setup:flutter` or `fvm use`; you do not edit the version number in settings by hand.

## Quality gates (run before opening a PR)

```bash
npm run test:all
```

This runs version sync, static checks, hygiene, analyze, format, unit tests, coverage, and a build smoke. Coverage gates (`scripts/check-coverage.js`): overall minimum **40%**; scoped (non-required sources) minimum **55%**. Required sources (`player_screen`) must appear in the lcov report but are excluded from the scoped gate. CI runs a subset plus multi-OS build smoke on `main` and `beta` only; interim branches and tags are skipped to save minutes.

Before a stable cut, run the manual checklist in [docs/QA.md](docs/QA.md).

`release:prepare` intentionally does **not** run a clean-tree guard. Keep the working tree intentional; do not assume an automated guard.

`release:draft` (Windows) and `release:wait-draft` (macOS/Linux) do guard the branch: stable versions must be on `main`, beta/alpha versions on `beta`, and local HEAD must equal the freshly fetched `origin/<branch>`. The Windows machine creates the draft with `target_commitish` set to that exact commit, so the tag lands on the branch tip at publish. macOS/Linux refuse a draft that targets a different commit than their checkout; set `FORCE_UPLOAD=1` to bypass that one check.

`release:prepare` validates `CHANGELOG.md` against the package version.
`release:draft` then copies it into the GitHub draft body. If the matching draft
already exists, its body is refreshed; an already-published release is never
rewritten.

Before packaging a release, `release:prepare` runs `npm run licenses` to refresh
`build/THIRD_PARTY_NOTICES.txt` (copied into installers by `package-release.js`).

Update channels: **STABLE** is the default for end users after a `v1.0.0` (or final stable `v0.11.0`) tag; **BETA** tracks pre-release builds. Keep channel defaults honest in Settings when cutting the first stable.

## Pull requests

- Target `beta` or `main` as agreed with maintainers.
- Keep changes focused; match existing style in `lib/` and `test/`.
- Do not commit `.env`, signing keys, or release artifacts.
- Update `CHANGELOG.md` for user-visible changes when appropriate.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities privately.

## Release builds (maintainers)

Release scripts (`release:*`, `b`, `r`) are **intentionally destructive** on the release machine (hard reset/clean). Run only on dedicated release VMs with a complete `.env`. See README and SECURITY.md for Azure Artifact Signing (`AZURE_*`) and `SKIP_WIN_CODESIGN=1` for unsigned local Windows builds.
