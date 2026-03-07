import SwiftUI
import ClawMailCore

struct ConnectionStatusBadge: View {
    let status: ConnectionStatus

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(foregroundColor)
            .background(
                Capsule()
                    .fill(backgroundColor)
            )
    }

    private var title: String {
        switch status {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error:
            return "Error"
        }
    }

    private var systemImage: String {
        switch status {
        case .connected:
            return "checkmark.circle.fill"
        case .connecting:
            return "arrow.triangle.2.circlepath.circle.fill"
        case .disconnected:
            return "minus.circle.fill"
        case .error:
            return "xmark.circle.fill"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .connected:
            return .white
        case .connecting:
            return Color.black.opacity(0.82)
        case .disconnected:
            return .white
        case .error:
            return .white
        }
    }

    private var backgroundColor: Color {
        switch status {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return Color.secondary.opacity(0.8)
        case .error:
            return .red
        }
    }
}
