# ClawMail Code Review Handoff

Date: March 8, 2026
Repository: `/Users/andrewrmitchell/Developer/ClawMail`
Purpose: Carry forward a full review into a fresh session with enough context to fix issues without re-reading the entire repo.

## Fresh Session Starting Point

- Pre-handoff checkpoint before the Google/provider push: `7027ec6` (`Finish account edit polish and quiet NIO warnings`)
- Best restart point: begin from the newest commit that contains this handoff note, then continue from the unresolved Google CardDAV finding described in the current latest update below
- Current user-testing status: Apple / iCloud is verified by hand; Google OAuth mail + calendar are working; Google CardDAV is still blocked; Fastmail and Microsoft manual verification remain to do

## Session Update (March 8, 2026, newest latest)

This handoff now reflects the next live Google CardDAV discovery result after ClawMail started requesting the server-advertised `https://www.googleapis.com/auth/carddav` scope.

Completed in this session:
- Captured a live Google OAuth token response showing that browser sign-in now grants `https://www.googleapis.com/auth/carddav` alongside mail/calendar/openid scopes.
- Captured the next live CardDAV discovery behavior after that scope fix:
  - `PROPFIND https://www.googleapis.com/.well-known/carddav`
  - HTTP `301` redirect to `https://www.googleapis.com/carddav/v1/principals/<authorized-email>/lists/default/`
  - immediate HTTP `400` when ClawMail asked that redirected resource for `current-user-principal`
- Added a Google-specific CardDAV fallback so if `.well-known/carddav` resolves directly to an address-book collection and Google's server rejects the principal-style `PROPFIND`, ClawMail retries against that same resource with `displayname` + `resourcetype`, confirms it is an address book, and uses it as the address-book home.
- Added regression coverage for that exact Google `301 -> 400 -> fallback succeeds` path.

Current interpretation after this pass:
- The Google scope problem appears resolved: Google's token endpoint granted `https://www.googleapis.com/auth/carddav`.
- The remaining Google blocker was a discovery-shape mismatch, not missing OAuth permission.
- Google appears willing to redirect `.well-known/carddav` straight to the default address-book collection for the signed-in account, and that resource does not accept a `current-user-principal` lookup.

Most useful next step for a fresh session:
1. Fully quit and relaunch the installed app.
2. Re-run Google browser sign-in once more.
3. Retry CardDAV and capture the new `ClawMail CardDAV:` lines.
4. Confirm the log now shows `Google address book fallback accepted resource ...` and that address-book listing proceeds instead of stopping at HTTP `400`.

Current build/test/install status after these fixes:
- `swift test`: passed
- Test suite reported 222 passing tests across 32 suites
- `make install`: passed
- Updated app bundle installed to `/Applications/ClawMail.app`

## Session Update (March 8, 2026, newer latest)

This handoff now reflects the next Google CardDAV debugging step after capturing both the OAuth token scopes and the live CardDAV `WWW-Authenticate` challenge from Google's server.

Completed in this session:
- Captured a live Google OAuth token response showing that browser sign-in granted `https://www.googleapis.com/auth/contacts`, `https://www.googleapis.com/auth/calendar`, and `https://mail.google.com/`.
- Captured the first live CardDAV `PROPFIND` failure to `https://www.googleapis.com/.well-known/carddav`, which returned HTTP `403` before any redirect occurred.
- Captured the decisive Google `WWW-Authenticate` challenge header from that 403 response:
  `error="insufficient_scope", scope="https://www.googleapis.com/auth/carddav"`
- Updated ClawMail's Google OAuth scope request from the old legacy Contacts/CardDAV assumption to the live server-advertised CardDAV scope `https://www.googleapis.com/auth/carddav`.
- Removed the app-side assumption that the broader Google Contacts scope `https://www.googleapis.com/auth/contacts` is sufficient for CardDAV.
- Updated the Google setup copy, diagnostics, README, and verification checklist to point at `https://www.googleapis.com/auth/carddav`.
- Updated CardDAV auth failures to include the required scope from the `WWW-Authenticate` header in the user-visible error when Google provides one.

Current interpretation after this pass:
- Google's live CardDAV endpoint is the strongest source we have now, and it explicitly says the token needs `https://www.googleapis.com/auth/carddav`.
- The earlier `m8/feeds` / canonical-contacts-scope theory is no longer the best explanation for the current blocker.
- The next test should be done only after re-running Google browser sign-in on a build that requests `https://www.googleapis.com/auth/carddav`.

Most useful next step for a fresh session:
1. Re-run Google browser sign-in on the latest installed build.
2. Confirm the OAuth scope log now includes `https://www.googleapis.com/auth/carddav`.
3. Retry CardDAV.
4. If CardDAV still fails, capture the updated `ClawMail CardDAV:` lines and compare Google's granted scopes against the CardDAV challenge header again.

Current build/test/install status after these fixes:
- Focused DAV and OAuth-related tests passed locally
- `make install`: passed
- Updated app bundle installed to `/Applications/ClawMail.app`

## Session Update (March 8, 2026, current latest)

This handoff now reflects the first follow-up pass on the Google CardDAV blocker after re-checking the current Google docs and tightening ClawMail's own scope handling.

Completed in this session:
- Re-checked the Google docs from primary sources and found the key clue in the Contacts API migration guide: Google documents the legacy Contacts scope `https://www.google.com/m8/feeds` as an alias of the canonical People API scope `https://www.googleapis.com/auth/contacts`.
- Updated `ConnectionTestAuthMaterial` so Google Contacts scope checks now treat those two scope strings as equivalent instead of treating the canonical scope as a hard failure.
- Removed the Google CardDAV preflight false negative that could block the CardDAV connection test before ClawMail even tried the DAV request, simply because Google returned the canonical scope label.
- Added OAuth debug logging for interactive browser sign-in in `OAuthFlowView` so `/tmp/clawmail.stderr.log` now records the requested Google scopes, a redacted authorization URL, the token-response granted scope list, and the authorized Google email when present.
- Updated the in-app Google recovery copy, Settings > API guidance, README, and verification checklist to say that Google may report the legacy CardDAV scope back as `https://www.googleapis.com/auth/contacts`.
- Added regression coverage so app-side Google scope checks now explicitly accept the canonical Contacts scope as satisfying the legacy CardDAV scope check.

Current interpretation after this pass:
- The March 7 failure that said Google granted `https://www.googleapis.com/auth/contacts` but not `https://www.google.com/m8/feeds` now looks more like a ClawMail diagnostic bug than proof that Google denied the needed Contacts permission.
- The earlier March 7 6:25 PM Google CardDAV `insufficient authentication scopes` error is still worth retesting on this new build, because that earlier run happened before the alias-aware logic and before the new OAuth scope logging.

Most useful next step for a fresh session:
1. Re-run Google browser sign-in on the latest build.
2. Re-test Google CardDAV without changing anything else first.
3. If CardDAV still fails, capture the exact CardDAV error plus the new OAuth log lines from `/tmp/clawmail.stderr.log` showing the requested scopes and granted scopes.
4. Only after that, decide whether the remaining problem is still Google-platform behavior or something in ClawMail's DAV request path.

Current build/test status after these fixes:
- `swift test`: passed
- Test suite reported 221 passing tests across 32 suites
- Manual Google verification on this exact build has not been rerun yet

## Session Update (March 7, 2026, current latest)

This handoff now reflects the provider-verification push after Apple was verified, including the Google OAuth crash fixes, account-binding improvements, and the still-open Google CardDAV scope issue.

Completed in this session:
- Added first-class provider behavior for Google, Microsoft 365 / Outlook, and Fastmail so the setup sheet is no longer Apple-only polished.
- Made the Google provider row use a full-width hit target instead of only reacting near the mail icon.
- Fixed multiple OAuth crash/timeout paths in `OAuthCallbackServer` and the connection-test UI, including the `dispatch_assert_queue` / main-actor isolation crash seen after the Google browser flow completed.
- Added PKCE to the desktop OAuth flow and hardened callback-server cleanup, timeout, and provider-error handling.
- Corrected Microsoft OAuth scopes to use Outlook's real IMAP/SMTP delegated scopes.
- Clarified the API settings UI so `Client ID` and `Client Secret` are explained as values created in Google Cloud / Microsoft Entra, not app-generated values.
- Reduced spurious first-save Keychain prompts by reusing in-memory credentials for the initial connect path instead of immediately round-tripping through Keychain.
- Added granted-scope diagnostics to Google connection failures so the app now distinguishes “Google did not grant the scope” from “Google granted something, but CardDAV still rejected the token.”
- Bound the authorized Google identity back into setup: the typed email is now only a `login_hint`, and after browser sign-in ClawMail reads the authorized email from Google’s `id_token`, replaces the field with that verified address, and uses it for account save / Google CalDAV defaults.
- Replaced the dimmed OAuth email field with an explicit `Authorized Email` banner after sign-in so the verified-account state is obvious again.
- Updated Google setup docs throughout the app, README, checklist, and recovery copy.
- Added branding assets and wiring for the new app icon / splash artwork, plus the helper script and source-artwork files used to generate them.

What was manually verified this session:
- Google browser sign-in no longer crashes the app.
- Google IMAP and SMTP connect successfully.
- Google CalDAV connects successfully.
- The authorized Google email is now surfaced in the UI instead of silently trusting the manually typed address.

Open blocker at handoff:
- Google CardDAV still fails even after the broader OAuth hardening work.
- Evidence from the March 7, 2026 6:25 PM screenshot:
  ClawMail showed `Request had insufficient authentication scopes` while also reporting that Google granted `https://www.googleapis.com/auth/contacts`.
- Interpretation:
  The newer People API contacts scope appears insufficient for Google CardDAV.
- Follow-up change already implemented after that evidence:
  ClawMail now requests the legacy Google Contacts/CardDAV scope `https://www.google.com/m8/feeds` instead, updates the diagnostics accordingly, and tells the user to re-run browser sign-in instead of just pressing `Retry Test`.
- Evidence from the March 7, 2026 6:44 PM screenshot after the user manually added feeds in Google Cloud:
  ClawMail still reported `Authentication failed: Google browser sign-in granted the newer Contacts scope, but not the legacy Google CardDAV contacts scope.`
- Current interpretation:
  either Google Auth platform `Data Access` is not actually adding `https://www.google.com/m8/feeds` to the installed-app consent flow, or Google’s current desktop/OAuth UI requires a different CardDAV permission strategy than the one we are using.

Most useful next step for a fresh session:
1. Re-check the current Google CardDAV docs and current Google OAuth/Data Access docs from primary sources.
2. Confirm whether `https://www.google.com/m8/feeds` is still the required Google CardDAV scope for installed apps in March 2026, or whether Google now expects a different scope or consent-screen configuration.
3. If the scope is correct, instrument/log the exact authorization URL and exact token response scope list during a fresh Google sign-in to verify whether Google is silently dropping the legacy scope.
4. If Google is dropping the scope, inspect whether the consent-screen configuration or app-verification state is filtering it out.

Small UX follow-up captured from manual testing:
- The earlier `Quitting...` feedback in the menu bar apparently felt less prominent in later manual testing; the user described it as no longer reading as a strong status message, more like a light highlight. This was not root-caused in this session and may need a quick visual re-check in the next one.

Current build/test/install status after these fixes:
- `swift test`: passed
- Test suite reported 220 passing tests across 32 suites
- `swift build -c release`: passed
- `make install`: passed
- Updated app bundle installed to `/Applications/ClawMail.app`

New tests added in this push:
- `Tests/ClawMailCoreTests/OAuthCallbackServerTests.swift`
- `Tests/ClawMailAppTests/AccountSetupCredentialStateTests.swift`
- `Tests/ClawMailCoreTests/OAuthRefreshTests.swift` gained PKCE, granted-scope, login-hint, authorized-email, and refresh-preserves-identity coverage
- `Tests/ClawMailCoreTests/DAVSecurityTests.swift` gained CardDAV redirect/auth-detail coverage
- `Tests/ClawMailAppTests/ConnectionTestAuthMaterialTests.swift` and `Tests/ClawMailAppTests/AccountSetupProviderTests.swift` gained Google/provider coverage

Key implementation files changed in this push:
- `Makefile`
- `Package.swift`
- `Sources/ClawMailApp/Account/AccountSetupView.swift`
- `Sources/ClawMailApp/Account/ConnectionTestAuthMaterial.swift`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift`
- `Sources/ClawMailApp/Account/OAuthFlowView.swift`
- `Sources/ClawMailApp/Settings/APITab.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Sources/ClawMailCore/Auth/KeychainManager.swift`
- `Sources/ClawMailCore/Auth/OAuth2Manager.swift`
- `Sources/ClawMailCore/Auth/OAuthCallbackServer.swift`
- `Sources/ClawMailCore/Auth/OAuthHelpers.swift`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift`
- `Sources/ClawMailCore/Models/Account.swift`
- `Sources/ClawMailApp/Resources/AppIcon.icns`
- `Sources/ClawMailApp/Resources/Branding/*`
- `Sources/ClawMailApp/Shared/BrandingAsset.swift`
- `scripts/generate_brand_assets.py`
- `Design/SourceArtwork/*`
- `README.md`
- `docs/account-verification-checklist.md`
- `docs/code-review-handoff.md`

Next issue to start with:
- Finish the Google CardDAV investigation described above.
- After Google is either fixed or conclusively classified as a current Google-platform limitation, continue human verification with Fastmail and Microsoft OAuth.

## Session Update (March 7, 2026, previous latest)

This handoff now reflects the follow-up polish pass after the account-edit checkpoint.

Completed in this session:
- Tightened edit-mode credential reuse so saved Keychain passwords/OAuth tokens are only reused after preload finishes, avoiding premature connection tests with missing auth material.
- Added an explicit existing-account banner and credential-status messaging in the setup sheet so editing feels persistent instead of like a fresh add flow.
- Reworked the Accounts-tab setup sheet presentation to use a fresh session for every add/edit open, fixing the stale-sheet bug where `Edit Account...` could reopen the previous add flow.
- Made the connection-test results card scroll independently and added recovery copy so `Back` / `Retry Test` stay reachable after multi-service failures.
- Updated CalDAV/CardDAV to track the effective HTTPS origin returned by redirects, preserve discovered absolute DAV home-set URLs, and trust Apple's partitioned iCloud DAV host families (`pXX-*.icloud.com`, including the `calendarws` / `contactsws` variants) without dropping the cross-origin protections.
- Added a `Quitting...` loading state to the menu bar quit action so shutdown gives immediate visual feedback before the app exits.
- Added focused app tests covering saved-password reuse, delayed saved-OAuth-token reuse, edit-mode provider changes that require fresh credentials, fresh add/edit sheet sessions, and Apple-style DAV redirected/sharded origins.
- Cleaned up the remaining Swift 6/NIO concurrency warnings by moving NIO pipeline mutations in `OAuthCallbackServer`, IMAP/SMTP, and IPC onto event-loop `syncOperations` instead of the async `Sendable`-checked helpers.
- Re-ran the local verification paths, confirmed `swift test` passes, confirmed the release install succeeds, and manually verified that the Apple/iCloud edit flow now tests green across IMAP, SMTP, CalDAV, and CardDAV.

Current build/test/install status after these fixes:
- `swift test`: passed
- Test suite reported 204 passing tests across 31 suites
- `swift build -c release`: passed
- `make install`: passed
- Release builds are clean; the earlier Swift 6/NIO `Sendable` warnings in `OAuthCallbackServer`, IMAP/SMTP, and IPC are gone

New tests added in this session:
- `Tests/ClawMailAppTests/AccountSetupCredentialStateTests.swift`
- `Tests/ClawMailAppTests/SetupSheetControllerTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailApp/Account/AccountSetupView.swift`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift`
- `Sources/ClawMailApp/MenuBar/StatusMenu.swift`
- `Sources/ClawMailApp/Settings/AccountsTab.swift`
- `Sources/ClawMailCore/Auth/OAuthCallbackServer.swift`
- `Sources/ClawMailCore/Calendar/CalDAVClient.swift`
- `Sources/ClawMailCore/Contacts/CardDAVClient.swift`
- `Sources/ClawMailCore/DAVURLValidator.swift`
- `Sources/ClawMailCore/Email/IMAPClient.swift`
- `Sources/ClawMailCore/Email/SMTPClient.swift`
- `Sources/ClawMailCore/IPC/IPCClient.swift`
- `Sources/ClawMailCore/IPC/IPCServer.swift`
- `Tests/ClawMailAppTests/AccountSetupCredentialStateTests.swift`
- `Tests/ClawMailAppTests/SetupSheetControllerTests.swift`
- `Tests/ClawMailCoreTests/DAVSecurityTests.swift`
- `ROADMAP.md`
- `docs/code-review-handoff.md`

Next issue to start with:
- Resume manual provider verification beyond the now-passing Apple/iCloud flow, starting with Google OAuth, then generic IMAP/SMTP + DAV, and Microsoft OAuth.
- After provider verification, the main remaining backlog is the product-polish work in `ROADMAP.md` (welcome/onboarding, branded app icon, custom menu bar icon, and event-driven UI refresh).

This handoff now reflects the latest checkpoint after account-editing work and startup Keychain-prompt cleanup.

Completed in this session:
- Added a real existing-account edit path in Settings so configured accounts can now be updated in place instead of only removed and re-added.
- Wired the Accounts tab and account detail pane to open the setup sheet in edit mode for the selected account.
- Added orchestrator-level account updates that preserve the existing account identity, save the new configuration, reconnect enabled accounts, and roll back on failure.
- Made the edit flow infer the provider from the existing account, preseed provider defaults, and reuse the currently stored password/OAuth tokens when possible.
- Removed the app's eager REST API Keychain read from launch, so startup no longer pulls the API key just to boot the menu bar app.
- Confirmed with live manual verification that startup Keychain prompts dropped from two prompts to one prompt.
- Added regression coverage for provider inference, account updates, and API server startup without a preloaded API key.

Known issue at that checkpoint (now addressed in the current latest update above):
- The new edit flow is not fully buttoned up yet. Manual testing showed that editing an existing account still feels too much like a fresh add flow, connection tests in edit mode failed across all configured services, and a four-failure result set can push the navigation buttons below the bottom edge of the sheet so recovery is awkward. This is now an explicit backlog item in `ROADMAP.md` and should be the first follow-up in a fresh context.

Additional follow-up captured from manual testing at that checkpoint (now addressed above):
- Quitting from the menu bar still feels sluggish/ambiguous because there is no clear visual pressed/loading feedback before the app exits. This is now tracked in `ROADMAP.md`.

Current build/test/install status after these fixes:
- `swift test`: passed
- Test suite reported 192 passing tests across 29 suites
- `make install`: passed
- Updated app bundle installed to `/Applications/ClawMail.app`

New tests added in this session:
- `Tests/ClawMailCoreTests/AccountUpdateTests.swift`
- `Tests/ClawMailAppTests/AccountSetupProviderTests.swift` gained provider inference coverage
- `Tests/ClawMailAppLibTests/APITests.swift` now covers API server startup without a preloaded launch-time API key

Key implementation files changed in this session:
- `Sources/ClawMailApp/Settings/AccountsTab.swift`
- `Sources/ClawMailApp/Account/AccountSetupView.swift`
- `Sources/ClawMailApp/AppDelegate.swift`
- `Sources/ClawMailAppLib/APIServer.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Tests/ClawMailCoreTests/AccountUpdateTests.swift`
- `Tests/ClawMailAppTests/AccountSetupProviderTests.swift`
- `Tests/ClawMailAppLibTests/APITests.swift`
- `ROADMAP.md`
- `docs/code-review-handoff.md`

Next issue to start with:
- Fix the remaining edit-account UX regression: keep the sheet recoverable after multi-service failures, make the prefilled state feel obviously persistent, and understand why edit-mode connection tests are failing for an already-working Apple account.
- After that, resume provider verification with Google OAuth and the generic IMAP/SMTP + DAV path.

## Session Update (March 6, 2026, previous latest)

This handoff now reflects follow-up UX and manual-testing fixes after the first real provider setup pass.

Completed in this session:
- Added `Apple / iCloud` as a first-class provider option in the account setup wizard instead of forcing Apple users through the generic `Other` path.
- Made `Apple / iCloud` the default provider choice and locked the picker order with regression coverage.
- Prefilled the Apple/iCloud provider with Apple's published IMAP/SMTP settings and kept it on the password/app-specific-password path rather than the Google/Microsoft OAuth flow.
- Updated provider naming and account auth labels so setup reads more like a native Mac app (`Apple / iCloud`, `Microsoft 365 / Outlook`, `Other Mail Account`).
- Increased the account-setup sheet height and made the provider-selection step scrollable so the navigation buttons remain reachable with all four provider rows visible.
- Improved failed connection-test results so the messages are aligned, selectable, and can include a clickable recovery link for provider-specific guidance.
- Root-caused a later app abort to `SyncScheduler`'s default `Task.sleep` path firing around the 15-minute scheduled-sync interval, then replaced that sleep implementation with a dispatch-timer-based helper to avoid the Swift concurrency deallocation crash.
- Tightened the manual log-tail instructions to clear old stderr output and show only new lines during app testing.
- Fixed setup reruns after credential edits so moving back from a failed test and pressing `Test Connection` starts a fresh test instead of dumping the user onto stale results.
- Made account saves behave more honestly in the UI by showing a saving/connecting state, surfacing a pending account immediately, and only showing the final success step after the add/connect path actually completes.
- Wired startup and runtime connection/activity callbacks into `AppState` so the menu bar and Accounts settings screen can show live account activity instead of stale snapshots.
- Replaced the account status dots with explicit status icons/checkmarks and added recent-activity text in the account detail view and menu bar.
- Added internal `app` audit entries for account lifecycle events (`account.add`, `account.connect`, `account.disconnect`, `account.remove`) so the Activity Log no longer starts empty after normal app usage.
- Improved the Activity Log tab with a manual refresh action, explicit `Auto-refresh (5s)` wording, empty-state messaging, and a last-refreshed timestamp.
- Added provider-model regression tests covering the new Apple/iCloud path and the existing OAuth provider metadata.
- Added a scheduler regression test to ensure stopping the default background-sync loop cancels promptly.
- Fixed the manual testing/log-tail mismatch by making normal app launches append to `/tmp/clawmail.stdout.log` and `/tmp/clawmail.stderr.log`, not just LaunchAgent runs.
- Updated the verification checklist and maintainer docs to background the log tail command and reflect the Apple/iCloud path.

Current build/test status after these fixes:
- `swift build -c release`: passed
- `swift test`: passed
- Test suite reported 183 passing tests across 27 suites

New tests added in this session:
- `Tests/ClawMailAppTests/AccountSetupProviderTests.swift`

Key implementation files changed in this session:
- `Sources/ClawMailApp/ClawMailApp.swift`
- `Sources/ClawMailApp/Account/AccountSetupView.swift`
- `Sources/ClawMailApp/Account/ConnectionTestView.swift`
- `Sources/ClawMailApp/Account/OAuthFlowView.swift`
- `Sources/ClawMailApp/Settings/AccountsTab.swift`
- `Sources/ClawMailApp/Settings/ActivityLogTab.swift`
- `Sources/ClawMailApp/MenuBar/StatusMenu.swift`
- `Sources/ClawMailApp/AppState.swift`
- `Sources/ClawMailApp/AppDelegate.swift`
- `Sources/ClawMailCore/Models/Account.swift`
- `Sources/ClawMailCore/Models/AuditEntry.swift`
- `Sources/ClawMailCore/Sync/SyncScheduler.swift`
- `Sources/ClawMailCore/AccountOrchestrator.swift`
- `Tests/ClawMailAppTests/AccountSetupProviderTests.swift`
- `Tests/ClawMailCoreTests/SyncSettingsRuntimeTests.swift`
- `README.md`
- `docs/account-verification-checklist.md`
- `docs/operations-reference.md`
- `ROADMAP.md`
- `docs/code-review-handoff.md`

Next issue to start with:
- Manual provider verification should begin with the new Apple/iCloud path, then continue with Google OAuth, generic IMAP/SMTP + DAV, and Microsoft OAuth.
- Remaining warnings are still concentrated in the Swift 6/NIO concurrency boundary for `OAuthCallbackServer`, IMAP/SMTP, and IPC.
- UI polish backlog remains open for a welcome/onboarding screen, branded app icon, and custom menu bar icon.

## Session Update (March 6, 2026, previous latest)

This handoff now reflects follow-up fixes from the first manual app launch pass after the first-launch UX changes.

Completed in this session:
- Root-caused the disappearing menu bar icon to a startup crash in `APIServer.start()`, not the menu bar lifecycle itself.
- Replaced the embedded REST server's brittle `Task.sleep` startup delay with a real startup handshake using Hummingbird's `onServerRunning` callback.
- Stopped the embedded REST server from registering process-wide SIGINT/SIGTERM handlers inside the menu bar app process.
- Added a live app-lib regression test that starts `APIServer`, hits `GET /api/v1/status`, and shuts the server down.
- Verified that launching the built `.app` bundle now keeps the `ClawMailApp` process alive instead of aborting immediately on startup.

Current build/test status after these fixes:
- `swift build -c release`: passed
- `swift test`: passed
- Test suite reported 179 passing tests across 26 suites

New tests added in this session:
- `Tests/ClawMailAppLibTests/APITests.swift` gained `APIServerLifecycleTests`

Key implementation files changed in this session:
- `Sources/ClawMailAppLib/APIServer.swift`
- `Tests/ClawMailAppLibTests/APITests.swift`
- `docs/code-review-handoff.md`

Next issue to start with:
- Remaining warnings are still concentrated in the Swift 6/NIO concurrency boundary for `OAuthCallbackServer`, IMAP/SMTP, and IPC.
- UI polish backlog remains open for a branded app icon and a custom menu bar icon.

## Session Update (March 6, 2026, previous latest)

This handoff now reflects follow-up fixes from the first real app-install/manual-smoke pass after the March 6 hardening work.

Completed in this session:
- Fixed first-launch discoverability for the menu bar app. Empty-account startup now opens Settings automatically and triggers the add-account flow instead of leaving the user at a silent menu bar-only state after launch.
- Added an `Add Account...` shortcut to the menu bar status menu when no accounts are configured.
- Made `make install` / `make uninstall` degrade gracefully when the CLI symlink target directory is not writable, and documented the fallback paths in the README.
- Added a regression test for the account-setup auto-presentation path and cleaned up the remaining non-NIO warnings in the app test helpers.
- Captured the still-open UX polish items (app icon, custom menu bar icon) and the remaining Swift 6/NIO warning cleanup as explicit roadmap backlog items.

Current build/test status after these fixes:
- `swift build -c release`: passed
- `swift test`: passed
- Test suite reported 178 passing tests across 25 suites

New tests added in this session:
- `Tests/ClawMailAppTests/SettingsInteractionTests.swift` gained startup/setup coverage

Key implementation files changed in this session:
- `Makefile`
- `README.md`
- `ROADMAP.md`
- `Sources/ClawMailApp/AppDelegate.swift`
- `Sources/ClawMailApp/MenuBar/StatusMenu.swift`
- `Sources/ClawMailApp/Settings/AccountsTab.swift`
- `Sources/ClawMailCore/Auth/OAuthCallbackServer.swift`
- `Tests/ClawMailAppTests/SettingsInteractionTests.swift`
- `Tests/ClawMailCoreTests/SecurityTests.swift`
- `Tests/ClawMailIntegrationTests/IntegrationTestHelpers.swift`

Next issue to start with:
- Remaining warnings are now concentrated in the Swift 6/NIO concurrency boundary for `OAuthCallbackServer`, IMAP/SMTP, and IPC. They are still worth a deliberate cleanup pass to prevent warning blindness.
- UI polish backlog remains open for a branded app icon and a custom menu bar icon.

## Session Update (March 6, 2026, previous latest)

This handoff now reflects a final verification pass after the March 6 hardening work.

Completed in this session:
- Re-ran `swift build` and `swift test`; both passed locally, with the full suite still reporting 177 passing tests across 25 suites.
- Expanded GitHub Actions CI to run the full `swift test` suite instead of only `ClawMailCoreTests`, so the app, app-lib, and integration regressions covered in this handoff are enforced in CI as well.

Current build/test status after these fixes:
- `swift build`: passed
- `swift test`: passed
- Test suite reported 177 passing tests across 25 suites

New tests added in this session:
- None

Key implementation files changed in this session:
- `.github/workflows/ci.yml`
- `docs/code-review-handoff.md`

Next issue to start with:
- No confirmed findings remain from the March 6 review handoff or the final verification pass.

## Session Update (March 6, 2026, previous latest)

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
