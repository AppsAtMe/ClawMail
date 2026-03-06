import SwiftUI
import ClawMailCore

/// Activity log tab: scrollable, filterable audit log viewer.
struct ActivityLogTab: View {
    @Environment(AppState.self) private var appState

    @State private var entries: [AuditEntry] = []
    @State private var accountFilter: String?
    @State private var searchText = ""
    @State private var autoRefresh = true
    @State private var errorState: UIErrorState?

    private let refreshTimer = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 0) {
            // Filter bar
            HStack {
                Picker("Account", selection: $accountFilter) {
                    Text("All Accounts").tag(nil as String?)
                    ForEach(appState.accounts) { account in
                        Text(account.label).tag(account.label as String?)
                    }
                }
                .frame(width: 180)

                TextField("Search...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 200)

                Spacer()

                Toggle("Auto-refresh", isOn: $autoRefresh)
                    .toggleStyle(.switch)

                Button(action: { exportLog() }) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Log table
            Table(filteredEntries) {
                TableColumn("Time") { entry in
                    Text(entry.timestamp.formatted(date: .abbreviated, time: .standard))
                        .font(.caption)
                }
                .width(min: 140, ideal: 160)

                TableColumn("Interface") { entry in
                    Text(entry.interface.rawValue.uppercased())
                        .font(.caption.bold())
                        .foregroundStyle(interfaceColor(entry.interface))
                }
                .width(min: 50, ideal: 60)

                TableColumn("Operation") { entry in
                    Text(entry.operation)
                        .font(.system(.caption, design: .monospaced))
                }
                .width(min: 100, ideal: 150)

                TableColumn("Account") { entry in
                    Text(entry.account ?? "-")
                        .font(.caption)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Result") { entry in
                    HStack(spacing: 4) {
                        Image(systemName: entry.result == .success ? "checkmark.circle" : "xmark.circle")
                            .foregroundStyle(entry.result == .success ? .green : .red)
                        Text(entry.result.rawValue)
                            .font(.caption)
                    }
                }
                .width(min: 70, ideal: 80)
            }
        }
        .onAppear { loadEntries() }
        .onReceive(refreshTimer) { _ in
            if autoRefresh { loadEntries() }
        }
        .onChange(of: accountFilter) { _, _ in loadEntries() }
        .alert("Operation Failed", isPresented: showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorState?.message ?? "Unknown error.")
        }
    }

    private var filteredEntries: [AuditEntry] {
        guard !searchText.isEmpty else { return entries }
        let query = searchText.lowercased()
        return entries.filter { entry in
            entry.operation.lowercased().contains(query) ||
            (entry.account?.lowercased().contains(query) ?? false) ||
            entry.interface.rawValue.lowercased().contains(query)
        }
    }

    private func loadEntries() {
        guard let orchestrator = appState.orchestrator else { return }
        Task {
            do {
                let results = try await orchestrator.getAuditLog(account: accountFilter, limit: 500)
                await MainActor.run {
                    entries = results
                }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Loading activity log", error: error)
                }
            }
        }
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "clawmail-audit-log.json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            do {
                let data = try encoder.encode(entries)
                try data.write(to: url, options: .atomic)
            } catch {
                errorState = UIErrorState(action: "Exporting activity log", error: error)
            }
        }
    }

    private var showingErrorAlert: Binding<Bool> {
        Binding(
            get: { errorState != nil },
            set: { if !$0 { errorState = nil } }
        )
    }

    private func interfaceColor(_ interface: AgentInterface) -> Color {
        switch interface {
        case .mcp: return .purple
        case .cli: return .blue
        case .rest: return .orange
        }
    }
}
