import SwiftUI
import ClawMailCore

/// Main settings window with sidebar tab navigation.
struct SettingsWindow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        @Bindable var state = appState
        TabView(selection: $state.settingsTab) {
            AccountsTab()
                .tabItem {
                    Label("Accounts", systemImage: "person.crop.circle")
                }
                .tag(SettingsTab.accounts)

            GuardrailsTab()
                .tabItem {
                    Label("Guardrails", systemImage: "shield.checkered")
                }
                .tag(SettingsTab.guardrails)

            APITab()
                .tabItem {
                    Label("API", systemImage: "network")
                }
                .tag(SettingsTab.api)

            ActivityLogTab()
                .tabItem {
                    Label("Activity Log", systemImage: "list.bullet.rectangle")
                }
                .tag(SettingsTab.activityLog)

            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gearshape")
                }
                .tag(SettingsTab.general)
        }
        .frame(minWidth: 650, minHeight: 450)
        .environment(appState)
        .onAppear {
            // LSUIElement apps have no Dock icon and can't receive focus normally.
            // Temporarily switch to .regular so macOS brings the window to front
            // with full keyboard focus.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async {
                for window in NSApp.windows where window.isVisible {
                    window.makeKeyAndOrderFront(nil)
                }
            }
        }
        .onDisappear {
            // If no other windows are visible, revert to accessory (menu bar only)
            let hasVisibleWindows = NSApp.windows.contains { $0.isVisible && !($0 is NSPanel) }
            if !hasVisibleWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
