import SwiftUI
import ClawMailCore

/// Result of a single connection test.
struct ConnectionTestResult: Identifiable {
    let id = UUID()
    let service: String
    let passed: Bool
    let message: String
    let recoverySuggestion: RecoverySuggestion?
}

struct RecoverySuggestion {
    let text: String
    let linkTitle: String?
    let linkURL: URL?
}

/// Ensures a continuation is resumed exactly once from concurrent tasks.
private final class OnceGate: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Tests IMAP, SMTP, CalDAV, CardDAV connections sequentially with progress.
struct ConnectionTestView: View {
    @Environment(AppState.self) private var appState

    @Binding var results: [ConnectionTestResult]
    @Binding var inProgress: Bool
    let account: Account
    let authMaterial: ConnectionTestAuthMaterial

    private let timeoutSeconds = 15
    private let googleCalendarScope = "https://www.googleapis.com/auth/calendar"
    private let googleCardDAVScope = "https://www.google.com/m8/feeds"
    private let googleModernContactsScope = "https://www.googleapis.com/auth/contacts"

    var body: some View {
        VStack(spacing: 16) {
            VStack(spacing: 6) {
                Text("Connection Test")
                    .font(.title2.bold())

                if !results.isEmpty, !results.allSatisfy(\.passed) {
                    Text("Review the failures below, then use Back to adjust settings or Retry to run the checks again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundStyle(result.passed ? .green : .red)
                                    .padding(.top, 1)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.service)
                                        .font(.headline)
                                    Text(result.message)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .textSelection(.enabled)
                                    if let recoverySuggestion = result.recoverySuggestion {
                                        Text(recoverySuggestion.text)
                                            .font(.caption)
                                            .foregroundStyle(.primary)
                                            .fixedSize(horizontal: false, vertical: true)
                                            .textSelection(.enabled)
                                        if let linkURL = recoverySuggestion.linkURL {
                                            Link(recoverySuggestion.linkTitle ?? linkURL.absoluteString, destination: linkURL)
                                                .font(.caption)
                                        }
                                    }
                                }
                                Spacer(minLength: 12)
                                Text(result.passed ? "Connected" : "Failed")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(result.passed ? .green : .red)
                            }

                            if result.id != results.last?.id {
                                Divider()
                            }
                        }
                    }

                    if inProgress {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Testing...")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .task(id: results.isEmpty) {
            if results.isEmpty && !inProgress {
                runTests()
            }
        }
    }

    private func runTests() {
        inProgress = true
        results = []

        Task {
            // Test IMAP
            await addResult(service: "IMAP", test: {
                let client = IMAPClient(
                    host: account.imapHost,
                    port: account.imapPort,
                    security: account.imapSecurity,
                    credential: authMaterial.imapCredential(email: account.emailAddress)
                )
                try await client.connect()
                try await client.authenticate()
                await client.disconnect()
            })

            // Test SMTP
            await addResult(service: "SMTP", test: {
                let client = SMTPClient(
                    host: account.smtpHost,
                    port: account.smtpPort,
                    security: account.smtpSecurity,
                    credentials: authMaterial.smtpCredentials(),
                    senderEmail: account.emailAddress
                )
                try await client.connect()
                try await client.disconnect()
            })

            // Test CalDAV (optional)
            if let caldavURL = account.caldavURL {
                if let scopeFailure = googleOAuthScopeFailureResult(for: "CalDAV") {
                    await MainActor.run {
                        results.append(scopeFailure)
                    }
                } else {
                    await addResult(service: "CalDAV", test: {
                        let client = try CalDAVClient(
                            baseURL: caldavURL,
                            credential: authMaterial.calDAVCredential(email: account.emailAddress)
                        )
                        try await client.authenticate()
                    })
                }
            }

            // Test CardDAV (optional)
            if let carddavURL = account.carddavURL {
                if let scopeFailure = googleOAuthScopeFailureResult(for: "CardDAV") {
                    await MainActor.run {
                        results.append(scopeFailure)
                    }
                } else {
                    await addResult(service: "CardDAV", test: {
                        let client = try CardDAVClient(
                            baseURL: carddavURL,
                            credential: authMaterial.cardDAVCredential(email: account.emailAddress)
                        )
                        try await client.authenticate()
                    })
                }
            }

            await MainActor.run {
                inProgress = false
            }
        }
    }

    /// Run a test with a timeout. Uses unstructured Tasks + a once-gate so the
    /// timeout actually fires even if the NIO connection is stuck (NIO futures
    /// don't respond to Swift Task cancellation).
    @MainActor
    private func addResult(service: String, test: @escaping @Sendable () async throws -> Void) async {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            let gate = OnceGate()
            let timeoutWorkItem = DispatchWorkItem {
                Task { @MainActor in
                    if gate.claim() {
                        continuation.resume(returning: .failure(
                            ClawMailError.connectionError("Connection timed out after \(timeoutSeconds) seconds")
                        ))
                    }
                }
            }

            // Operation task (unstructured — won't block the continuation)
            Task {
                do {
                    try await test()
                    await MainActor.run {
                        if gate.claim() {
                            timeoutWorkItem.cancel()
                            continuation.resume(returning: .success(()))
                        }
                    }
                } catch {
                    await MainActor.run {
                        if gate.claim() {
                            timeoutWorkItem.cancel()
                            continuation.resume(returning: .failure(error))
                        }
                    }
                }
            }

            // Timeout watchdog stays outside Swift concurrency because stuck NIO work
            // does not always react cleanly to task cancellation.
            DispatchQueue.global(qos: .userInitiated).asyncAfter(
                deadline: .now() + .seconds(timeoutSeconds),
                execute: timeoutWorkItem
            )
        }

        switch result {
        case .success:
            results.append(ConnectionTestResult(
                service: service,
                passed: true,
                message: "Connected",
                recoverySuggestion: nil
            ))
        case .failure(let error):
            // Use String(describing:) — localizedDescription goes through Foundation
            // which can produce generic "error N" messages for non-NSError types.
            let message: String
            if let claw = error as? ClawMailError {
                message = claw.message
            } else {
                message = String(describing: error)
            }
            results.append(ConnectionTestResult(
                service: service,
                passed: false,
                message: message,
                recoverySuggestion: recoverySuggestion(for: service, error: error, message: message)
            ))
        }
    }

    private func recoverySuggestion(for service: String, error: Error, message: String) -> RecoverySuggestion? {
        let normalized = message.lowercased()
        let provider = inferredProvider

        if isAuthFailure(error: error, normalizedMessage: normalized) {
            switch provider {
            case .appleICloud:
                return RecoverySuggestion(
                    text: "Try this: use an Apple Account app-specific password instead of your normal sign-in password.",
                    linkTitle: "Open Apple instructions",
                    linkURL: URL(string: "https://support.apple.com/121539")
                )
            case .google:
                if case .oauth2 = account.authMethod {
                    if normalized.contains("insufficient authentication scopes") {
                        if service == "CalDAV" {
                            return RecoverySuggestion(
                                text: preciseGoogleScopeRecoveryText(
                                    serviceLabel: "Calendar",
                                    requiredScope: googleCalendarScope
                                ),
                                linkTitle: "Open Google OAuth consent screen instructions",
                                linkURL: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")
                            )
                        }
                        if service == "CardDAV" {
                            return RecoverySuggestion(
                                text: preciseGoogleScopeRecoveryText(
                                    serviceLabel: "Contacts",
                                    requiredScope: googleCardDAVScope
                                ),
                                linkTitle: "Open Google OAuth consent screen instructions",
                                linkURL: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")
                            )
                        }
                    }
                    if normalized.contains("did not grant calendar access") {
                        return RecoverySuggestion(
                            text: "Try this: retry Google browser sign-in and make sure Calendar access is granted on the consent screen. In Google Cloud Console, Google Auth platform > Data Access should also list the Calendar scope for this app.",
                            linkTitle: "Open Google OAuth consent screen instructions",
                            linkURL: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")
                        )
                    }
                    if normalized.contains("did not grant contacts access") {
                        return RecoverySuggestion(
                            text: "Try this: retry Google browser sign-in and make sure Contacts access is granted on the consent screen. In Google Cloud Console, Google Auth platform > Data Access should also list Google's legacy CardDAV contacts scope `\(googleCardDAVScope)` for this app.",
                            linkTitle: "Open Google OAuth consent screen instructions",
                            linkURL: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")
                        )
                    }
                    if service == "CalDAV" {
                        return RecoverySuggestion(
                            text: "Try this: Gmail mail OAuth is working, but Google Calendar DAV is still returning 403. Confirm `CalDAV API` (`caldav.googleapis.com`) is enabled in this same Google Cloud project, and retry browser sign-in if Calendar access was not granted on the consent screen.",
                            linkTitle: "Open CalDAV API in Google Cloud Console",
                            linkURL: URL(string: "https://console.cloud.google.com/apis/library/caldav.googleapis.com")
                        )
                    }
                    if service == "CardDAV" {
                        return RecoverySuggestion(
                            text: "Try this: Gmail mail OAuth is working, but Google Contacts DAV is still returning 403. Google CardDAV expects the legacy Google Contacts scope `\(googleCardDAVScope)`. Re-run Google browser sign-in on the latest build so ClawMail can request that scope, then confirm Google Auth platform > Data Access includes it for this app.",
                            linkTitle: "Open Google OAuth consent screen instructions",
                            linkURL: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")
                        )
                    }
                    return RecoverySuggestion(
                        text: "Try this: confirm the Google OAuth client ID and secret in Settings > API, then sign in again so ClawMail gets fresh browser tokens.",
                        linkTitle: nil,
                        linkURL: nil
                    )
                }
                return RecoverySuggestion(
                    text: "Try this: Gmail rejects normal account passwords here. Use an app password or switch to the Google browser sign-in option.",
                    linkTitle: nil,
                    linkURL: nil
                )
            case .microsoft:
                if case .oauth2 = account.authMethod {
                    return RecoverySuggestion(
                        text: "Try this: confirm the Microsoft OAuth client ID and secret in Settings > API and make sure the app has Outlook IMAP and SMTP delegated permissions.",
                        linkTitle: nil,
                        linkURL: nil
                    )
                }
                return RecoverySuggestion(
                    text: "Try this: for Microsoft 365 / Outlook, prefer the browser sign-in option. If you are testing password auth, confirm the tenant still allows it.",
                    linkTitle: nil,
                    linkURL: nil
                )
            case .fastmail:
                return RecoverySuggestion(
                    text: "Try this: use a Fastmail app password instead of your account password for third-party mail, calendar, and contacts access.",
                    linkTitle: "Open Fastmail instructions",
                    linkURL: URL(string: "https://www.fastmail.help/hc/en-us/articles/360058752854")
                )
            case .none:
                return RecoverySuggestion(
                    text: "Try this: double-check the username, password, and server settings, then retry the connection test.",
                    linkTitle: nil,
                    linkURL: nil
                )
            }
        }

        if normalized.contains("timed out") || normalized.contains("not connected") {
            return RecoverySuggestion(
                text: "Try this: verify the server host, port, and security settings, and confirm the server is reachable from this Mac.",
                linkTitle: nil,
                linkURL: nil
            )
        }

        if service == "SMTP", normalized.contains("starttls") {
            return RecoverySuggestion(
                text: "Try this: confirm the outgoing server supports the selected security mode and port.",
                linkTitle: nil,
                linkURL: nil
            )
        }

        return nil
    }

    private func preciseGoogleScopeRecoveryText(serviceLabel: String, requiredScope: String) -> String {
        let diagnostic: String
        if let grantedScopes = authMaterial.grantedGoogleScopes(), !grantedScopes.isEmpty {
            let formattedScopes = grantedScopes.sorted().joined(separator: ", ")
            if authMaterial.grantsGoogleScope(requiredScope) == true {
                diagnostic = "ClawMail saw Google grant `\(requiredScope)`. If Google still says the token has insufficient scopes, stop here and send this result back because ClawMail may need a Google-specific scope adjustment for \(serviceLabel.lowercased()) access. Granted scopes: \(formattedScopes)."
            } else if requiredScope == googleCardDAVScope,
                      authMaterial.grantsGoogleScope(googleModernContactsScope) == true {
                diagnostic = "ClawMail saw Google grant the newer Contacts scope `\(googleModernContactsScope)`, but Google CardDAV still rejected the token. That strongly suggests this Google CardDAV flow needs the legacy Contacts scope `\(googleCardDAVScope)` instead. Granted scopes: \(formattedScopes)."
            } else {
                diagnostic = "ClawMail did not receive the required Google scope `\(requiredScope)`. Granted scopes were: \(formattedScopes)."
            }
        } else {
            diagnostic = "ClawMail could not confirm the granted Google scopes from the token response, so the safest next step is to re-run browser sign-in after checking Google Auth platform > Data Access."
        }

        return "Try this: go Back and run Google browser sign-in again after confirming Google Auth platform > Data Access includes the \(serviceLabel) scope `\(requiredScope)`. Retry Test reuses the same token and will not fix a scope issue by itself. \(diagnostic)"
    }

    private func googleOAuthScopeFailureResult(for service: String) -> ConnectionTestResult? {
        guard case .google? = inferredProvider,
              case .oauth2 = account.authMethod else {
            return nil
        }

        let missingScope: String?
        let missingScopeLabel: String
        switch service {
        case "CalDAV":
            missingScope = authMaterial.grantsGoogleScope(googleCalendarScope) == false ? googleCalendarScope : nil
            missingScopeLabel = "Calendar"
        case "CardDAV":
            missingScope = authMaterial.grantsGoogleScope(googleCardDAVScope) == false ? googleCardDAVScope : nil
            missingScopeLabel = "Contacts"
        default:
            return nil
        }

        guard let missingScope else { return nil }
        let message: String
        if service == "CardDAV", authMaterial.grantsGoogleScope(googleModernContactsScope) == true {
            message = "Authentication failed: Google browser sign-in granted the newer Contacts scope, but not the legacy Google CardDAV contacts scope."
        } else {
            message = "Authentication failed: Google browser sign-in did not grant \(missingScopeLabel) access."
        }
        return ConnectionTestResult(
            service: service,
            passed: false,
            message: message,
            recoverySuggestion: RecoverySuggestion(
                text: "Try this: retry Google browser sign-in and make sure \(missingScopeLabel) access is granted. In Google Cloud Console, Google Auth platform > Data Access should also include `\(missingScope)` for this app.",
                linkTitle: "Open Google OAuth consent screen instructions",
                linkURL: URL(string: "https://developers.google.com/workspace/guides/configure-oauth-consent")
            )
        )
    }

    private var inferredProvider: KnownProvider? {
        switch (account.imapHost.lowercased(), account.smtpHost.lowercased()) {
        case ("imap.mail.me.com", "smtp.mail.me.com"):
            return .appleICloud
        case ("imap.gmail.com", "smtp.gmail.com"):
            return .google
        case ("outlook.office365.com", "smtp.office365.com"):
            return .microsoft
        case ("imap.fastmail.com", "smtp.fastmail.com"):
            return .fastmail
        default:
            return nil
        }
    }

    private func isAuthFailure(error: Error, normalizedMessage: String) -> Bool {
        if case ClawMailError.authFailed = error {
            return true
        }

        return normalizedMessage.contains("authentication failed")
            || normalizedMessage.contains("login failed")
            || normalizedMessage.contains("badcredentials")
            || normalizedMessage.contains("535")
            || normalizedMessage.contains("xoauth2 failed")
    }
}

private enum KnownProvider {
    case appleICloud
    case google
    case microsoft
    case fastmail
}
