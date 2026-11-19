import SwiftUI
import AppKit

enum RankBadgeStyle {
    private static let symbols = [
        "shield.lefthalf.filled", "shield.fill", "medal.fill", "seal.fill",
        "rosette", "crown.fill", "star.circle.fill", "sparkles", "sun.max.fill"
    ]
    private static let colors: [Color] = [
        Color(red: 0.66, green: 0.39, blue: 0.24),
        Color(red: 0.58, green: 0.63, blue: 0.70),
        Color(red: 0.82, green: 0.62, blue: 0.20),
        Color(red: 0.42, green: 0.58, blue: 0.82),
        Color(red: 0.32, green: 0.66, blue: 0.52),
        Color(red: 0.32, green: 0.70, blue: 0.82),
        Color(red: 0.57, green: 0.47, blue: 0.82),
        Color(red: 0.78, green: 0.36, blue: 0.40),
        Color(red: 0.90, green: 0.67, blue: 0.22)
    ]

    static func symbol(for rankIndex: Int) -> String {
        symbols[min(max(rankIndex, 0), symbols.count - 1)]
    }

    static func color(for rankIndex: Int) -> Color {
        colors[min(max(rankIndex, 0), colors.count - 1)]
    }

    private static let artworkNames = [
        "bronze", "silver", "gold", "platinum", "jade", "diamond", "master", "grandmaster", "king"
    ]
    private static let artworkCache = NSCache<NSString, NSImage>()

    static func artwork(for rankIndex: Int, small: Bool = false) -> Image? {
        let index = min(max(rankIndex, 0), artworkNames.count - 1)
        let cacheKey = "\(index)-\(small)" as NSString
        if let image = artworkCache.object(forKey: cacheKey) { return Image(nsImage: image) }
        let directory = small ? "Resources/RankBadges/Small" : "Resources/RankBadges"
        guard let url = Bundle.module.url(forResource: artworkNames[index], withExtension: "png", subdirectory: directory),
              let image = NSImage(contentsOf: url) else { return nil }
        artworkCache.setObject(image, forKey: cacheKey)
        return Image(nsImage: image)
    }
}
