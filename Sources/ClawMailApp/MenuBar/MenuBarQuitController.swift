import Foundation

@MainActor
final class MenuBarQuitController {
    private let feedbackDelay: Duration
    private let wait: @Sendable (Duration) async -> Void
    private var quitScheduled = false

    init(
        feedbackDelay: Duration = .milliseconds(300),
        wait: @escaping @Sendable (Duration) async -> Void = MenuBarQuitController.defaultWait
    ) {
        self.feedbackDelay = feedbackDelay
        self.wait = wait
    }

    func beginQuit(
        appState: AppState,
        terminate: @escaping @MainActor @Sendable () -> Void
    ) {
        guard !quitScheduled, !appState.isQuitting else { return }

        quitScheduled = true
        appState.isQuitting = true

        let feedbackDelay = self.feedbackDelay
        let wait = self.wait
        Task { @MainActor in
            await Task.yield()
            await wait(feedbackDelay)
            terminate()
        }
    }

    private static func defaultWait(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }
}
