import Testing
import Foundation
@testable import ClawMailCore

/// Diagnostic test for SMTP auth against a real server (e.g. Gmail).
/// Run with environment variables:
///
///   SMTP_USER=you@gmail.com SMTP_PASS=yourapppassword swift test --filter testSMTPAuthDiagnostic
///
/// Optional env vars (defaults to Gmail SSL on port 465):
///   SMTP_HOST=smtp.gmail.com  SMTP_PORT=465  SMTP_SECURITY=ssl|starttls
@Suite(.serialized)
struct SMTPDiagnosticTests {

    @Test func testSMTPAuthDiagnostic() async throws {
        guard let user = ProcessInfo.processInfo.environment["SMTP_USER"],
              let pass = ProcessInfo.processInfo.environment["SMTP_PASS"] else {
            print("[SMTP DIAG] Skipped — set SMTP_USER and SMTP_PASS env vars to run")
            return
        }

        let host = ProcessInfo.processInfo.environment["SMTP_HOST"] ?? "smtp.gmail.com"
        let port = Int(ProcessInfo.processInfo.environment["SMTP_PORT"] ?? "465") ?? 465
        let secStr = ProcessInfo.processInfo.environment["SMTP_SECURITY"] ?? "ssl"
        let security: ConnectionSecurity = secStr == "starttls" ? .starttls : .ssl

        print("[SMTP DIAG] Connecting to \(host):\(port) (\(secStr))")
        print("[SMTP DIAG] User: \(user)")
        print("[SMTP DIAG] Pass: \(String(repeating: "*", count: pass.count)) (\(pass.count) chars)")

        let client = SMTPClient(
            host: host,
            port: port,
            security: security,
            credentials: .password(pass),
            senderEmail: user
        )

        do {
            try await client.connect()
            print("[SMTP DIAG] SUCCESS — authenticated to \(host)")
            try await client.disconnect()
            print("[SMTP DIAG] Disconnected cleanly")
        } catch let error as ClawMailError {
            print("[SMTP DIAG] ClawMailError: \(error.message)")
            print("[SMTP DIAG] Error code: \(error.code)")
            throw error
        } catch {
            print("[SMTP DIAG] Raw error type: \(type(of: error))")
            print("[SMTP DIAG] String(describing:): \(String(describing: error))")
            print("[SMTP DIAG] localizedDescription: \(error.localizedDescription)")
            throw error
        }
    }
}
