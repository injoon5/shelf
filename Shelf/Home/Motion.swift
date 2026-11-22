import SwiftUI

/// Every spring and duration in Shelf. Movement uses springs so it can be
/// interrupted from wherever it is; the few timing curves here are for things
/// that don't move (a fade, the jiggle's swing).
enum Motion {
    // MARK: Springs

    /// Icons sliding aside while one is dragged.
    static let reorder = Animation.spring(duration: 0.35, bounce: 0.15)
    /// Entering and leaving edit mode, the banner, search.
    static let standard = Animation.spring(duration: 0.4, bounce: 0.1)
    /// Small state changes: a press releasing, a dot appearing.
    static let quick = Animation.spring(duration: 0.25, bounce: 0)
    /// The pill becoming the search field.
    static let search = Animation.spring(duration: 0.45, bounce: 0.18)
    /// An icon refusing to open.
    static let shake = Animation.spring(duration: 0.12, bounce: 0.6)
    /// The install pie filling.
    static let pie = Animation.spring(duration: 0.5, bounce: 0)

    // MARK: Fades

    static let fade = Animation.easeOut(duration: 0.2)
    /// The app replacing its launch screen.
    static let launch = Animation.easeOut(duration: 0.18)

    // MARK: Jiggle

    /// One full swing, there and back.
    static let jigglePeriod: Double = 0.26
    static var jiggle: Animation { .easeInOut(duration: jigglePeriod / 2).repeatForever(autoreverses: true) }

    // MARK: Durations

    /// Nothing that loads shows a spinner before this.
    static let spinnerDelay: Duration = .milliseconds(300)
    /// How far the pie creeps while a download is still running.
    static let pieCreep: Double = 0.85
    static let pieCreepTime: Double = 2.5
    static let bannerStay: Duration = .seconds(3)
    static let pageDotsStay: Duration = .seconds(1)
    static let copiedStay: Duration = .milliseconds(1500)
    static let pageFlipHold: Duration = .milliseconds(600)
    /// The zoom into an app. Kiln parses on the main thread, so the app is
    /// built only after this, behind the launch screen.
    static let launchSettle: Duration = .milliseconds(420)
    static let wallpaperDrift: Double = 20
    static let syncStaleAfter: TimeInterval = 600
    static let keyPoll: Duration = .seconds(3)
    static let dataPullTimeout: Duration = .seconds(1)
}
