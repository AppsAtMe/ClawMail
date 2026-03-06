# ClawMail Code Review Handoff

Date: March 6, 2026
Repository: `/Users/andrewrmitchell/Developer/ClawMail`
Purpose: Carry forward a full review into a fresh session with enough context to fix issues without re-reading the entire repo.

## Session Update (March 6, 2026, current latest)

This handoff now reflects the follow-up documentation sync and the deeper settings interaction coverage added after the remaining low-risk cleanup work.

Completed in this session:
- Updated the handoff, README, specification, blueprint, and roadmap so they reflect the shipped MCP launch model, LaunchAgent target, recipient approval workflow, and current testing posture.
- Added `docs/operations-reference.md` with a concise maintainer-focused reference for startup, shutdown, IPC/session behavior, approvals, and local files.
- Added async `ViewInspector`-based app tests that drive real failure flows for API key regeneration, activity-log loading, guardrails approval-state loading, and launch-at-login updates.
- Introduced a small `Inspection` test seam for the relevant settings tabs so hosted SwiftUI state changes can be inspected without affecting production behavior.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 177 passing tests across 25 suites

New tests added in this session:
- `Tests/ClawMailAppTests/SettingsInteractionTests.swift`

Key implementation files changed in this session:
- `README.md`
- `SPECIFICATION.md`
- `BLUEPRINT.md`
- `ROADMAP.md`
- `docs/operations-reference.md`
- `Sources/ClawMailApp/Inspection.swift`
- `Sources/ClawMailApp/Settings/APITab.swift`
- `Sources/ClawMailApp/Settings/ActivityLogTab.swift`
- `Sources/ClawMailApp/Settings/GeneralTab.swift`
- `Sources/ClawMailApp/Settings/GuardrailsTab.swift`

Next issue to start with:
- No confirmed findings remain from the March 6 review handoff.
- If we want to keep investing in UI assurance, the next reasonable increment would be confirmation-driven Accounts-tab tests or broader end-to-end UI automation for multi-step settings flows.

## Session Update (March 6, 2026, previous latest)

This handoff now reflects follow-up UI coverage for the settings error alerts that were added during the March 6 hardening sweep.

Completed in this session:
- Added app-level tests that verify the Accounts, Activity Log, API, General, and Guardrails settings tabs all render the "Operation Failed" alert with the expected message when an error state is present.
- Introduced narrow test seams on the settings tabs so app tests can construct them without touching live config, launch agent, or orchestrator state.
- Added `ViewInspector` as a test-only dependency for SwiftUI alert inspection in `ClawMailAppTests`.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 172 passing tests across 24 suites

New tests added in this session:
- `Tests/ClawMailAppTests/SettingsErrorAlertTests.swift`

Key implementation files changed in this session:
- `Package.swift`
- `Sources/ClawMailApp/Settings/AccountsTab.swift`
- `Sources/ClawMailApp/Settings/ActivityLogTab.swift`
- `Sources/ClawMailApp/Settings/APITab.swift`
- `Sources/ClawMailApp/Settings/GeneralTab.swift`
- `Sources/ClawMailApp/Settings/GuardrailsTab.swift`

Next issue to start with:
- The remaining follow-up from the broader review is still the low-risk `try?` sweep outside these settings flows, with `AppDelegate` notification setup and IPC cleanup paths still the most obvious candidates.
- If we want deeper UI assurance beyond alert rendering, the next increment would be interaction-level settings tests that drive failing actions end-to-end.

## Session Update (March 6, 2026, newest latest)

This handoff now reflects follow-up cleanup on the remaining low-risk `try?` / silent-failure paths that were still worth tightening after the original review findings were closed.

Completed in this session:
- Scheduled and manual `SyncScheduler` runs no longer swallow sync failures silently. Errors are formatted, logged, and forwarded through the orchestrator `onError` callback.
- `SyncScheduler.stop()` now awaits task shutdown so test runs and app shutdown do not leave the background scheduler task lingering after cancellation.
- `LaunchAgentManager.uninstall()` no longer always reports success. Install/uninstall now share small injected helper seams so failure handling can be tested without invoking the real `launchctl` binary.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 167 passing tests across 23 suites

New tests added in this session:
- `Tests/ClawMailAppTests/LaunchAgentManagerTests.swift`
- `Tests/ClawMailCoreTests/SyncSettingsRuntimeTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailCore/Sync/SyncScheduler.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Sources/ClawMailApp/LaunchAgent/LaunchAgentManager.swift`

Next issue to start with:
- UI-level coverage for the settings error alerts is still the most obvious follow-up if we want better verification around the March 6 settings hardening.
- Remaining `try?` uses are now mostly best-effort cleanup, decoding probes, or notification side effects; if continuing the sweep, the next candidates are `AppDelegate` notification setup and the IPC cleanup paths.

## Session Update (March 6, 2026, newest latest)

This handoff now reflects follow-up fixes for the remaining lower-level review observations that were still open after the pending-approval workflow work.

Completed in this session:
- Calendar, contact, and task update/delete flows now use UID-targeted DAV `REPORT` queries to locate the exact remote resource before mutating it.
- DAV writes now use the server-reported resource `href` instead of assuming objects live at `/<UID>.ics` or `/<UID>.vcf`.
- Settings/UI paths that previously swallowed important save/action failures now surface user-visible error alerts in the Accounts, Activity Log, API, General, and Guardrails tabs.
- README security claims were re-audited and updated to match the March 6 hardening work around HTTPS-only DAV, same-origin DAV follow-up validation, held-send approvals, and symlink-aware attachment path enforcement.

Current build/test status after these fixes:
- `swift build`: passed
- `swift test`: passed
- Test suite reported 162 passing tests across 23 suites

New tests added in this session:
- `Tests/ClawMailCoreTests/DAVResourceLookupTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift`
- `Sources/ClawMailCore/Calendar/CalendarManager.swift`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift`
- `Sources/ClawMailCore/Contacts/ContactsManager.swift`
- `Sources/ClawMailCore/Tasks/TaskManager.swift`
- `Sources/ClawMailApp/UIErrorState.swift`
- `Sources/ClawMailApp/Settings/AccountsTab.swift`
- `Sources/ClawMailApp/Settings/ActivityLogTab.swift`
- `Sources/ClawMailApp/Settings/APITab.swift`
- `Sources/ClawMailApp/Settings/GeneralTab.swift`
- `Sources/ClawMailApp/Settings/GuardrailsTab.swift`
- `README.md`

Next issue to start with:
- No confirmed findings remain from the original March 6 review handoff.
- If continuing, the next sensible follow-up would be UI-level coverage for the new settings error alerts or a sweep of the remaining low-risk `try?` uses outside settings flows.

## Session Update (March 6, 2026, newest latest)

This handoff now reflects fixes through the pending-approval workflow observation that was still open after issues 1-10.

Completed in this session:
- Pending recipient approvals now persist the blocked outgoing request instead of only throwing an error. Send, reply, and forward requests are held in `pending_approvals`, keyed by a request ID, and replay once the required recipients are approved.
- Pending approvals are now exposed through the orchestrator, JSON-RPC, REST routes, CLI commands, and the Guardrails settings tab. Held sends can be listed, approved, or rejected explicitly.
- Ready held sends are retried automatically after approval, when the relevant account reconnects, and when first-time recipient approval is disabled at runtime.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 159 passing tests across 22 suites

New tests added in this session:
- `Tests/ClawMailCoreTests/PendingApprovalWorkflowTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailCore/Models/PendingApproval.swift`
- `Sources/ClawMailCore/Storage/MetadataIndex.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Sources/ClawMailCore/IPC/IPCDispatcher.swift`
- `Sources/ClawMailAppLib/Routes/RecipientsRoutes.swift`
- `Sources/ClawMailCLI/Commands/RecipientsCommands.swift`
- `Sources/ClawMailApp/Settings/GuardrailsTab.swift`

Next issue to start with:
- Recheck the remaining lower-level observations:
  - calendar/contact/task update-delete paths that still brute-force fetch large remote collections
  - settings/UI save paths that still swallow failures with `try?`
  - README/security claim audit after the March 6 fixes

## Session Update (March 6, 2026, latest)

This handoff now reflects fixes for issues 1-10. Issues 9-10 were completed after the earlier March 6 update below and verified with a full test pass.

Completed in this session:
- 9. Account removal now deletes stored per-account Keychain secrets before config/database cleanup. Passwords and OAuth tokens are removed alongside account metadata.
- 10. Persisted sync settings now drive runtime behavior. The scheduler uses the configured sync interval and folder list, initial sync honors `initialSyncDays`, and General settings hot-apply sync changes to the running orchestrator instead of only saving them to disk.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 154 passing tests across 21 suites

New tests added in this session:
- `Tests/ClawMailCoreTests/AccountRemovalCredentialCleanupTests.swift`
- `Tests/ClawMailCoreTests/SyncSettingsRuntimeTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Sources/ClawMailCore/Auth/KeychainManager.swift`
- `Sources/ClawMailCore/Storage/MetadataIndex.swift`
- `Sources/ClawMailCore/Sync/SyncScheduler.swift`
- `Sources/ClawMailApp/Settings/GeneralTab.swift`

Next issue to start with:
- Recheck the lower-level observations, starting with the pending-approval workflow that still appears disconnected from actual queued approval handling.

## Session Update (March 6, 2026, earlier latest)

This handoff reflected fixes for issues 1-8. Issues 6-8 were completed after the earlier March 6 update below and verified with a full test pass.

Completed in this session:
- 6. OAuth-backed credentials now fetch access tokens on demand through a token-provider abstraction. Expired tokens refresh through `OAuth2Manager` before IMAP/SMTP/CalDAV/CardDAV authentication and request use.
- 7. Account setup connection testing now exercises the configured auth path. IMAP performs full auth, and OAuth-based setup uses OAuth tokens instead of the password field for SMTP/CalDAV/CardDAV tests.
- 8. Audit provenance is now passed per request instead of inferred from the global agent lock. IPC sessions map to `.cli` or `.mcp`, REST write routes pass `.rest`, and active MCP sessions no longer mislabel unrelated CLI/REST writes.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 149 passing tests across 19 suites

New tests added in this session:
- `Tests/ClawMailCoreTests/OAuthRefreshTests.swift`
- `Tests/ClawMailAppTests/ConnectionTestAuthMaterialTests.swift`
- `Tests/ClawMailCoreTests/AuditProvenanceTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailCore/Auth/OAuthTokenProvider.swift`
- `Sources/ClawMailCore/Auth/CredentialStore.swift`
- `Sources/ClawMailCore/Auth/OAuth2Manager.swift`
- `Sources/ClawMailCore/Auth/KeychainManager.swift`
- `Sources/ClawMailCore/Email/IMAPClient.swift`
- `Sources/ClawMailCore/Email/SMTPClient.swift`
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Sources/ClawMailCore/IPC/IPCServer.swift`
- `Sources/ClawMailCore/IPC/IPCDispatcher.swift`
- `Sources/ClawMailApp/Account/ConnectionTestAuthMaterial.swift`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift`
- `Sources/ClawMailApp/Account/AccountSetupView.swift`
- `Sources/ClawMailAppLib/Routes/EmailRoutes.swift`
- `Sources/ClawMailAppLib/Routes/CalendarRoutes.swift`
- `Sources/ClawMailAppLib/Routes/ContactsRoutes.swift`
- `Sources/ClawMailAppLib/Routes/TasksRoutes.swift`
- `Package.swift`

Next issue to start with:
- 9. Removing an account does not remove stored secrets

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

Status: Fixed on March 6, 2026, after the earlier handoff update.

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

Status: Fixed on March 6, 2026, after the earlier handoff update.

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

Status: Fixed on March 6, 2026, after the earlier handoff update.

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

1. Clean up account-removal credential deletion.
2. Make persisted sync/IDLE settings actually drive runtime behavior.
3. Recheck the pending-approval workflow and other lower-level observations once 9-10 are done.
4. Add regression tests for the remaining items above.

## Suggested Regression Tests To Add

- Account removal test proving Keychain items are deleted.
- Runtime config propagation tests for sync interval and IDLE folders.
- Pending-approval workflow tests if that table is wired into real approval queueing.

## Notes For The Next Session

- The repo is large enough that re-reviewing everything will waste context. Start from this handoff and confirm the remaining issues directly in the referenced files.
- Do not re-open issues 1-8 unless you find a regression. They were fixed and verified with a full `swift test` pass across 149 tests in 19 suites.
- The highest-risk bugs are concentrated in:
  - `Sources/ClawMailCore/AccountOrchestrator.swift`
  - `Sources/ClawMailCore/Auth/CredentialStore.swift`
  - `Sources/ClawMailCore/Auth/KeychainManager.swift`
  - `Sources/ClawMailCore/Models/Config.swift`
  - `Sources/ClawMailCore/Sync/SyncScheduler.swift`
  - `Sources/ClawMailCore/Email/IMAPIdleMonitor.swift`
  - `Sources/ClawMailApp/Settings/GeneralTab.swift`
