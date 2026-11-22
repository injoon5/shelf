import SwiftUI

/// The runner's sizes, kept out of its views like the Home Screen's.
enum RunnerMetrics {
    /// The strip along the top where a downward drag always closes the app.
    static let dismissStrip: CGFloat = 44
    static let dismissDistance: CGFloat = 30

    // MARK: Error screen

    static let errorIconSize: CGFloat = 60
    static let errorSpacing: CGFloat = 16
    static let errorPadding: CGFloat = 24
    /// Lines shown on each side of the failing one.
    static let errorContext = 2
    static let codeRadius: CGFloat = 14
    static let codePadding: CGFloat = 12
    static let codeLineSpacing: CGFloat = 2
    static let gutterGap: CGFloat = 10
    static let failingLineOpacity: Double = 0.16
}
