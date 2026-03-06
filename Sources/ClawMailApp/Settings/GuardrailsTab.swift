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
                if firstTimeApproval && !approvedRecipients.isEmpty {
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
    }

    private func loadFromConfig() {
        let guardrails = appState.config.guardrails

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

        // Load approved recipients
        if let orchestrator = appState.orchestrator {
            Task {
                if let recipients = try? await orchestrator.listApprovedRecipients() {
                    await MainActor.run {
                        approvedRecipients = recipients
                    }
                }
            }
        }
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
        appState.config = config
        try? config.save()
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
            try? await appState.orchestrator?.removeApprovedRecipient(
                email: recipient.email,
                account: recipient.accountLabel
            )
            approvedRecipients.removeAll { $0.id == recipient.id }
        }
    }
}
