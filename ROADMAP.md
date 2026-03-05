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

- [ ] **Integration test coverage** — Expand integration tests to cover CalDAV, CardDAV, and full search pipeline against Docker test servers.
- [ ] **Security-focused test suite** — Unit tests for CRLF injection prevention, path traversal validation, FTS5 sanitization, and IPC handshake rejection.
- [ ] **CI pipeline** — GitHub Actions workflow for build + test on macOS runners.
