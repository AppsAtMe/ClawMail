# ClawMail Account Setup Guide

**Setup and troubleshooting for email providers**

---

## Quick Setup (Happy Path)

### Google (Gmail)
1. Choose **Google** provider
2. Click **Open Browser**
3. Sign in to your Google account
4. Grant ClawMail permission to access email
5. Done — ClawMail auto-configures Gmail, Calendar, and Contacts

### Microsoft 365 / Outlook
1. Choose **Microsoft 365 / Outlook** provider
2. Click **Open Browser**
3. Sign in to your Microsoft account
4. Grant permissions
5. Done — Mail is preconfigured; CalDAV/CardDAV auto-discovered if available

### Apple / iCloud
1. Choose **Apple / iCloud** provider
2. Enter your **iCloud email address**
3. Create an [app-specific password](https://support.apple.com/121539)
4. Enter the app-specific password in ClawMail
5. Done — iCloud Mail, Calendar, Contacts, and Reminders configured

### Fastmail
1. Choose **Fastmail** provider
2. Enter your **Fastmail email address**
3. Create a [Fastmail app password](https://www.fastmail.help/hc/en-us/articles/360058752854)
4. Enter the app password in ClawMail
5. Done — Mail, Calendar, and Contacts auto-configured

---

## Other Mail Account (IMAP/SMTP)

For email providers not listed above, you'll need to enter server details manually.

### What You'll Need

| Setting | What to Enter | Common Values |
|---------|---------------|---------------|
| **Email Address** | Your full email address | `you@example.com` |
| **Password** | Email password or app password | (varies) |
| **Sender Name** | Name shown to recipients | `Your Name` |
| **IMAP Server** | Incoming mail server | `imap.example.com` |
| **IMAP Port** | Incoming server port | `993` (SSL) or `143` |
| **IMAP Security** | Encryption method | SSL or STARTTLS |
| **SMTP Server** | Outgoing mail server | `smtp.example.com` |
| **SMTP Port** | Outgoing server port | `465` (SSL) or `587` |
| **SMTP Security** | Encryption method | SSL or STARTTLS |

### Finding Your Server Settings

#### Generic Instructions
1. Check your email provider's documentation for "IMAP settings" or "email client setup"
2. Look for a "Configure email client" or "Mail app settings" page
3. Contact your provider's support if settings aren't documented

#### Common Provider Patterns

| Provider Type | IMAP Server | SMTP Server |
|---------------|-------------|-------------|
| **Custom domain (cPanel/Plesk)** | `mail.yourdomain.com` | `mail.yourdomain.com` |
| **Namecheap** | `mail.privateemail.com` | `mail.privateemail.com` |
| **GoDaddy** | `imap.secureserver.net` | `smtpout.secureserver.net` |
| **Yahoo Mail** | `imap.mail.yahoo.com` | `smtp.mail.yahoo.com` |
| **Zoho Mail** | `imap.zoho.com` | `smtp.zoho.com` |
| **Proton Mail** | Requires Proton Mail Bridge | (use Bridge) |

### Security Best Practices

#### Use App-Specific Passwords
Many providers require app-specific passwords instead of your main password:

- **Yahoo Mail:** Generate in Account Security → Generate app password
- **Zoho Mail:** Use application-specific passwords in security settings
- **Custom hosts:** Check if your host supports app passwords

#### Password Security
- **Never** use your main account password if app passwords are available
- Store passwords securely (ClawMail uses macOS Keychain)
- Rotate passwords periodically

### Optional: Calendar & Contacts (DAV)

For calendar and contacts sync, add CalDAV and CardDAV URLs:

| Service | CalDAV URL | CardDAV URL |
|---------|------------|-------------|
| **Nextcloud** | `https://cloud.example.com/remote.php/dav/calendars/user/` | `https://cloud.example.com/remote.php/dav/addressbooks/user/` |
| **Owncloud** | Similar to Nextcloud | Similar to Nextcloud |
| **Generic** | Check provider documentation | Check provider documentation |

Leave these blank if you only need email.

---

## Troubleshooting

### Connection Failed

**Symptom:** "Could not connect to server" error

**Solutions:**
1. **Check server names** — Ensure no typos in IMAP/SMTP hostnames
2. **Verify ports** — Common: IMAP 993, SMTP 465 or 587
3. **Try different security** — Some servers need SSL vs STARTTLS
4. **Check firewall** — Ensure ClawMail can access the internet
5. **Test with another client** — Verify settings work in Apple Mail/Thunderbird

### Authentication Failed

**Symptom:** "Login failed" or "Invalid credentials"

**Solutions:**
1. **Use app-specific password** — Most providers require this
2. **Check email address format** — Some servers need full address, others just username
3. **Verify account status** — Ensure account isn't locked or disabled
4. **Enable "less secure apps"** — Some older providers need this (not recommended)

### SSL/TLS Errors

**Symptom:** Certificate or encryption errors

**Solutions:**
1. **Check security setting** — Try SSL vs STARTTLS
2. **Verify port matches security** — SSL usually 993/465, STARTTLS 143/587
3. **Update macOS** — Ensure root certificates are current

### OAuth Issues (Google/Microsoft)

**Symptom:** Browser sign-in fails or loops

**Solutions:**
1. **Check default browser** — Ensure a compatible browser is default
2. **Clear browser cookies** — Try signing in with fresh session
3. **Check redirect URI** — Verify the redirect matches ClawMail's registered URI
4. **Review permissions** — Ensure you clicked "Allow" for all requested scopes

### Can't Send Mail

**Symptom:** IMAP works, but SMTP fails

**Solutions:**
1. **Different SMTP credentials** — Some providers use different login for SMTP
2. **Check SMTP port** — Try 587 with STARTTLS if 465 fails
3. **Verify outgoing server** — SMTP host may differ from IMAP host
4. **Check sending limits** — Some providers throttle new apps

### Calendar/Contacts Not Syncing

**Symptom:** Email works, but DAV services don't

**Solutions:**
1. **Verify DAV URLs** — Check with provider for correct CalDAV/CardDAV endpoints
2. **Use .well-known discovery** — Many servers auto-discover at root domain
3. **Check Fastmail specifically** — Fastmail DAV uses `.well-known` redirects
4. **Test with Apple Calendar** — Verify DAV works outside ClawMail

---

## Provider-Specific Notes

### Yahoo Mail
- Requires app-specific password
- Enable "Allow apps that use less secure sign in" in security settings
- May need to verify via SMS/email when adding new app

### Proton Mail
- **Does not support direct IMAP** — requires Proton Mail Bridge
- Install Bridge, then use `localhost` IMAP/SMTP settings from Bridge

### Zoho Mail
- Supports app-specific passwords
- Free tier may have IMAP restrictions
- Check Zoho Mail control panel for correct server settings

### Self-Hosted / Custom Domain
- Settings vary by hosting provider
- Common: cPanel, Plesk, Virtualmin each have different defaults
- Contact your hosting support for correct settings

### Work/School Accounts
- May have additional security (MFA, conditional access)
- Contact IT department for approved app settings
- May require admin consent for OAuth apps

---

## Still Stuck?

1. **Check the [README](README.md)** for general setup instructions
2. **Open an issue** on GitHub with:
   - Provider name
   - Error message (exact text)
   - Steps you've tried
3. **Join [Discord](https://discord.gg/clawmail)** for community help

---

*Last updated: March 2026*
