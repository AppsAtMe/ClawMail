import SwiftUI
import ClawMailCore

/// Result of a single connection test.
struct ConnectionTestResult: Identifiable {
    let id = UUID()
    let service: String
    let passed: Bool
    let message: String
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
    let password: String

    private let timeoutSeconds = 15

    var body: some View {
        VStack(spacing: 16) {
            Text("Connection Test")
                .font(.title2.bold())

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

    /// Run a test with a timeout. Uses unstructured Tasks + a once-gate so the
    /// timeout actually fires even if the NIO connection is stuck (NIO futures
    /// don't respond to Swift Task cancellation).
    @MainActor
    private func addResult(service: String, test: @escaping @Sendable () async throws -> Void) async {
        let result: Result<Void, Error> = await withCheckedContinuation { continuation in
            let gate = OnceGate()

            // Operation task (unstructured — won't block the continuation)
            Task {
                do {
                    try await test()
                    if gate.claim() { continuation.resume(returning: .success(())) }
                } catch {
                    if gate.claim() { continuation.resume(returning: .failure(error)) }
                }
            }

            // Timeout task
            Task {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                if gate.claim() {
                    continuation.resume(returning: .failure(
                        ClawMailError.connectionError("Connection timed out after \(timeoutSeconds) seconds")
                    ))
                }
            }
        }

        switch result {
        case .success:
            results.append(ConnectionTestResult(service: service, passed: true, message: "Connected"))
        case .failure(let error):
            // Use String(describing:) — localizedDescription goes through Foundation
            // which can produce generic "error N" messages for non-NSError types.
            let message: String
            if let claw = error as? ClawMailError {
                message = claw.message
            } else {
                message = String(describing: error)
            }
            results.append(ConnectionTestResult(service: service, passed: false, message: message))
        }
    }
}
