import Foundation

enum BrandingAsset: String, CaseIterable {
    case appIconArtwork = "AppIconArtwork"
    case splashArtwork = "SplashArtwork"
    case splashArtworkSquare = "SplashArtworkSquare"

    var url: URL? {
        Bundle.main.url(forResource: rawValue, withExtension: "png", subdirectory: "Branding")
    }
}
