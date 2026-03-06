# ClawMail Operations Reference

Operational notes for the local app runtime, agent interfaces, and approval workflow.

## Service Startup

On launch, `ClawMailApp`:

1. Loads `config.json`
2. Opens the metadata database
3. Starts `AccountOrchestrator` and account sync
4. Starts the IPC server and writes the IPC token file
5. Configures webhook forwarding if `webhookURL` is set
6. Requests local notification permission for held-send alerts
7. Ensures a REST API key exists in Keychain
8. Starts the REST API server

If startup fails, the app stays in a non-running state and surfaces the launch error in the menu bar UI.

## Service Shutdown

On termination, the app stops services in this order:

1. REST API server
2. IPC server
3. Account orchestrator

IPC shutdown is best-effort but no longer silent: unexpected socket, token-file, or event-loop cleanup failures are logged to stderr. Startup also removes stale IPC socket files before binding.

## Agent Session Model

- One long-lived IPC agent session is allowed at a time.
- `ClawMailMCP` uses the exclusive agent session type.
- CLI IPC sessions are concurrent and do not acquire the agent lock.
- REST requests run through the in-process API server and do not use the exclusive IPC agent session.

This means a connected MCP client blocks other MCP/agent sessions, but not one-off CLI commands or REST API calls.

## Pending Approval Workflow

When first-time recipient approval is enabled and an outbound message targets a new recipient:

1. The send is persisted in `pending_approvals`
2. The original request is held instead of discarded
3. The app posts a macOS local notification when possible
4. The held request is visible in Settings > Guardrails, CLI, REST, and MCP
5. Approval or rejection can happen explicitly by request ID

Held sends are retried automatically after approval, when the relevant account reconnects, and when first-time recipient approval is later disabled.

## Local Files And Logs

| Item | Path |
|------|------|
| Config | `~/Library/Application Support/ClawMail/config.json` |
| Database | `~/Library/Application Support/ClawMail/metadata.sqlite` |
| IPC socket | `~/Library/Application Support/ClawMail/clawmail.sock` |
| IPC token | `~/Library/Application Support/ClawMail/ipc.token` |
| LaunchAgent | `~/Library/LaunchAgents/com.clawmail.agent.plist` |
| LaunchAgent stdout | `/tmp/clawmail.stdout.log` |
| LaunchAgent stderr | `/tmp/clawmail.stderr.log` |

Credentials, OAuth tokens, and the REST API key remain in the macOS Keychain under the `com.clawmail` service.

## Launch At Login

Launch at login installs `~/Library/LaunchAgents/com.clawmail.agent.plist`, which starts the app executable directly:

`/Applications/ClawMail.app/Contents/MacOS/ClawMailApp`

The menu bar UI can also install or uninstall the LaunchAgent at runtime. Failures in that update path surface as UI errors instead of being silently ignored.
