# Dacx Release Runbook

This runbook covers beta and stable releases for Windows x64, universal macOS,
and Linux x64. Keep release keys and `.env` files on dedicated release machines.

## Prepare a version

1. Set `package.json` version.
2. Run `npm run u`.

`npm run u` synchronizes package metadata and `CHANGELOG.md`. It updates only
download-table URLs, inserts one blank current-version heading, and switches the
beta notice. Add release notes after this command. The command is idempotent.

`npm run check:release-notes` is stricter than `npm run u`: it rejects an empty
current section. Do not run release packaging until this check passes.

## Run release preparation

Run on a clean, dedicated release machine:

```text
npm run release:prepare
```

The command installs locked dependencies, checks the version and notes, refreshes
licenses, cleans release staging, and runs the full test gate. Review generated
license output before packaging.

Build and sign on platform-specific machines:

```text
npm run release:win
npm run release:mac
npm run release:linux
```

The Windows machine creates the shared GitHub draft. macOS and Linux wait for the
same draft. Each machine uploads its artifacts and signatures; none publishes it.

## Verify draft before publishing

Create one passing platform proof report for each platform under:

```text
test-results/release-proof/<version>/
```

Reports must contain the candidate version, platform, `status: "passed"`, and
`releaseProof: true`. Then run:

```text
npm run release:verify-draft
```

The verifier checks the exact primary asset matrix, checksum contents, detached
GPG signatures from the pinned `GPG_FINGERPRINT`, the pinned repository Ed25519
Windows update key, remote asset bytes/digests, and all three platform proof
reports. It writes
`test-results/release-proof/<version>/report.json` and never publishes a release.

Set `GPG_FINGERPRINT` (or `RELEASE_GPG_FINGERPRINT`) to the full primary-key
fingerprint in `.env`; `--gpg-fingerprint <fingerprint>` is the explicit CLI
override. The verifier requires a matching GnuPG `VALIDSIG` record for every
primary artifact and checksum sidecar.

Publish manually only after the report passes and the manual checklist in
`docs/QA.md` is complete. Keep the draft while fixing failures; do not replace
assets on a published release unless the maintainer explicitly approves it.

## Release sequence

- `beta.1`: feature-complete candidate.
- `beta.2`: regression and packaging fixes only.
- Additional beta: only for a remaining release blocker; prefer fewer than four.
- `1.0.0`: publish after the final beta passes Windows, macOS, and Linux E2E,
  packaged smoke, updater, signing, and draft-verifier gates.

Do not advertise an opt-in feature as stable until all three packaged platforms
have passing proof reports. Keep the default app path minimalist.

## Recovery

If a candidate fails, leave the GitHub release as a draft, fix the branch, rerun
`npm run u` if the version changed, and repeat all affected platform checks.
Record failed reports and command logs with the candidate. For a published issue,
follow the maintainer's rollback or replacement decision; never delete release
assets as an unreviewed workaround.
