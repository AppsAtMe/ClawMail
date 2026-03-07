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

- [ ] **Build warning cleanup** — Eliminate the remaining Swift 6/NIO concurrency warnings in `OAuthCallbackServer`, IMAP/SMTP, and IPC so local builds stay quiet and new warnings stand out.
- [ ] **Integration test coverage** — Expand integration tests to cover CalDAV, CardDAV, and full search pipeline against Docker test servers.
- [x] **Security-focused test suite** — Unit and regression coverage exists for CRLF injection prevention, path traversal validation, FTS5 sanitization, DAV same-origin / HTTPS enforcement, and IPC handshake behavior.
- [x] **Settings failure-state coverage** — App tests cover both rendered and interaction-driven failure alerts for the API, Activity Log, General, and Guardrails settings flows.
- [x] **CI pipeline** — GitHub Actions workflow builds and runs the full `swift test` suite on macOS runners.

## UX / Polish

- [ ] **Account editing polish** — Existing-account editing now exists, but the edit flow still needs polish so fields stay obviously prefilled, retries remain reachable when multiple connection tests fail, and setup does not feel like a fresh add flow.
- [ ] **Welcome / onboarding screen** — Add a polished first-run "Welcome to ClawMail" flow that explains what the menu bar app does, guides provider selection, and frames the next setup step before dropping users into settings.
- [ ] **Branded app icon** — Add a polished ClawMail app icon asset instead of relying on the current placeholder/default bundle presentation.
- [ ] **Custom menu bar icon** — Replace the temporary SF Symbol-based status icon with a purpose-designed monochrome menu bar glyph that reads clearly at small sizes.
- [ ] **Quit feedback / confirmation affordance** — Quitting from the menu bar currently pauses and then exits without clear visual feedback. Add either a clearer pressed/loading state or a confirmation affordance so quit feels intentional and responsive.
- [ ] **Event-driven UI refresh** — Replace timer-based menu/activity polling with Darwin Notifications or another push mechanism so status and audit updates appear immediately across processes.
- [x] **First-launch discoverability** — Empty-account startup now opens Settings automatically and surfaces the add-account flow so new users are not stranded in a menu bar-only app.
