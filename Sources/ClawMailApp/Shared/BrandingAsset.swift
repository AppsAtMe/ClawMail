import AppKit
import Foundation

enum BrandingAsset: String, CaseIterable {
    case appIconArtwork = "AppIcon-New"
    case splashArtwork = "AboutArtwork"
    case splashArtworkSquare = "AboutArtwork"

    var url: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Branding")
    }

    var image: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
