import SwiftUI

/// What every screen shares. A screen's own sizes are in its metrics file
/// (`HomeMetrics`, `SettingsMetrics`, `CreateMetrics`, `RunnerMetrics`).
enum ShelfMetrics {
    /// Where text stops growing, as in Apple's apps, so nothing that could
    /// overflow at the largest sizes does (plan §13.1). The Home Screen's icons
    /// and edit buttons stop sooner, at `HomeMetrics.textSizeCap`.
    static let textSizeCap = DynamicTypeSize.xxxLarge
}
