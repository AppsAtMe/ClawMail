import AppKit
import Foundation

enum BrandingAsset: String, CaseIterable {
    case appIconArtwork = "AppIconArtwork"
    case splashArtwork = "SplashArtwork"
    case splashArtworkSquare = "SplashArtworkSquare"

    var url: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Branding")
    }

    var image: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
