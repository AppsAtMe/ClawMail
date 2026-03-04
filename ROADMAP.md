# ClawMail Roadmap

Tracks unimplemented features, known limitations, and planned improvements. Items are ordered roughly by priority within each section.

## Security Hardening

- [ ] **OAuth2 full implementation** — Complete the OAuth2 flow in `OAuthFlowView.swift` with state parameter validation (CSRF prevention), local HTTP callback listener, and token exchange. See security comments in the file.
- [ ] **IPC peer credential verification** — In addition to the token handshake, verify the connecting process via `SO_PEERCRED` / `LOCAL_PEERPID` to ensure only expected executables (CLI, MCP) connect.
- [ ] **Socket file permissions** — Explicitly `chmod 0700` the `~/Library/Application Support/ClawMail/` directory on startup to ensure only the owning user can access the socket and token files.
- [ ] **REST API rate limiting on reads** — Add HTTP-level rate limiting middleware to prevent abuse of list/search endpoints (separate from the email send rate limiter in GuardrailEngine).

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
