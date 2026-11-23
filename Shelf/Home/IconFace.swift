import SwiftUI
import UIKit

/// SF Symbol names come from the server and from model replies, so any of
/// them may not exist. A name that isn't a symbol becomes the generic glyph.
@MainActor
enum Symbol {
    static let fallback = "app"
    private static var known: [String: String] = [:]

    static func resolve(_ name: String?) -> String {
        guard let name, !name.isEmpty else { return fallback }
        if let hit = known[name] { return hit }
        let resolved = UIImage(systemName: name) == nil ? fallback : name
        known[name] = resolved
        return resolved
    }
}

extension Tint {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

/// What an icon is drawn from. Apps and Shelf's own Settings icon share it.
struct IconFace: Equatable {
    var symbol: String
    var tint: Color

    @MainActor
    init(_ app: AppMeta) {
        symbol = Symbol.resolve(app.icon)
        tint = app.tint.color
    }

    init(symbol: String, tint: Color) {
        self.symbol = symbol
        self.tint = tint
    }

    static let settings = IconFace(symbol: "gearshape.fill", tint: .gray)

    /// The tile, top to bottom: the system's near-black in dark mode,
    /// otherwise the tint, lifted toward white at the top. `IconPalette`
    /// resolves it once for every place an icon is painted.
    func fill(dark: Bool) -> (top: Color, bottom: Color) {
        dark ? (HomeMetrics.darkFillTop, HomeMetrics.darkFillBottom)
            : (tint.mix(with: .white, by: HomeMetrics.fillLift), tint)
    }
}
