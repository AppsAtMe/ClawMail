# ClawMail Account Verification Checklist

Manual verification checklist for real-world account setup in the macOS app.

## Recommended Run Order

| Account Type | Priority | Focus |
|---|---:|---|
| Apple / iCloud app-specific password | 1 | First-class Apple provider path, server defaults, reconnect |
| Google OAuth2 | 1 | OAuth setup, token use, reconnect |
| Fastmail app password | 1 | Password-based mail + DAV provider defaults |
| Generic IMAP/SMTP + CalDAV/CardDAV | 1 | Manual config, DAV validation, DAV CRUD |
| Microsoft 365 / Outlook OAuth2 | 2 | Second OAuth provider, provider-specific behavior |
| Google app password | 2 | Password auth on a real provider |

## Session Preflight

- [ ] Start stderr log tail in another Terminal tab/window, or background it:
  `: > /tmp/clawmail.stderr.log && tail -n 0 -F /tmp/clawmail.stderr.log &`
- [ ] Launch `/Applications/ClawMail.app`
- [ ] If testing OAuth, first create a Google Desktop app OAuth client and a Microsoft Entra app registration, then paste their client IDs in `Settings > API`
- [ ] If testing Google OAuth with a personal Gmail account, make sure the Google Auth platform `Audience` / user type is `External`
- [ ] If testing Google OAuth in `Testing` mode, add the Google account being used as an OAuth consent-screen test user
- [ ] If testing Google OAuth, make sure Google Auth platform `Data Access` includes the Gmail scope, Calendar scope, and Google CardDAV scope `https://www.googleapis.com/auth/carddav`
- [ ] If testing Google Calendar, enable `CalDAV API` (`caldav.googleapis.com`) in the same Cloud project before signing in
- [ ] Pick one known-safe recipient
- [ ] Pick one brand-new recipient for held-send approval testing
- [ ] If possible, have one DAV-capable account ready for calendar, contacts, and tasks checks

## Core Setup Flow

Run this for each account type:

- [ ] Open `Settings > Accounts > +`
- [ ] Verify the provider path is correct:
  `Apple / iCloud` should prefill Apple's mail servers and use password-based setup
  `Google` and `Microsoft 365 / Outlook` should drive the OAuth flow
  `Fastmail` should prefill Fastmail's mail and DAV services and stay on the password/app-password path
  `Other Mail Account` should require manual server entry
- [ ] Verify required fields block progress when empty
- [ ] For OAuth providers, verify the typed email acts only as a login hint and that ClawMail replaces it with the authorized address returned by browser sign-in
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
  No password entry should be needed after browser consent. The email field should act only as a login hint until Google sign-in finishes, then ClawMail should replace it with the authorized Google address Google returned. Google Contacts should use the built-in CardDAV discovery URL, and the primary CalDAV URL should derive from that authorized email address. If Google shows `Error 403: access_denied`, verify the client is a Desktop app, the Google Auth platform `Audience` / user type is `External` for personal Gmail testing, the account is a listed test user while the consent screen is in Testing, and Google Auth platform `Data Access` includes the Gmail, Calendar, and Google CardDAV scope `https://www.googleapis.com/auth/carddav` ClawMail requests. If browser consent succeeds but ClawMail reports `client_secret is missing`, paste the Google Client Secret from that same OAuth client or recreate the client as a Desktop app and try again. If Gmail mail works but CalDAV still returns HTTP `403`, enable `CalDAV API` (`caldav.googleapis.com`) in that same Cloud project. If Gmail mail works but CardDAV still returns HTTP `403`, capture the exact CardDAV error plus the OAuth/CardDAV log lines from `/tmp/clawmail.stderr.log` so we can compare what ClawMail requested against what Google granted and what the CardDAV endpoint challenged for. If ClawMail reports `insufficient authentication scopes`, go Back and re-run browser sign-in after adjusting Google `Data Access`; `Retry Test` alone will reuse the same token.
- Fastmail app password:
  Setup should use a Fastmail app password and prefill `imap.fastmail.com:993`, `smtp.fastmail.com:465`, `https://caldav.fastmail.com`, and `https://carddav.fastmail.com`.
- Google app password:
  App password should work; the normal account password should not.
- Microsoft OAuth2:
  IMAP and SMTP should work; DAV behavior may depend on tenant/provider support and may need manual endpoints.
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
