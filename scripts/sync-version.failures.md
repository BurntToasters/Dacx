# Version Sync Failure Inventory

`npm run u` must fail safely for these cases:

- Invalid or unsupported package version.
- Missing or malformed `package-lock.json`.
- Missing or malformed changelog download table.
- Download URLs outside the top table changed by accident.
- Historical release URLs changed by accident.
- Missing or duplicated current-version heading.
- Existing current-release notes overwritten.
- Blank release heading inserted more than once.
- Beta notice absent for alpha/beta versions.
- Beta notice left visible for stable versions.
- Mixed CRLF/LF line endings rewritten unnecessarily.
- One file written before another file fails validation.
- Running sync twice produces different bytes.
- Version references drift between package, lockfile, package metadata, and changelog.
- Stable transition leaves a visible beta notice or removes existing stable notes.
- CRLF input is silently converted to LF.
- A duplicate current heading loses current release notes.
- A malformed lockfile or changelog marker writes only part of the version update.

Release verifier failure cases also covered by the E2E harness:

- A tampered Windows manifest signature passes because only the sidecar exists.
- A remote GitHub asset advertises a wrong digest or size while its name matches.
- A detached signature comes from the wrong GPG key or fingerprint.

`release:prepare` must additionally fail when current release notes contain no release entries.

CI desktop E2E failure cases also include missing version/run identity inputs;
the integration receipt must bind to the exact candidate version and smoke run.
