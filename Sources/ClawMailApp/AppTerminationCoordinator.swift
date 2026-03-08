import Foundation

@MainActor
final class AppTerminationCoordinator {
    private var fallbackScheduled = false

    func beginTermination(appState: AppState, scheduleFallback: () -> Void) {
        appState.isQuitting = true

        guard !fallbackScheduled else { return }
        fallbackScheduled = true
        scheduleFallback()
    }
}
