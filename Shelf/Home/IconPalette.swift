import SwiftUI
import UIKit

/// The colours an icon is painted in, in one tone: the tile's top and
/// bottom, and the glyph's. Worked out once per face and tone, so the grid,
/// the dock, a card's face and a sheet's preview are the same colours.
struct IconPalette: Equatable {
    var top: UIColor
    var bottom: UIColor
    /// The glyph's colour, or nil for white a shade darker at the foot.
    var glyph: UIColor?

    /// Light icons are the tint, lifted toward white at the top, with a
    /// white glyph. Dark icons are the system's near-black with the glyph in
    /// the tint, as Springboard's dark icons are.
    @MainActor
    init(_ face: IconFace, tone: IconTone) {
        var environment = EnvironmentValues()
        environment.colorScheme = tone.colorScheme
        func ui(_ color: Color) -> UIColor { UIColor(cgColor: color.resolve(in: environment).cgColor) }
        let fill = face.fill(dark: tone == .dark)
        top = ui(fill.top)
        bottom = ui(fill.bottom)
        glyph = tone == .dark ? ui(face.tint) : nil
    }
}

/// An icon's glyph, drawn once per symbol, size and colour, and kept.
@MainActor
enum IconGlyph {
    private static var cache: [String: UIImage] = [:]

    /// The glyph for an icon of side `size`, centred in a square of that
    /// side: a hierarchical SF Symbol at half the icon's size, medium weight.
    static func image(_ symbol: String, iconSize size: CGFloat, color: UIColor?, scale: CGFloat) -> UIImage {
        let key = "\(symbol)|\(size)|\(color.map(\.hexKey) ?? "white")|\(scale)"
        if let known = cache[key] { return known }

        let ink = color ?? .white
        let configuration = UIImage.SymbolConfiguration(pointSize: size * HomeMetrics.glyphRatio, weight: .medium)
            .applying(UIImage.SymbolConfiguration(hierarchicalColor: ink))
        let symbolImage = UIImage(systemName: symbol, withConfiguration: configuration)
            ?? UIImage(systemName: Symbol.fallback, withConfiguration: configuration)!
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        let canvas = CGSize(width: size, height: size)
        let image = UIGraphicsImageRenderer(size: canvas, format: format).image { context in
            // Centred by the symbol's alignment rectangle, as SwiftUI lays
            // out an `Image(systemName:)`, not by its padded image size.
            let insets = symbolImage.alignmentRectInsets
            let aligned = CGSize(width: symbolImage.size.width - insets.left - insets.right,
                                 height: symbolImage.size.height - insets.top - insets.bottom)
            // SwiftUI puts the frame on the pixel grid, so this does too.
            func pixel(_ value: CGFloat) -> CGFloat { (value * scale).rounded() / scale }
            let rect = CGRect(x: pixel((size - aligned.width) / 2 - insets.left), y: pixel((size - aligned.height) / 2 - insets.top),
                              width: symbolImage.size.width, height: symbolImage.size.height)
            symbolImage.draw(in: rect)
            guard color == nil else { return }
            // White, a shade darker at the foot: a little of the depth iOS
            // 27's glyphs have. Painted through the glyph, which keeps its
            // hierarchy's own opacities.
            let cg = context.cgContext
            cg.setBlendMode(.sourceIn)
            let colors = [UIColor.white.cgColor, UIColor.white.withAlphaComponent(HomeMetrics.glyphShade).cgColor] as CFArray
            let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 1])!
            cg.drawLinearGradient(gradient, start: CGPoint(x: 0, y: rect.minY), end: CGPoint(x: 0, y: rect.maxY), options: [])
        }
        cache[key] = image
        return image
    }
}

private extension UIColor {
    var hexKey: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "%.4f,%.4f,%.4f,%.4f", r, g, b, a)
    }
}
