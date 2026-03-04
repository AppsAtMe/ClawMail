import SwiftUI
import ClawMailCore

@main
struct ClawMailAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar extra (always visible)
        MenuBarExtra("ClawMail", systemImage: menuBarIcon) {
            StatusMenu()
                .environment(appDelegate.appState)
        }

        // Settings window (opened on demand)
        Settings {
            SettingsWindow()
                .environment(appDelegate.appState)
        }
    }

    private var menuBarIcon: String {
        let state = appDelegate.appState
        if state.launchError != nil {
            return "envelope.badge.shield.half.filled"
        }
        if state.agentConnected {
            return "envelope.fill"
        }
        return "envelope"
    }
}
