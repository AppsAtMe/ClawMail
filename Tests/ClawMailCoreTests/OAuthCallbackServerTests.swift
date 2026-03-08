import Foundation
import Testing
@testable import ClawMailCore

@Suite(.serialized)
struct OAuthCallbackServerTests {

    @Test func successfulCallbackReturnsCodeAndStopsCleanly() async throws {
        let server = OAuthCallbackServer()
        let (_, redirectURI) = try await server.start()

        let waitTask = Task<CallbackOutcome, Never> {
            do {
                let result = try await server.waitForCallback(timeout: .seconds(5))
                return .success(code: result.code, state: result.state)
            } catch {
                return .failure(String(describing: error))
            }
        }

        let callbackURL = try #require(URL(string: "\(redirectURI)?code=auth-code&state=expected-state"))
        let (_, response) = try await URLSession.shared.data(from: callbackURL)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        switch await waitTask.value {
        case .success(let code, let state):
            #expect(code == "auth-code")
            #expect(state == "expected-state")
        case .failure(let error):
            Issue.record("Expected a successful callback result, got \(error)")
        }

        await server.stop()
        await server.stop()
    }

    @Test func providerErrorRedirectFailsImmediately() async throws {
        let server = OAuthCallbackServer()
        let (_, redirectURI) = try await server.start()

        let waitTask = Task<WaitOutcome, Never> {
            do {
                _ = try await server.waitForCallback(timeout: .seconds(5))
                return .success
            } catch let error as ClawMailError {
                return .failure(error.message)
            } catch is CancellationError {
                return .cancelled
            } catch {
                return .failure(String(describing: error))
            }
        }

        let errorURL = try #require(URL(string: "\(redirectURI)?error=access_denied&error_description=testing%20blocked"))
        let (_, response) = try await URLSession.shared.data(from: errorURL)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)

        switch await waitTask.value {
        case .failure(let message):
            #expect(message.contains("access_denied"))
            #expect(message.contains("testing blocked"))
        case .success:
            Issue.record("Expected the callback server to fail immediately on provider error")
        case .cancelled:
            Issue.record("Expected a provider error, not cancellation")
        }

        await server.stop()
    }

    @Test func stopCancelsPendingWaitAndIsIdempotent() async throws {
        let server = OAuthCallbackServer()
        _ = try await server.start()

        let waitTask = Task<WaitOutcome, Never> {
            do {
                _ = try await server.waitForCallback(timeout: .seconds(60))
                return .success
            } catch is CancellationError {
                return .cancelled
            } catch let error as ClawMailError {
                return .failure(error.message)
            } catch {
                return .failure(String(describing: error))
            }
        }

        try? await Task.sleep(for: .milliseconds(50))
        await server.stop()
        await server.stop()

        #expect(await waitTask.value == .cancelled)
    }
}

private enum WaitOutcome: Sendable, Equatable {
    case success
    case failure(String)
    case cancelled
}

private enum CallbackOutcome: Sendable, Equatable {
    case success(code: String, state: String)
    case failure(String)
}
