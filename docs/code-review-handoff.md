# ClawMail Code Review Handoff

Date: March 6, 2026
Repository: `/Users/andrewrmitchell/Developer/ClawMail`
Purpose: Carry forward a full review into a fresh session with enough context to fix issues without re-reading the entire repo.

## Session Update (March 6, 2026, later)

This handoff started with issues 1-10 open. Issues 1-5 are now fixed in code and covered by regression tests.

Completed in this session:
- 1. Attachment path guardrails now resolve symlinks before policy checks, compare directory ancestry by path components instead of raw prefixes, and use the validated canonical path for attachment reads/writes.
- 2. CalDAV/CardDAV constructors now reject non-HTTPS base URLs, and account setup UI validates optional DAV URLs before allowing the setup flow to advance.
- 3. DAV follow-up URLs are now same-origin constrained. Server-supplied absolute `href` / principal / home-set URLs are rejected if they change scheme, host, or port.
- 4. Approved recipients are now scoped by `(email, account_label)` instead of global email-only approval. Listing/removal APIs now preserve account context.
- 5. Launch-at-login now starts `ClawMailApp` from the app bundle instead of the nonexistent `clawmail daemon` command. The generated plist, bundled plist template, and README are aligned.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 143 passing tests across 16 suites

New tests added in this session:
- `Tests/ClawMailCoreTests/SecurityTests.swift`
- `Tests/ClawMailCoreTests/DAVSecurityTests.swift`
- `Tests/ClawMailCoreTests/RegressionTests.swift`
- `Tests/ClawMailIntegrationTests/ModelTests.swift`
- `Tests/ClawMailAppTests/LaunchAgentManagerTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailCore/Email/EmailManager.swift`
- `Sources/ClawMailCore/DAVURLValidator.swift`
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift`
- `Sources/ClawMailCore/Models/ApprovedRecipient.swift`
- `Sources/ClawMailCore/Storage/DatabaseManager.swift`
- `Sources/ClawMailCore/Storage/MetadataIndex.swift`
- `Sources/ClawMailCore/Guardrails/GuardrailEngine.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Sources/ClawMailCore/IPC/IPCDispatcher.swift`
- `Sources/ClawMailCLI/Commands/RecipientsCommands.swift`
- `Sources/ClawMailAppLib/Routes/RecipientsRoutes.swift`
- `Sources/ClawMailApp/Settings/GuardrailsTab.swift`
- `Sources/ClawMailApp/Account/AccountSetupView.swift`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift`
- `Sources/ClawMailApp/LaunchAgent/LaunchAgentManager.swift`
- `Resources/com.clawmail.agent.plist`
- `Package.swift`
- `README.md`

Next issue to start with:
- 6. OAuth refresh path exists but is effectively unused

## Summary

A full static review was completed across the macOS app, REST API, IPC layer, auth/OAuth, storage, email, calendar, contacts, tasks, sync, launch agent, and distribution paths.

Build/test status at original review time:
- `swift build`: passed
- `swift test`: passed
- Test suite reported 131 passing tests
- `swift run ClawMailCLI daemon`: failed with `Unexpected argument 'daemon'`

Important: the passing test suite does **not** cover several of the highest-risk issues below.

## Highest Priority Findings

### 1. Attachment path guardrails are bypassable via symlinks

Severity: High

Problem:
- Attachment read/write restrictions are implemented with lexical path checks only.
- The code uses `URL(fileURLWithPath: path).standardized` and `hasPrefix(...)` style checks before I/O.
- That does not protect against symlink traversal.

Impact:
- A symlink inside an allowed directory such as `~/Documents`, `~/Downloads`, `~/Desktop`, or `/tmp` can be used to:
  - read blocked files as outbound attachments
  - overwrite arbitrary paths when downloading attachments

Primary references:
- `Sources/ClawMailCore/Email/EmailManager.swift:375`
- `Sources/ClawMailCore/Email/EmailManager.swift:409`
- `Sources/ClawMailCore/Email/EmailManager.swift:463`
- `Sources/ClawMailCore/Email/SMTPClient.swift:60`

Suggested fix direction:
- Resolve symlinks before enforcing allow/block policies.
- Use `resolvingSymlinksInPath()` or equivalent canonicalization on the final path.
- Re-check path ancestry after symlink resolution.
- For writes, consider opening with flags that avoid following unexpected symlinks if possible.
- Add tests for:
  - allowed path containing symlink to `/etc/passwd`
  - allowed temp path containing symlink to a blocked home path
  - download target symlink escaping allowed directories

### 2. CalDAV/CardDAV credentials can be sent over plaintext HTTP

Severity: High

Problem:
- Account setup accepts arbitrary CalDAV/CardDAV URLs.
- The DAV clients accept those URLs and attach `Authorization` for both Basic and Bearer auth without requiring HTTPS.
- This contradicts the README/security claims that TLS is required.

Impact:
- A user can configure `http://...` DAV endpoints and send passwords or tokens in cleartext.

Primary references:
- `Sources/ClawMailApp/Account/AccountSetupView.swift:205`
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift:54`
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift:324`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift:42`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift:228`

Suggested fix direction:
- Enforce `https` for CalDAV/CardDAV in both UI validation and client constructors.
- Reject non-HTTPS URLs early with a `ClawMailError.invalidParameter` or auth/configuration error.
- Update tests to cover rejection of plaintext DAV URLs.

### 3. DAV clients trust server-supplied absolute URLs and can leak credentials cross-origin

Severity: High

Problem:
- DAV discovery and follow-up requests accept absolute URLs from server-provided `href` / home-set values.
- `resolvingRelative(path:)` returns arbitrary absolute `http(s)` URLs unchanged.
- The clients then apply `Authorization` to those requests.

Impact:
- A malicious or compromised DAV server can return an absolute URL on a different host and harvest the user’s password or bearer token.

Primary references:
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift:353`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift:257`
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift:978`
- `Sources/ClawMailCore/Calendar/CalendarManager.swift:57`
- `Sources/ClawMailCore/Contacts/ContactsManager.swift:53`

Suggested fix direction:
- Restrict DAV follow-up URLs to the original origin unless there is an explicit trusted redirect policy.
- Validate scheme, host, and port before sending credentials.
- Treat unexpected cross-origin absolute URLs as server errors.
- Add tests for malicious absolute `href` / home-set responses.

### 4. First-time recipient approval is global, not per account

Severity: High

Problem:
- `approved_recipients` uses `email` as the primary key.
- Approval lookup ignores account.
- Approving a recipient on one account implicitly approves it for every other account.

Impact:
- Guardrail behavior is weaker than intended for multi-account setups.
- A sensitive work account can inherit approvals from a personal account.

Primary references:
- `Sources/ClawMailCore/Storage/DatabaseManager.swift:119`
- `Sources/ClawMailCore/Storage/MetadataIndex.swift:219`
- `Sources/ClawMailCore/Storage/MetadataIndex.swift:230`
- `Sources/ClawMailCore/Guardrails/GuardrailEngine.swift:45`

Suggested fix direction:
- Make `(email, account_label)` the approval key.
- Update `isRecipientApproved(email:account:)` and all callers.
- Migrate existing schema and preserve data if needed.
- Add tests proving approval isolation between accounts.

### 5. Launch-at-login is broken in the distributed product

Severity: High

Problem:
- The LaunchAgent is configured to run `/usr/local/bin/clawmail daemon`.
- The CLI has no `daemon` subcommand.
- This was confirmed during review.

Observed command result:
- `swift run ClawMailCLI daemon` -> `Unexpected argument 'daemon'`

Primary references:
- `Sources/ClawMailApp/LaunchAgent/LaunchAgentManager.swift:27`
- `Resources/com.clawmail.agent.plist:7`
- `Sources/ClawMailCLI/CLI.swift:5`
- `Makefile:114`

Suggested fix direction:
- Decide the intended launch target:
  - either LaunchAgent should run the app bundle executable directly
  - or the CLI needs a real `daemon` mode
- Then align:
  - bundled plist
  - generated plist in `LaunchAgentManager`
  - install docs
  - packaging flow
- Add at least one integration check that validates the launch command exists.

## Other Important Findings

### 6. OAuth refresh path exists but is effectively unused

Severity: Medium-high

Problem:
- Tokens are loaded once during account connect and converted into static credentials for IMAP/SMTP/CalDAV/CardDAV clients.
- `OAuth2Manager.getAccessToken` / refresh logic exists, but it is not wired into the clients or reconnect path.

Impact:
- OAuth accounts will break after access-token expiry.
- Likely to show up after restart, reconnect, or long-running sessions.

Primary references:
- `Sources/ClawMailCore/Auth/CredentialStore.swift:19`
- `Sources/ClawMailCore/AccountOrchestrator.swift:552`
- `Sources/ClawMailCore/Auth/OAuth2Manager.swift:98`
- `Sources/ClawMailApp/Account/OAuthFlowView.swift:118`

Suggested fix direction:
- Introduce a credential abstraction that can fetch/refresh current access tokens on demand.
- Reconnect IMAP/SMTP/DAV clients with fresh tokens when expired.
- Add expiry/refresh tests around OAuth-backed accounts.

### 7. Connection test UI is not actually validating the configured auth path

Severity: Medium

Problem:
- IMAP test only calls `connect()`, not `authenticate()`.
- OAuth account setup still tests SMTP/CalDAV/CardDAV with the password field, even though OAuth tokens were obtained.

Impact:
- False positives for bad IMAP passwords.
- False negatives for valid OAuth setups.

Primary references:
- `Sources/ClawMailApp/Account/ConnectionTestView.swift:83`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift:98`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift:113`

Suggested fix direction:
- Make IMAP test perform full auth.
- Use OAuth tokens for the providers that were configured via OAuth.
- Keep the setup wizard’s auth path aligned with the runtime auth path.

### 8. Audit interface attribution is globally shared and inaccurate

Severity: Medium

Problem:
- Audit logging uses one global `agentInterface` field on the orchestrator.
- REST writes default to `.cli` when no MCP agent is active.
- During an MCP session, unrelated CLI/REST writes can inherit the wrong interface label.

Impact:
- Audit trail is misleading.
- Weakens post-incident traceability.

Primary references:
- `Sources/ClawMailCore/IPC/IPCServer.swift:423`
- `Sources/ClawMailCore/AccountOrchestrator.swift:161`
- `Sources/ClawMailCore/AccountOrchestrator.swift:536`
- `Sources/ClawMailAppLib/Routes/EmailRoutes.swift:107`

Suggested fix direction:
- Pass interface provenance per request, not via global mutable state.
- Thread interface identity through IPC/REST/CLI entry points explicitly.

### 9. Removing an account does not remove stored secrets

Severity: Medium

Problem:
- Account removal disconnects and deletes config/db state.
- Stored Keychain credentials/tokens are left behind.

Impact:
- Privacy cleanup is incomplete.
- Re-adding or reusing account IDs could create surprising behavior later.

Primary references:
- `Sources/ClawMailCore/AccountOrchestrator.swift:140`
- `Sources/ClawMailCore/Auth/CredentialStore.swift:52`
- `Sources/ClawMailCore/Auth/KeychainManager.swift:93`

Suggested fix direction:
- Call credential cleanup during account removal.
- Consider whether OAuth client secrets are account-scoped or global and document accordingly.

### 10. Several persisted settings are ignored at runtime

Severity: Medium

Problem:
- UI persists sync interval, initial sync days, and IDLE folders.
- Runtime still hardcodes 15 minutes and `INBOX` in the scheduler/IDLE startup.

Impact:
- Settings UI is misleading.
- Users may think coverage/rate is configured when it is not.

Primary references:
- `Sources/ClawMailApp/Settings/GeneralTab.swift:31`
- `Sources/ClawMailCore/AccountOrchestrator.swift:107`
- `Sources/ClawMailCore/AccountOrchestrator.swift:620`
- `Sources/ClawMailCore/Sync/SyncScheduler.swift:14`

Suggested fix direction:
- Feed config values into sync scheduler and IDLE monitor startup.
- Decide whether changes are hot-reloaded or require restart.

## Lower-Level Observations Worth Rechecking While Fixing

- Pending approvals table exists but appears unused for actual queued approval workflow.
  - References:
    - `Sources/ClawMailCore/Storage/DatabaseManager.swift:128`
    - `Sources/ClawMailCore/Storage/MetadataIndex.swift:269`
- Multiple calendar/contact/task update/delete paths do brute-force scan of all remote objects by fetching everything first.
  - This is more correctness/performance than security, but could become pathological on large accounts.
- Many settings/UI save paths swallow errors with `try?`, which may hide operational failures.
- README/security claims should be re-audited after fixes, especially around TLS and attachment/path restrictions.

## Commands Run During Review

- `swift build`
- `swift test`
- `swift run ClawMailCLI --help`
- `swift run ClawMailCLI daemon`

Observed outcomes:
- Build passed.
- Tests passed.
- CLI help showed no `daemon` subcommand.
- Explicit daemon invocation failed.

## Recommended Fix Order For New Session

1. Wire OAuth token refresh into actual client use.
2. Fix connection testing logic.
3. Correct audit provenance plumbing.
4. Clean up account-removal credential deletion.
5. Make persisted sync/IDLE settings actually drive runtime behavior.
6. Add regression tests for the remaining items above.

## Suggested Regression Tests To Add

- Symlink escape tests for attachment upload and attachment download.
- DAV URL validation tests rejecting `http://`.
- DAV malicious absolute `href` / home-set cross-origin credential leak tests.
- Per-account recipient approval isolation tests.
- Launch-agent command validity check or packaging smoke test.
- OAuth expiry/refresh flow tests.
- Setup connection test coverage for IMAP auth and OAuth-backed service tests.
- Audit logging provenance tests proving CLI/REST/MCP attribution stays correct under concurrency.
- Account removal test proving Keychain items are deleted.
- Runtime config propagation tests for sync interval and IDLE folders.

## Notes For The Next Session

- The repo is large enough that re-reviewing everything will waste context. Start from this handoff and confirm the remaining issues directly in the referenced files.
- Do not re-open issues 1-5 unless you find a regression. They were fixed and verified with a full `swift test` pass in this session.
- The highest-risk bugs are concentrated in:
  - `Sources/ClawMailCore/Email/EmailManager.swift`
  - `Sources/ClawMailCore/Calendar/CalDAVClient.swift`
  - `Sources/ClawMailCore/Contacts/CardDAVClient.swift`
  - `Sources/ClawMailCore/Storage/DatabaseManager.swift`
  - `Sources/ClawMailCore/Storage/MetadataIndex.swift`
  - `Sources/ClawMailApp/LaunchAgent/LaunchAgentManager.swift`
  - `Resources/com.clawmail.agent.plist`
  - `Sources/ClawMailCore/Auth/OAuth2Manager.swift`
  - `Sources/ClawMailApp/Account/ConnectionTestView.swift`
  - `Sources/ClawMailCore/AccountOrchestrator.swift`
