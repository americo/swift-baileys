# SwiftBaileys E2E Validation Checklist

This checklist tracks the end-to-end proof for the TypeScript-to-Swift rewrite. `Scripts/verify-production-readiness.sh` proves build, generated resource freshness, fixture parity, unit coverage, manual Swift file-size limits, and the automated high-fidelity mock e2e pass. A live WhatsApp pass can still be run as an external compatibility check.

## Preconditions

- For live validation, use a dedicated WhatsApp test account, not a production personal or customer number.
- For live validation, use a fresh auth directory outside the repository, for example `/tmp/swiftbaileys-e2e-auth`.
- For mock validation, use `Scripts/verify-mock-e2e.sh`; it uses mock transports and in-memory stores only.
- Do not commit auth state, QR screenshots, message content from real users, or Signal key material.
- Capture only redacted stanza summaries: message ids, JID domains, node tags, status codes, and test timestamps.

## Required Scenarios

- [x] Mock e2e: pairing and credential persistence.
- [x] Mock e2e: direct send and message cache.
- [x] Mock e2e: group send and sender-key fanout.
- [x] Mock e2e: status broadcast fanout.
- [x] Mock e2e: retry receipt resend.
- [x] Mock e2e: media upload/download and reupload.
- [x] Mock e2e: app-state sync and persistence.
- [x] Mock e2e: incoming events and ACK behavior.
- [ ] Optional live pass: pairing, direct send, group send, status broadcast, retry receipt resend, media upload/download, app-state sync, and incoming event handling against a dedicated WhatsApp test account.

## Acceptance Evidence

- [x] `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer Scripts/verify-mock-e2e.sh` passes.
- [x] A redacted mock e2e log is generated at `.build/mock-e2e/redacted-log.md`.
- [x] Mock validation uses no auth directory and no real auth/session files.
- [ ] Optional live validation log records each live scenario with timestamps and message/query ids.
- [ ] Any failed or unsupported live server behavior is either fixed or recorded as a concrete remaining gap in `Docs/API_PARITY_MATRIX.md`.
