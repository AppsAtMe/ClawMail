import AppKit
import SwiftUI
import ClawMailCore

struct AboutTab: View {
    @Environment(AppState.self) private var environmentAppState
    private let appStateOverride: AppState?
    private let details: AboutAppDetails
    private let revealAction: @MainActor (URL) -> Void
    private let copySupportAction: @MainActor (String) -> Void
    internal let inspection = Inspection<Self>()

    @State private var copiedSupportInfo = false

    init(
        appState: AppState? = nil,
        details: AboutAppDetails = .current(),
        revealAction: @escaping @MainActor (URL) -> Void = Self.defaultRevealAction,
        copySupportAction: @escaping @MainActor (String) -> Void = Self.defaultCopySupportAction
    ) {
        self.appStateOverride = appState
        self.details = details
        self.revealAction = revealAction
        self.copySupportAction = copySupportAction
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroCard
                metricsGrid

                if let launchError = appState.launchError {
                    launchErrorCard(message: launchError)
                }

                detailGrid
            }
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(24)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(inspection.notice) { inspection.visit(self, $0) }
        .onDisappear {
            copiedSupportInfo = false
        }
    }

    private var heroCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.25, blue: 0.45),
                            Color(red: 0.05, green: 0.15, blue: 0.30),
                            Color(red: 0.02, green: 0.08, blue: 0.18)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.25), lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    Circle()
                        .fill(Color.white.opacity(0.16))
                        .frame(width: 240, height: 240)
                        .blur(radius: 70)
                        .offset(x: -36, y: -92)
                }

            ViewThatFits(in: .horizontal) {
                heroRowLayout
                heroColumnLayout
            }
            .padding(24)
        }
        .environment(\.colorScheme, .dark)
    }

    private var heroRowLayout: some View {
        HStack(alignment: .center, spacing: 24) {
            heroTextBlock
            Spacer(minLength: 0)
            heroArtwork
        }
    }

    private var heroColumnLayout: some View {
        VStack(alignment: .leading, spacing: 20) {
            heroTextBlock

            HStack {
                Spacer(minLength: 0)
                heroArtwork
            }
        }
    }

    private var heroTextBlock: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                iconBadge
                Text("About ClawMail")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(heroEyebrowColor)
            }

            Text(details.appName)
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(heroTitleColor)

            Text("Menu bar control for mail, calendar, contacts, tasks, and automation on macOS.")
                .font(.body.weight(.medium))
                .foregroundStyle(heroBodyColor)
                .fixedSize(horizontal: false, vertical: true)

            Text("Designed to stay lightweight when several accounts are active, while keeping support paths and runtime details close at hand.")
                .font(.callout)
                .foregroundStyle(heroSecondaryBodyColor)
                .fixedSize(horizontal: false, vertical: true)

            heroMetadata
            heroActions

            if copiedSupportInfo {
                Label("Support summary copied to the clipboard", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var heroMetadata: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                heroPill("Version \(details.version)")
                heroPill("Build \(details.build)")
                heroPill("macOS \(details.minimumSystemVersion)+")
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    heroPill("Version \(details.version)")
                    heroPill("Build \(details.build)")
                }
                heroPill("macOS \(details.minimumSystemVersion)+")
            }
        }
    }

    private var heroActions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) {
                openSupportFolderButton
                copySupportButton
            }

            VStack(alignment: .leading, spacing: 10) {
                openSupportFolderButton
                copySupportButton
            }
        }
    }

    private var openSupportFolderButton: some View {
        Button("Open Support Folder") {
            copiedSupportInfo = false
            revealAction(details.supportDirectoryURL)
        }
        .buttonStyle(HeroActionButtonStyle(kind: .primary))
    }

    private var copySupportButton: some View {
        Button("Copy Support Info") {
            copySupportAction(details.supportSummary)
            copiedSupportInfo = true
        }
        .buttonStyle(HeroActionButtonStyle(kind: .secondary))
    }

    private var metricsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
            metricCard(
                title: "Accounts",
                value: "\(appState.accounts.count)",
                subtitle: accountsMetricSubtitle,
                tint: .blue
            )

            metricCard(
                title: "Automation",
                value: appState.agentConnected ? "Connected" : "Idle",
                subtitle: appState.agentConnected ? "MCP agent is online" : "Waiting for an agent connection",
                tint: appState.agentConnected ? .green : .orange
            )

            metricCard(
                title: "Services",
                value: serviceHealthTitle,
                subtitle: serviceHealthSubtitle,
                tint: serviceHealthTint
            )
        }
    }

    private var detailGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 16, alignment: .top)], spacing: 16) {
            detailsCard
            storageCard
            accountsCard
            designCard
        }
    }

    private var detailsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Release", systemImage: "shippingbox")

                Text("Identity, versioning, and platform details for this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                detailRow(title: "Version", value: details.version)
                detailRow(title: "Build", value: details.build)
                detailRow(title: "Bundle ID", value: details.bundleIdentifier)
                detailRow(title: "Minimum macOS", value: details.minimumSystemVersion)
                detailRow(title: "License", value: "MIT License")

                if let copyright = details.copyright {
                    detailRow(title: "Copyright", value: copyright)
                }
            }
        }
    }

    private var storageCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Support & Diagnostics", systemImage: "folder")

                Text("These are the quickest places to inspect when debugging, backing up a setup, or handing off support details.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                pathRow(title: "Application Support", url: details.supportDirectoryURL)
                pathRow(title: "Config File", url: details.configURL)
                pathRow(title: "Database", url: details.databaseURL)
            }
        }
    }

    private var accountsCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Configured Accounts", systemImage: "person.2")

                if displayedAccounts.isEmpty {
                    Text("No accounts are configured yet. Use the Accounts tab to add your first provider and start syncing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(displayedAccounts.enumerated()), id: \.element.id) { index, account in
                            if index > 0 {
                                Divider()
                            }
                            accountRow(account)
                        }

                        if hiddenAccountCount > 0 {
                            Text("+ \(hiddenAccountCount) more \(hiddenAccountCount == 1 ? "account" : "accounts") in the Accounts tab")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private var designCard: some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                cardHeader("Built For", systemImage: "sparkles")

                designRow(
                    title: "Multi-account setups",
                    text: "Keep the menu bar focused on status and quick actions while heavier account details stay in Settings.",
                    systemImage: "person.2.fill",
                    tint: .blue
                )

                designRow(
                    title: "Local inspection",
                    text: "Config, metadata, and support files live in predictable paths under your user Library.",
                    systemImage: "folder.fill",
                    tint: .orange
                )

                designRow(
                    title: "Automation workflows",
                    text: "Mail, calendars, contacts, tasks, and agent integrations share one app shell.",
                    systemImage: "bolt.fill",
                    tint: .green
                )
            }
        }
    }

    private func launchErrorCard(message: String) -> some View {
        card(
            fill: Color.red.opacity(0.08),
            stroke: Color.red.opacity(0.18)
        ) {
            VStack(alignment: .leading, spacing: 12) {
                cardHeader("Launch Issue", systemImage: "exclamationmark.triangle.fill", iconTint: .red)

                Text("ClawMail hit an error while starting one or more background services.")
                    .font(.subheadline.weight(.medium))

                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Reveal Application Support") {
                    copiedSupportInfo = false
                    revealAction(details.supportDirectoryURL)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var heroArtwork: some View {
        artworkView(asset: .appIconArtwork, cornerRadius: 28, fallbackSystemImage: "mail.stack.fill")
            .frame(width: 196, height: 196)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("ClawMail artwork")
    }

    private var iconBadge: some View {
        artworkView(asset: .appIconArtwork, cornerRadius: 14, fallbackSystemImage: "envelope.badge.fill")
            .frame(width: 42, height: 42)
            .shadow(color: Color.black.opacity(0.14), radius: 10, y: 6)
    }

    private func artworkView(asset: BrandingAsset, cornerRadius: CGFloat, fallbackSystemImage: String) -> some View {
        Group {
            if let image = asset.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(red: 0.10, green: 0.45, blue: 0.78),
                            Color(red: 0.02, green: 0.16, blue: 0.38)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )

                    Image(systemName: fallbackSystemImage)
                        .font(.system(size: 44, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .shadow(color: Color.black.opacity(0.12), radius: 18, y: 10)
    }

    private func heroPill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(Color(red: 0.05, green: 0.24, blue: 0.42))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.72))
            )
    }

    private var heroEyebrowColor: Color {
        Color.white.opacity(0.74)
    }

    private var heroTitleColor: Color {
        Color.white.opacity(0.98)
    }

    private var heroBodyColor: Color {
        Color.white.opacity(0.90)
    }

    private var heroSecondaryBodyColor: Color {
        Color.white.opacity(0.72)
    }

    private func metricCard(title: String, value: String, subtitle: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(tint.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.18), lineWidth: 1)
        )
    }

    private func card<Content: View>(
        fill: Color = Color(nsColor: .controlBackgroundColor),
        stroke: Color? = Color.black.opacity(0.05),
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(fill)
            )
            .overlay {
                if let stroke {
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(stroke, lineWidth: 1)
                }
            }
    }

    private func cardHeader(_ title: String, systemImage: String, iconTint: Color = .accentColor) -> some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .foregroundStyle(iconTint)
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
    }

    private func detailRow(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(value)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func pathRow(title: String, url: URL) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(url.path)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button("Reveal \(title)") {
                copiedSupportInfo = false
                revealAction(url)
            }
            .buttonStyle(.link)
        }
    }

    private func accountRow(_ account: Account) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(account.label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(account.emailAddress)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer(minLength: 10)
            ConnectionStatusBadge(status: account.connectionStatus)
        }
    }

    private func designRow(title: String, text: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tint.opacity(0.15))
                .frame(width: 30, height: 30)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var appState: AppState {
        appStateOverride ?? environmentAppState
    }

    private var displayedAccounts: [Account] {
        Array(appState.accounts.prefix(3))
    }

    private var hiddenAccountCount: Int {
        max(0, appState.accounts.count - displayedAccounts.count)
    }

    private var accountsMetricSubtitle: String {
        switch appState.accounts.count {
        case 0:
            return "Add your first account in Settings"
        case 1:
            return "1 account configured"
        default:
            return "\(appState.accounts.count) accounts configured"
        }
    }

    private var serviceHealthTitle: String {
        if appState.launchError != nil {
            return "Attention"
        }
        if appState.isRunning {
            return "Healthy"
        }
        return "Starting"
    }

    private var serviceHealthSubtitle: String {
        if appState.launchError != nil {
            return "A launch issue needs attention"
        }
        if appState.isRunning {
            return "Background services are running"
        }
        return "Starting account and API services"
    }

    private var serviceHealthTint: Color {
        if appState.launchError != nil {
            return .red
        }
        if appState.isRunning {
            return .green
        }
        return .orange
    }

    private static func defaultRevealAction(_ url: URL) {
        let fileManager = FileManager.default
        let target = fileManager.fileExists(atPath: url.path) ? url : url.deletingLastPathComponent()
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    private static func defaultCopySupportAction(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct AboutAppDetails: Equatable {
    let appName: String
    let version: String
    let build: String
    let bundleIdentifier: String
    let minimumSystemVersion: String
    let supportDirectoryURL: URL
    let configURL: URL
    let databaseURL: URL
    let copyright: String?

    var supportSummary: String {
        var lines = [
            appName,
            "Version: \(version)",
            "Build: \(build)",
            "Bundle ID: \(bundleIdentifier)",
            "Minimum macOS: \(minimumSystemVersion)",
            "Application Support: \(supportDirectoryURL.path)",
            "Config File: \(configURL.path)",
            "Database: \(databaseURL.path)"
        ]

        if let copyright {
            lines.append("Copyright: \(copyright)")
        }

        return lines.joined(separator: "\n")
    }

    static func current(bundle: Bundle = .main) -> AboutAppDetails {
        AboutAppDetails(
            appName: bundle.infoDictionaryString(forKey: "CFBundleDisplayName")
                ?? bundle.infoDictionaryString(forKey: "CFBundleName")
                ?? "ClawMail",
            version: bundle.infoDictionaryString(forKey: "CFBundleShortVersionString")
                ?? ClawMailVersion.current,
            build: bundle.infoDictionaryString(forKey: "CFBundleVersion")
                ?? ClawMailVersion.build,
            bundleIdentifier: bundle.bundleIdentifier ?? "com.clawmail.app",
            minimumSystemVersion: bundle.infoDictionaryString(forKey: "LSMinimumSystemVersion")
                ?? "14.0",
            supportDirectoryURL: AppConfig.defaultDirectoryURL,
            configURL: AppConfig.defaultConfigURL,
            databaseURL: DatabaseManager.defaultDatabaseURL,
            copyright: bundle.infoDictionaryString(forKey: "NSHumanReadableCopyright")
        )
    }
}

private extension Bundle {
    func infoDictionaryString(forKey key: String) -> String? {
        object(forInfoDictionaryKey: key) as? String
    }
}

private struct HeroActionButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(foregroundColor)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(backgroundColor(configuration.isPressed))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(borderColor(configuration.isPressed), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.985 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private var foregroundColor: Color {
        switch kind {
        case .primary:
            return Color(red: 0.05, green: 0.15, blue: 0.29)
        case .secondary:
            return Color.white.opacity(0.94)
        }
    }

    private func backgroundColor(_ isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return Color.white.opacity(isPressed ? 0.82 : 0.94)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.16 : 0.10)
        }
    }

    private func borderColor(_ isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return Color.white.opacity(isPressed ? 0.18 : 0.22)
        case .secondary:
            return Color.white.opacity(isPressed ? 0.42 : 0.28)
        }
    }
}
