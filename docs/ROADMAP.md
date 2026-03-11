# ClawMail Roadmap

Tracks unimplemented features, known limitations, and planned improvements. Items are ordered roughly by priority within each section.

## Security Hardening

- [x] **OAuth2 full implementation** — Local HTTP callback server (`OAuthCallbackServer`), cryptographic `state` parameter with constant-time validation (CSRF prevention per RFC 6749 §10.12), browser-based authorization, token exchange, Keychain storage. See `OAuthFlowView.swift` and `OAuthCallbackServer.swift`.
- [x] **IPC peer credential verification** — `LOCAL_PEERPID` verification in `IPCServerHandler.channelActive` checks the connecting process via `proc_pidpath`. Fail-open design (token auth is primary). See `IPCServer.swift`.
- [x] **Socket file permissions** — `chmod 0700` on `~/Library/Application Support/ClawMail/` at `IPCServer.start()`. Token file is `0600`.
- [x] **REST API rate limiting on reads** — Token bucket rate limiter (`RateLimitMiddleware`) with 120 req/min capacity and continuous refill. Runs before auth middleware to prevent brute-force key guessing. See `RateLimitMiddleware.swift`.
- [ ] **OAuth2 client ID configuration** — `OAuthClientConfig` placeholders need real client IDs from Google Cloud Console and Azure AD. Currently empty strings.

## Features (Deferred from Spec)

These are explicitly listed in SPECIFICATION.md as "Future Considerations":

- [ ] Multi-agent support (simultaneous connections with workspace isolation)
- [ ] Email threading / conversation view
- [ ] Email templates for agents
- [ ] Rich text (HTML) email composition
- [ ] S/MIME or PGP encryption/signing
- [ ] Email rules / filters
- [ ] HTTP-based MCP transport (remote agent connections)
- [ ] Draft management
- [ ] Cross-platform (Windows / Linux)
- [ ] Auto-responder
- [ ] Provider-specific APIs (native Gmail API / Microsoft Graph)

## Quality / Testing

- [x] **Build warning cleanup** — The Swift 6/NIO `Sendable` warning burst in `OAuthCallbackServer`, IMAP/SMTP, and IPC has been resolved by moving pipeline setup onto NIO's event-loop `syncOperations`, so release builds are quiet again.
- [ ] **Integration test coverage** — Expand integration tests to cover CalDAV, CardDAV, and full search pipeline against Docker test servers.
- [x] **Security-focused test suite** — Unit and regression coverage exists for CRLF injection prevention, path traversal validation, FTS5 sanitization, DAV same-origin / HTTPS enforcement, and IPC handshake behavior.
- [x] **Settings failure-state coverage** — App tests cover both rendered and interaction-driven failure alerts for the API, Activity Log, General, and Guardrails settings flows.
- [x] **CI pipeline** — GitHub Actions workflow builds and runs the full `swift test` suite on macOS runners.

## UX / Polish

- [x] **Account editing polish** — Edit mode now surfaces an explicit existing-account banner, waits for saved Keychain credentials before reusing them, and keeps connection-test retry/back controls reachable with scrollable failure results.
- [ ] **Welcome / onboarding screen** — Add a polished first-run "Welcome to ClawMail" flow that explains what the menu bar app does, guides provider selection, and frames the next setup step before dropping users into settings.
- [ ] **Branded app icon** — Add a polished ClawMail app icon asset instead of relying on the current placeholder/default bundle presentation.
- [ ] **Custom menu bar icon** — Replace the temporary SF Symbol-based status icon with a purpose-designed monochrome menu bar glyph that reads clearly at small sizes.
- [x] **Quit feedback / confirmation affordance** — The menu bar quit action now switches into an explicit `Quitting...` loading state while the terminate/fallback path runs so the exit feels intentional and responsive.
- [ ] **Event-driven UI refresh** — Replace timer-based menu/activity polling with Darwin Notifications or another push mechanism so status and audit updates appear immediately across processes.
- [x] **First-launch discoverability** — Empty-account startup now opens Settings automatically and surfaces the add-account flow so new users are not stranded in a menu bar-only app.
