import SwiftUI
import Darwin
import ClawMailCore

@main
struct ClawMailAppMain: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        AppLogBootstrap.configureIfNeeded()
    }

    var body: some Scene {
        // Menu bar extra (always visible)
        MenuBarExtra {
            StatusMenu()
                .environment(appDelegate.appState)
        } label: {
            MenuBarLabel()
                .environment(appDelegate.appState)
        }
        .menuBarExtraStyle(.window)

        // Settings window (opened on demand)
        Settings {
            SettingsWindow()
                .environment(appDelegate.appState)
        }
    }
}

private enum AppLogBootstrap {
    static let stdoutPath = "/tmp/clawmail.stdout.log"
    static let stderrPath = "/tmp/clawmail.stderr.log"

    static func configureIfNeeded() {
        redirect(fileDescriptor: STDOUT_FILENO, to: stdoutPath)
        redirect(fileDescriptor: STDERR_FILENO, to: stderrPath)
        setvbuf(stdout, nil, _IOLBF, 0)
        setvbuf(stderr, nil, _IONBF, 0)
        logStartup()
    }

    private static func redirect(fileDescriptor: Int32, to path: String) {
        // Preserve direct terminal output when the app is launched from an interactive shell.
        guard isatty(fileDescriptor) == 0 else { return }

        let descriptor = open(path, O_WRONLY | O_CREAT | O_APPEND, 0o644)
        guard descriptor >= 0 else { return }

        if descriptor != fileDescriptor {
            _ = dup2(descriptor, fileDescriptor)
            close(descriptor)
        }
    }

    private static func logStartup() {
        let formatter = ISO8601DateFormatter()
        let timestamp = formatter.string(from: Date())
        fputs("ClawMail: log bootstrap active at \(timestamp) (stdout=\(stdoutPath), stderr=\(stderrPath))\n", stderr)
    }
}

private struct MenuBarLabel: View {
    @Environment(AppState.self) private var appState
    @Environment(\.openSettings) private var openSettingsAction

    var body: some View {
        Image(systemName: menuBarIcon)
            .help("ClawMail")
            .onAppear { presentSettingsIfRequested() }
            .onChange(of: appState.showSettings) { _, _ in
                presentSettingsIfRequested()
            }
    }

    private var menuBarIcon: String {
        if appState.launchError != nil {
            return "envelope.badge.shield.half.filled"
        }
        if appState.agentConnected {
            return "envelope.fill"
        }
        return "envelope"
    }

    private func presentSettingsIfRequested() {
        guard appState.showSettings else { return }
        appState.showSettings = false
        openSettingsAction()
        NSApp.activate(ignoringOtherApps: true)
    }
}
