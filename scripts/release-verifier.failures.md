# Draft Release Verifier Failure Inventory

`release:verify-draft` must fail closed when:

- Package version or release tag is invalid.
- Local release staging directory is missing or has no artifacts.
- Any required Windows, macOS, or Linux primary artifact is missing.
- The local release directory contains any file outside the exact approved asset set.
- An artifact name contains a different version or an unapproved platform/architecture.
- A checksum sidecar is missing, malformed, or hashes the wrong file.
- A required detached GPG sidecar is missing.
- Windows update manifest or signature is missing, malformed, or names the wrong version/platform/MSI hash.
- GitHub draft is missing, published, points at another tag, or has incomplete assets.
- Remote asset names differ from local staged names.
- A platform proof report is missing, malformed, stale, skipped, or not marked `releaseProof`.
- A proof report belongs to another platform or version.
- A proof report uses a legacy schema or is bound to different artifact bytes.
- A proof report omits its required top-level version/status/releaseProof fields
  and tries to smuggle the version through nested check metadata.
- A report is written only after all checks finish, so failure output cannot be audited.
- Repeated verification changes or deletes prior evidence.
- A Windows manifest signature is tampered after signing.
- A remote asset advertises a wrong GitHub digest or size despite matching name.
- A detached signature comes from the wrong GPG signer or fingerprint.
- The GPG signer test cannot start gpg-agent because its socket path under a
  long macOS temp folder exceeds the Unix socket limit, so the test fails locally.
- The GPG signer test leaves a gpg-agent running or its temporary keyring on disk.
- A platform proof emitted by the current smoke harness uses its v2 schema and
  is rejected despite containing the required proof checks.

The verifier must write a JSON report and command log, then return nonzero for every
failed or incomplete release proof. It must never publish or mutate the GitHub draft.
