import Testing
@testable import ClawMailApp

@MainActor
@Suite
struct AppTerminationCoordinatorTests {

    @Test func beginTerminationMarksAppStateAsQuittingAndSchedulesFallbackOnce() {
        let coordinator = AppTerminationCoordinator()
        let appState = AppState()
        var scheduleCount = 0

        coordinator.beginTermination(appState: appState) {
            scheduleCount += 1
        }
        coordinator.beginTermination(appState: appState) {
            scheduleCount += 1
        }

        #expect(appState.isQuitting)
        #expect(scheduleCount == 1)
    }

    @Test func beginTerminationHonorsExistingQuittingStateWithoutRescheduling() {
        let coordinator = AppTerminationCoordinator()
        let appState = AppState()
        appState.isQuitting = true
        var scheduleCount = 0

        coordinator.beginTermination(appState: appState) {
            scheduleCount += 1
        }
        coordinator.beginTermination(appState: appState) {
            scheduleCount += 1
        }

        #expect(appState.isQuitting)
        #expect(scheduleCount == 1)
    }
}
