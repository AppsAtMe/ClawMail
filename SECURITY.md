# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in ClawMail, please report it responsibly.

**Email:** [apps@andrewrmitchell.com](mailto:apps@andrewrmitchell.com)

Please include:
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

## Response Timeline

- **Acknowledgment:** Within 48 hours
- **Initial assessment:** Within 1 week
- **Fix or mitigation:** As soon as practical, depending on severity

## Scope

The following are in scope:
- ClawMail application code (all targets)
- IPC protocol and authentication
- REST API authentication and authorization
- Credential storage and handling
- Input validation (IMAP/SMTP injection, path traversal, etc.)
- Guardrail bypasses

The following are out of scope:
- Vulnerabilities in third-party dependencies (report upstream)
- Issues requiring physical access to the machine
- Social engineering

## Disclosure

We will coordinate disclosure with you. Please do not open a public GitHub issue for security vulnerabilities.
