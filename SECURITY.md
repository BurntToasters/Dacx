# Security Policy

## Supported versions

Security fixes are applied to the latest release on the [stable](https://github.com/BurntToasters/Dacx/releases) channel and, when applicable, the current `beta` / `next-*` development branches.

| Version | Supported |
| ------- | --------- |
| Latest stable | Yes |
| Latest beta | Yes |
| Older releases | Best effort |

## Reporting a vulnerability

Please **do not** open public GitHub issues for undisclosed security problems.

Report privately to the maintainer via the contact path listed on [rosie.run/support](https://rosie.run/support) or the repository owner profile. Include:

- Affected version and platform (Windows / macOS / Linux)
- Steps to reproduce
- Impact assessment (confidentiality, integrity, availability)
- Proof of concept if available

We aim to acknowledge reports within a few business days and will coordinate disclosure timing with you.

## Security model (brief)

Dacx is a **local desktop media player**. It does not implement user accounts or a server API. Primary trust boundaries:

- **Self-update** — downloads from GitHub (host allowlist), verified with SHA256 + Ed25519 manifests (Windows) and `codesign --verify --deep --strict` plus Team ID / bundle ID / version checks (macOS).
- **Local IPC** — method/event channels between Flutter and native runners; Windows named pipes use a per-user DACL.
- **File open** — paths from CLI, drag-and-drop, and OS “Open With” are validated before use.

Release signing keys and `.env` secrets must remain on maintainer release machines only.

## Flatpak sandbox

Official Flatpak builds use narrowed filesystem access: standard XDG media/download
locations only. The manifest does **not** request `--filesystem=host`; opening
arbitrary paths relies on the Freedesktop file portal (same as the in-app file
picker). Third-party license text is shipped under `/app/share/doc/dacx/`.

## Third-party notices

Release artifacts include `THIRD_PARTY_NOTICES.txt` and `LICENSE` (generated via
`npm run licenses` during `release:prepare`). See `docs/NATIVE_DEPENDENCIES.md`
for bundled native runtime notes (libmpv / media_kit).

## Release VM hardening

Official Windows release builds should set in `.env`:

- `WINDOWS_SIGNING_CERT_THUMBPRINT` (or `DACX_WINDOWS_SIGNER_THUMBPRINT`) — baked into the binary for runtime Authenticode checks
- `DACX_REQUIRE_WINDOWS_SIGNER=1` — causes `npm run build:win` to **fail** if the thumbprint is missing (dev machines can omit this)

macOS release builds should set `APPLE_TEAM_ID` (see `scripts/flutter-build-macos.js`).

The `release:finalize` and related git reset scripts are **intentionally destructive** on the release machine; run only on dedicated VMs with a clean working tree.
