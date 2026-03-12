import AppKit
import Foundation

enum BrandingAsset: CaseIterable {
    case appIconArtwork
    case aboutArtwork

    private var filename: String {
        switch self {
        case .appIconArtwork:
            return "AppIconArtwork"
        case .aboutArtwork:
            return "AboutArtwork"
        }
    }

    private var fileExtension: String {
        switch self {
        case .appIconArtwork:
            return "png"
        case .aboutArtwork:
            return "png"
        }
    }

    var url: URL? {
        switch self {
        case .appIconArtwork:
            return Bundle.main.url(forResource: filename, withExtension: fileExtension, subdirectory: "Branding")
        case .aboutArtwork:
            return Bundle.main.url(forResource: filename, withExtension: fileExtension, subdirectory: "Branding")
        }
    }

    var image: NSImage? {
        guard let url else { return nil }
        return NSImage(contentsOf: url)
    }
}
