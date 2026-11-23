import CoreGraphics

/// The New App sheet's sizes, kept out of its views like the Home Screen's.
enum CreateMetrics {
    static let padding: CGFloat = 20
    static let spacing: CGFloat = 14
    static let buttonHeight: CGFloat = 36
    static let closeSize: CGFloat = 30
    static let previewRadius: CGFloat = 28
    static let previewBorder: CGFloat = 0.5
    static let tileSize: CGFloat = 52
    static let fieldSpacing: CGFloat = 2
    /// `Kiln.check`'s warnings listed under the name; the rest are counted.
    static let warningsShown = 2
    static let warningLines = 2
    /// "2 more warnings" lines up with the text of the warnings above it.
    static let warningIndent: CGFloat = 24
}
