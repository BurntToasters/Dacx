# Contributing to Dacx

Thanks for helping improve Dacx.

## Development setup

1. Install Node.js 22+, Dart (for FVM), and platform build deps per [README.md](README.md).
2. `npm ci && npm run setup:flutter`
3. `fvm flutter pub get`
4. Run locally: `npm run dev` (or `dev:win` / `dev:mac` / `dev:linux`)

Run every project Flutter or Dart command through FVM: `fvm flutter ...` or
`fvm dart ...`. Never call the system `flutter` or `dart` directly.

## Quality gates (run before opening a PR)

```bash
npm run test:all
```

This runs version sync, static checks, hygiene, analyze, format, unit tests, coverage, and a build smoke. Coverage gates (`scripts/check-coverage.js`): overall minimum **40%**; scoped (non-required sources) minimum **55%**. Required sources (`player_screen`, spectrum) must appear in the lcov report but are excluded from the scoped gate. CI runs a subset plus multi-OS build smoke on `main` and `beta` only (and `v*` tags) — interim branches are skipped to save minutes.

Before a stable cut, run the manual checklist in [docs/QA.md](docs/QA.md).

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

Release scripts (`release:*`, `b`, `r`) are **intentionally destructive** on the release machine (hard reset/clean). Run only on dedicated release VMs with a complete `.env`. See README and SECURITY.md for signing and `DACX_REQUIRE_WINDOWS_SIGNER`.
