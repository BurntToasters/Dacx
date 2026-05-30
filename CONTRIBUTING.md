# Contributing to Dacx

Thanks for helping improve Dacx.

## Development setup

1. Install Node.js 22+, Dart (for FVM), and platform build deps per [README.md](README.md).
2. `npm ci && npm run setup:flutter`
3. `fvm flutter pub get`
4. Run locally: `npm run dev` (or `dev:win` / `dev:mac` / `dev:linux`)

## Quality gates (run before opening a PR)

```bash
npm run test:all
```

This runs version sync, static checks, hygiene, analyze, format, unit tests, coverage (55% floor), and a build smoke. CI on `main`, `beta`, and `next-*` runs a subset plus multi-OS build smoke.

Before packaging a release, `release:prepare` runs `npm run licenses` to refresh
`build/THIRD_PARTY_NOTICES.txt` (copied into installers by `package-release.js`).

## Pull requests

- Target `beta` or `main` as agreed with maintainers.
- Keep changes focused; match existing style in `lib/` and `test/`.
- Do not commit `.env`, signing keys, or release artifacts.
- Update `CHANGELOG.md` for user-visible changes when appropriate.

## Security

See [SECURITY.md](SECURITY.md) for reporting vulnerabilities privately.

## Release builds (maintainers)

Release scripts (`release:*`, `b`, `r`) are **intentionally destructive** on the release machine (hard reset/clean). Run only on dedicated release VMs with a complete `.env`. See README and SECURITY.md for signing and `DACX_REQUIRE_WINDOWS_SIGNER`.
