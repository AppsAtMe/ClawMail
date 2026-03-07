# ClawMail Account Verification Checklist

Manual verification checklist for real-world account setup in the macOS app.

## Recommended Run Order

| Account Type | Priority | Focus |
|---|---:|---|
| Apple / iCloud app-specific password | 1 | First-class Apple provider path, server defaults, reconnect |
| Google OAuth2 | 1 | OAuth setup, token use, reconnect |
| Generic IMAP/SMTP + CalDAV/CardDAV | 1 | Manual config, DAV validation, DAV CRUD |
| Microsoft 365 / Outlook OAuth2 | 2 | Second OAuth provider, provider-specific behavior |
| Google app password | 2 | Password auth on a real provider |

## Session Preflight

- [ ] Start stderr log tail in another Terminal tab/window, or background it:
  `: > /tmp/clawmail.stderr.log && tail -n 0 -F /tmp/clawmail.stderr.log &`
- [ ] Launch `/Applications/ClawMail.app`
- [ ] If testing OAuth, configure Google and Microsoft OAuth client ID/secret in `Settings > API`
- [ ] Pick one known-safe recipient
- [ ] Pick one brand-new recipient for held-send approval testing
- [ ] If possible, have one DAV-capable account ready for calendar, contacts, and tasks checks

## Core Setup Flow

Run this for each account type:

- [ ] Open `Settings > Accounts > +`
- [ ] Verify the provider path is correct:
  `Apple / iCloud` should prefill Apple's mail servers and use password-based setup
  Google and Microsoft should drive the OAuth flow
  `Other Mail Account` should require manual server entry
- [ ] Verify required fields block progress when empty
- [ ] Verify optional DAV URLs accept valid `https://...` values
- [ ] Verify optional DAV URLs reject invalid or `http://...` values
- [ ] Run the connection test
- [ ] Confirm IMAP result is correct
- [ ] Confirm SMTP result is correct
- [ ] Confirm CalDAV result is correct or intentionally skipped
- [ ] Confirm CardDAV result is correct or intentionally skipped
- [ ] Finish setup and save the account
- [ ] Verify the saved account summary shows the expected auth method and endpoints

## Runtime Smoke

Run after each account is added:

```bash
clawmail status
clawmail email list --account=<label> --folder=INBOX --limit=5
clawmail email search --account=<label> "from:test"
clawmail audit list --account=<label> --limit=20
clawmail email send --account=<label> \
  --to="safe-recipient@example.com" \
  --subject="ClawMail manual test" \
  --body="Smoke test"
```

Checklist:

- [ ] `clawmail status` looks healthy
- [ ] Email list works
- [ ] Email search works
- [ ] Audit log works
- [ ] Test send to the known-safe recipient succeeds
- [ ] Quit and relaunch the app
- [ ] Account reconnects without re-entering credentials

## DAV Checks

Run when CalDAV/CardDAV is configured:

```bash
clawmail calendar list --account=<label> --from=2026-03-01 --to=2026-03-31
clawmail contacts list --account=<label>
clawmail tasks create --account=<label> --task-list=default --title="Manual test task"
```

- [ ] Calendar list works
- [ ] Contacts list works
- [ ] Tasks create works
- [ ] Calendar create, update, and delete work
- [ ] Contact create, update, and delete work
- [ ] Task create, update or complete, and delete work

## Guardrails Regression

Run for at least one account:

- [ ] Enable `first-time recipient approval` in `Settings > Guardrails`
- [ ] Send to a brand-new recipient
- [ ] Confirm the send is held instead of discarded
- [ ] Confirm the held send appears in `Settings > Guardrails`
- [ ] Approve the held send
- [ ] Confirm the message is actually delivered after approval

## Provider Notes

- Apple / iCloud:
  Setup should use an app-specific password, not the normal Apple Account password.
  `imap.mail.me.com:993` with SSL and `smtp.mail.me.com:587` with STARTTLS should be prefilled.
- Google OAuth2:
  No password entry should be needed after browser consent.
- Google app password:
  App password should work; the normal account password should not.
- Microsoft OAuth2:
  IMAP and SMTP should work; DAV behavior may depend on tenant/provider support.
- Generic IMAP/SMTP + DAV:
  This is the best target for manual server entry, HTTPS DAV validation, and CRUD checks.

## Result Template

Copy this block per account:

```md
Account label:
Provider/auth:
Date tested:

Setup
[ ] Provider path correct
[ ] Validation behaved correctly
[ ] Connection test honest by service
[ ] Account saved successfully

Runtime
[ ] Status healthy
[ ] Email list/search works
[ ] Send works
[ ] Relaunch/reconnect works

DAV
[ ] Not applicable or verified

Guardrails
[ ] Not applicable or verified

Notes
- Exact error text:
- Provider limitation vs app bug:
- Anything surprising:
```
