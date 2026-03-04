import SwiftUI
import ClawMailCore

/// Result of a single connection test.
struct ConnectionTestResult: Identifiable {
    let id = UUID()
    let service: String
    let passed: Bool
    let message: String
}

/// Tests IMAP, SMTP, CalDAV, CardDAV connections sequentially with progress.
struct ConnectionTestView: View {
    @Environment(AppState.self) private var appState

    @Binding var results: [ConnectionTestResult]
    @Binding var inProgress: Bool
    let account: Account
    let password: String

    var body: some View {
        VStack(spacing: 16) {
            Text("Connection Test")
                .font(.title2.bold())

            if results.isEmpty && !inProgress {
                Text("Testing connections to your email servers...")
                    .foregroundStyle(.secondary)
                    .onAppear { runTests() }
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(results) { result in
                    HStack(spacing: 8) {
                        Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(result.passed ? .green : .red)
                        Text(result.service)
                            .font(.headline)
                        Spacer()
                        Text(result.message)
                            .foregroundStyle(.secondary)
                            .font(.caption)
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
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            .cornerRadius(8)
        }
        .padding()
        .onChange(of: inProgress) { _, testing in
            if testing && results.isEmpty {
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
                let credential: IMAPCredential = .password(
                    username: account.emailAddress,
                    password: password
                )
                let client = IMAPClient(
                    host: account.imapHost,
                    port: account.imapPort,
                    security: account.imapSecurity,
                    credential: credential
                )
                try await client.connect()
                await client.disconnect()
            })

            // Test SMTP
            await addResult(service: "SMTP", test: {
                let creds: Credentials = .password(password)
                let client = SMTPClient(
                    host: account.smtpHost,
                    port: account.smtpPort,
                    security: account.smtpSecurity,
                    credentials: creds,
                    senderEmail: account.emailAddress
                )
                try await client.connect()
                try await client.disconnect()
            })

            // Test CalDAV (optional)
            if let caldavURL = account.caldavURL {
                await addResult(service: "CalDAV", test: {
                    let cred: CalDAVCredential = .password(
                        username: account.emailAddress,
                        password: password
                    )
                    let client = CalDAVClient(baseURL: caldavURL, credential: cred)
                    try await client.authenticate()
                })
            }

            // Test CardDAV (optional)
            if let carddavURL = account.carddavURL {
                await addResult(service: "CardDAV", test: {
                    let cred: CardDAVCredential = .password(
                        username: account.emailAddress,
                        password: password
                    )
                    let client = CardDAVClient(baseURL: carddavURL, credential: cred)
                    try await client.authenticate()
                })
            }

            await MainActor.run {
                inProgress = false
            }
        }
    }

    @MainActor
    private func addResult(service: String, test: @escaping @Sendable () async throws -> Void) async {
        do {
            try await test()
            results.append(ConnectionTestResult(service: service, passed: true, message: "Connected"))
        } catch {
            results.append(ConnectionTestResult(service: service, passed: false, message: error.localizedDescription))
        }
    }
}
