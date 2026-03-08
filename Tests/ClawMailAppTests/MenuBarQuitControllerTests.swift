import Testing
@testable import ClawMailApp

@MainActor
@Suite
struct MenuBarQuitControllerTests {

    @Test func beginQuitMarksQuittingImmediatelyAndWaitsBeforeTerminate() async {
        let waitProbe = WaitProbe()
        let terminationProbe = TerminationProbe()
        let controller = MenuBarQuitController(feedbackDelay: .milliseconds(300)) { delay in
            await waitProbe.record(delay: delay)
            await waitProbe.waitForResume()
        }
        let appState = AppState()

        controller.beginQuit(appState: appState) {
            terminationProbe.markTerminated()
        }

        #expect(appState.isQuitting)
        #expect(terminationProbe.count == 0)

        await waitProbe.waitUntilStarted()
        let observedDelay = await waitProbe.observedDelay
        #expect(observedDelay == .milliseconds(300))
        #expect(terminationProbe.count == 0)

        await waitProbe.resume()
        await terminationProbe.waitUntilTerminated()

        #expect(terminationProbe.count == 1)
    }

    @Test func beginQuitIsIdempotent() async {
        let terminationProbe = TerminationProbe()
        let controller = MenuBarQuitController(feedbackDelay: .zero) { _ in }
        let appState = AppState()

        controller.beginQuit(appState: appState) {
            terminationProbe.markTerminated()
        }
        controller.beginQuit(appState: appState) {
            terminationProbe.markTerminated()
        }

        await terminationProbe.waitUntilTerminated()
        try? await Task.sleep(for: .milliseconds(20))

        #expect(appState.isQuitting)
        #expect(terminationProbe.count == 1)
    }
}

private actor WaitProbe {
    private var storedDelay: Duration?
    private var started = false
    private var startedContinuation: CheckedContinuation<Void, Never>?
    private var continuation: CheckedContinuation<Void, Never>?

    var observedDelay: Duration? {
        get { storedDelay }
    }

    func record(delay: Duration) {
        storedDelay = delay
        started = true
        startedContinuation?.resume()
        startedContinuation = nil
    }

    func waitUntilStarted() async {
        guard !started else { return }
        await withCheckedContinuation { continuation in
            startedContinuation = continuation
        }
    }

    func waitForResume() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

@MainActor
private final class TerminationProbe {
    var count = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func markTerminated() {
        count += 1
        continuation?.resume()
        continuation = nil
    }

    func waitUntilTerminated() async {
        guard count == 0 else { return }
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }
}
