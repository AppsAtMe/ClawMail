import SwiftUI
import ClawMailCore

/// Guardrails settings tab: configure send rate limits, domain lists, recipient approval.
struct GuardrailsTab: View {
    @Environment(AppState.self) private var appState

    @State private var rateLimitEnabled = false
    @State private var maxPerMinute = ""
    @State private var maxPerHour = ""
    @State private var maxPerDay = ""

    @State private var allowlistEnabled = false
    @State private var allowlistDomains: [String] = []
    @State private var newAllowDomain = ""

    @State private var blocklistEnabled = false
    @State private var blocklistDomains: [String] = []
    @State private var newBlockDomain = ""

    @State private var firstTimeApproval = false

    @State private var approvedRecipients: [ApprovedRecipient] = []
    @State private var pendingApprovals: [PendingApproval] = []
    @State private var errorState: UIErrorState?

    var body: some View {
        Form {
            // Send Rate Limits
            Section("Send Rate Limits") {
                Toggle("Enable rate limiting", isOn: $rateLimitEnabled)
                if rateLimitEnabled {
                    TextField("Max per minute", text: $maxPerMinute)
                        .textFieldStyle(.roundedBorder)
                    TextField("Max per hour", text: $maxPerHour)
                        .textFieldStyle(.roundedBorder)
                    TextField("Max per day", text: $maxPerDay)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Domain Allowlist
            Section("Domain Allowlist") {
                Toggle("Enable domain allowlist (only allow these domains)", isOn: $allowlistEnabled)
                if allowlistEnabled {
                    ForEach(allowlistDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button(action: {
                                allowlistDomains.removeAll { $0 == domain }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("Add domain (e.g. example.com)", text: $newAllowDomain)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addAllowDomain() }
                        Button("Add") { addAllowDomain() }
                            .disabled(newAllowDomain.isEmpty)
                    }
                }
            }

            // Domain Blocklist
            Section("Domain Blocklist") {
                Toggle("Enable domain blocklist (block these domains)", isOn: $blocklistEnabled)
                if blocklistEnabled {
                    ForEach(blocklistDomains, id: \.self) { domain in
                        HStack {
                            Text(domain)
                            Spacer()
                            Button(action: {
                                blocklistDomains.removeAll { $0 == domain }
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    HStack {
                        TextField("Add domain (e.g. spam.com)", text: $newBlockDomain)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit { addBlockDomain() }
                        Button("Add") { addBlockDomain() }
                            .disabled(newBlockDomain.isEmpty)
                    }
                }
            }

            // First-time Recipient Approval
            Section("First-time Recipient Approval") {
                Toggle("Require approval before sending to new recipients", isOn: $firstTimeApproval)
                if !approvedRecipients.isEmpty {
                    Text("Approved Recipients:")
                        .font(.headline)
                    ForEach(approvedRecipients) { recipient in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(recipient.email)
                                Text(recipient.accountLabel)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Spacer()
                            Text(recipient.approvedAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Button(action: {
                                removeApprovedRecipient(recipient)
                            }) {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }

                if !pendingApprovals.isEmpty {
                    Text("Held Sends:")
                        .font(.headline)
                    ForEach(pendingApprovals) { approval in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(approval.subject ?? approval.operation.rawValue.capitalized)
                                Text(approval.accountLabel)
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                                Text(approval.emails.joined(separator: ", "))
                                    .foregroundStyle(.secondary)
                                    .font(.caption)
                            }
                            Spacer()
                            Text(approval.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .foregroundStyle(.secondary)
                                .font(.caption)
                            Button("Approve") {
                                approvePendingApproval(approval)
                            }
                            .buttonStyle(.borderless)
                            Button("Reject") {
                                rejectPendingApproval(approval)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear { loadFromConfig() }
        .onChange(of: rateLimitEnabled) { _, _ in saveConfig() }
        .onChange(of: maxPerMinute) { _, _ in saveConfig() }
        .onChange(of: maxPerHour) { _, _ in saveConfig() }
        .onChange(of: maxPerDay) { _, _ in saveConfig() }
        .onChange(of: allowlistEnabled) { _, _ in saveConfig() }
        .onChange(of: allowlistDomains) { _, _ in saveConfig() }
        .onChange(of: blocklistEnabled) { _, _ in saveConfig() }
        .onChange(of: blocklistDomains) { _, _ in saveConfig() }
        .onChange(of: firstTimeApproval) { _, _ in saveConfig() }
        .alert("Operation Failed", isPresented: showingErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorState?.message ?? "Unknown error.")
        }
    }

    private func loadFromConfig() {
        let guardrails = appState.config.guardrails
        rateLimitEnabled = false
        maxPerMinute = ""
        maxPerHour = ""
        maxPerDay = ""
        allowlistEnabled = false
        allowlistDomains = []
        blocklistEnabled = false
        blocklistDomains = []

        if let rateLimit = guardrails.sendRateLimit {
            rateLimitEnabled = true
            maxPerMinute = rateLimit.maxPerMinute.map(String.init) ?? ""
            maxPerHour = rateLimit.maxPerHour.map(String.init) ?? ""
            maxPerDay = rateLimit.maxPerDay.map(String.init) ?? ""
        }

        if let allowlist = guardrails.domainAllowlist {
            allowlistEnabled = true
            allowlistDomains = allowlist
        }

        if let blocklist = guardrails.domainBlocklist {
            blocklistEnabled = true
            blocklistDomains = blocklist
        }

        firstTimeApproval = guardrails.firstTimeRecipientApproval

        loadApprovalState()
    }

    private func saveConfig() {
        var config = appState.config
        config.guardrails.sendRateLimit = rateLimitEnabled ? RateLimitConfig(
            maxPerMinute: Int(maxPerMinute),
            maxPerHour: Int(maxPerHour),
            maxPerDay: Int(maxPerDay)
        ) : nil
        config.guardrails.domainAllowlist = allowlistEnabled ? allowlistDomains : nil
        config.guardrails.domainBlocklist = blocklistEnabled ? blocklistDomains : nil
        config.guardrails.firstTimeRecipientApproval = firstTimeApproval
        do {
            try config.save()
            appState.config = config
        } catch {
            errorState = UIErrorState(action: "Saving guardrail settings", error: error)
            loadFromConfig()
            return
        }
        // Push new guardrail rules into the running engine immediately.
        let guardrails = config.guardrails
        Task { await appState.orchestrator?.updateGuardrailConfig(guardrails) }
    }

    private func addAllowDomain() {
        let domain = newAllowDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty, !allowlistDomains.contains(domain) else { return }
        allowlistDomains.append(domain)
        newAllowDomain = ""
    }

    private func addBlockDomain() {
        let domain = newBlockDomain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !domain.isEmpty, !blocklistDomains.contains(domain) else { return }
        blocklistDomains.append(domain)
        newBlockDomain = ""
    }

    private func removeApprovedRecipient(_ recipient: ApprovedRecipient) {
        Task {
            do {
                try await appState.orchestrator?.removeApprovedRecipient(
                    email: recipient.email,
                    account: recipient.accountLabel
                )
                loadApprovalState()
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Removing approved recipient", error: error)
                }
            }
        }
    }

    private func approvePendingApproval(_ approval: PendingApproval) {
        Task {
            do {
                try await appState.orchestrator?.approvePendingApproval(
                    requestId: approval.requestId,
                    account: approval.accountLabel
                )
                loadApprovalState()
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Approving held send", error: error)
                }
            }
        }
    }

    private func rejectPendingApproval(_ approval: PendingApproval) {
        Task {
            do {
                try await appState.orchestrator?.rejectPendingApproval(
                    requestId: approval.requestId,
                    account: approval.accountLabel
                )
                loadApprovalState()
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Rejecting held send", error: error)
                }
            }
        }
    }

    private func loadApprovalState() {
        guard let orchestrator = appState.orchestrator else {
            approvedRecipients = []
            pendingApprovals = []
            return
        }

        Task {
            do {
                async let recipients = orchestrator.listApprovedRecipients()
                async let approvals = orchestrator.listPendingApprovals()
                let (loadedRecipients, loadedApprovals) = try await (recipients, approvals)

                await MainActor.run {
                    approvedRecipients = loadedRecipients
                    pendingApprovals = loadedApprovals
                }
            } catch {
                await MainActor.run {
                    errorState = UIErrorState(action: "Loading recipient approval state", error: error)
                }
            }
        }
    }

    private var showingErrorAlert: Binding<Bool> {
        Binding(
            get: { errorState != nil },
            set: { if !$0 { errorState = nil } }
        )
    }
}
