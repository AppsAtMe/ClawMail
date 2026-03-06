import Foundation
import ClawMailCore

struct UIErrorState: Identifiable {
    let id = UUID()
    let message: String

    init(action: String, error: any Error) {
        let detail: String
        if let clawError = error as? ClawMailError {
            detail = clawError.message
        } else {
            let description = error.localizedDescription
            detail = description.isEmpty || description == "(null)" ? String(describing: error) : description
        }
        self.message = "\(action): \(detail)"
    }

    init(message: String) {
        self.message = message
    }
}
