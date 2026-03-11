import AppKit
import Foundation

enum BrandingAsset: CaseIterable {
    case appIconArtwork
    case aboutArtwork
    case splashArtwork
    case splashArtworkSquare

    private var filename: String {
        switch self {
        case .appIconArtwork:
            return "AppIconArtwork"
        case .aboutArtwork:
            return "AboutArtwork"
        case .splashArtwork:
            return "SplashArtwork"
        case .splashArtworkSquare:
            return "SplashArtworkSquare"
        }
    }

    private var fileExtension: String {
        switch self {
        case .appIconArtwork:
            return "png"
        case .aboutArtwork, .splashArtwork, .splashArtworkSquare:
            return "png"
        }
    }

    var url: URL? {
        switch self {
        case .appIconArtwork:
            Bundle.main.url(forResource: filename, withExtension: fileExtension, subdirectory: "Branding")
        case .aboutArtwork, .splashArtwork, .splashArtworkSquare:
            Bundle.main.url(forResource: filename, withExtension: fileExtension, subdirectory: "Branding")
        }
    }

    var image: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
