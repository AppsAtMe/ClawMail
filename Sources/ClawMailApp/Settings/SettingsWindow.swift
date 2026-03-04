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
    }
}
