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

Report privately to the maintainer via the contact path listed on [help.rosie.run/contact](https://help.rosie.run/contact) or the repository owner profile. Include:

- Affected version and platform (Windows / macOS / Linux)
- Steps to reproduce
- Impact assessment (confidentiality, integrity, availability)
- Proof of concept if available

We aim to acknowledge reports within a few business days and will coordinate disclosure timing with you.

## Security model (brief)

Dacx is a **local desktop media player**. It does not implement user accounts or a server API. Primary trust boundaries:

- **Self-update:** downloads from GitHub (host allowlist). **Windows:** SHA256 must match both `SHA256SUMS` and an **Ed25519-signed update manifest** (primary install trust). Authenticode is fully configured for official GitHub MSI builds (signed using Azure Artifact Signing). After verification, Dacx launches bundled `dacx-update-helper.exe` via a short in-memory WMI bootstrap (no on-disk PowerShell scripts) so the helper survives Process Lifetime Management, re-checks SHA256, elevates `msiexec`, then relaunches Dacx on success. **macOS:** SHA256SUMS over TLS, then Apple code signature verification (`codesign --verify --deep --strict`) plus Team ID / bundle ID / version / Gatekeeper checks via the XPC helper; Developer ID signing is the trust anchor (no separate Ed25519 update manifest). **Linux:** no in-app self-update; prefer AppImage + [AppManager](https://github.com/kem-a/AppManager) for install/updates, or trust GPG-signed deb/rpm/tar / GitHub Flatpak sideloads / manual downloads.
- **Local IPC:** method/event channels between Flutter and native runners; Windows named pipes use a per-user DACL.
- **File open:** paths from CLI, drag-and-drop, and OS “Open With” are validated before use (UNC / credential URLs rejected).

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

Official Windows release builds require Azure Artifact Signing env vars
(`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_CLIENT_SECRET`,
`AZURE_ARTIFACT_SIGNING_*`). The publisher is passed to Flutter as
`DACX_WINDOWS_SIGNER_PUBLISHER`. Set `SKIP_WIN_CODESIGN=1` for unsigned local
MSIs; self-update then relies on Ed25519 alone. Official production releases
are fully Authenticode-signed.

macOS release builds should set `APPLE_TEAM_ID` (see `scripts/flutter-build-macos.js`).

`release:prepare`, `release:mirror`, and `release:finalize` update generated
metadata and release staging files. Run them on a clean release tree and review
their output before uploading. They do not reset Git or delete unrelated local
files. The `b`, `r`, and `vi` scripts do run `git reset --hard` / `git clean -fd`
and can permanently remove local changes; use those only on dedicated VMs after
confirming the working tree is disposable.
