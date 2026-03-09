import AppKit
import Foundation

enum BrandingAsset: String, CaseIterable {
    case appIconArtwork = "AppIcon-New"
    case splashArtwork = "AboutArtwork"
    case splashArtworkSquare = "AboutArtwork-Square"

    var filename: String {
        // Both splash variants use the same AboutArtwork image
        switch self {
        case .splashArtworkSquare:
            return "AboutArtwork"
        default:
            return rawValue
        }
    }

    var url: URL? {
        Bundle.main.url(forResource: filename, withExtension: "png", subdirectory: "Branding")
    }

    var image: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
