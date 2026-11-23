import UIKit

/// Every number search is drawn and moved with: App Library's search, with
/// its top bar moved to the bottom (PLAN.md §0.3).
///
/// Measured on the iPhone 17 simulator (402 × 874 pt, iOS 27.0) from 3x
/// captures of App Library search with an empty query, light and dark
/// (`design/reference/README.md`, "Search"). The section headers, the round
/// ✕ and the cloud glyph aren't in the simulator's App Library, so those
/// come from `app-library-search.png`, which is a 402 pt wide screen at
/// 1.667 px/pt once its frame is taken off.
enum SearchMetrics {
    // MARK: The field

    /// 144 px tall at 3x, its glass rim included.
    static let fieldHeight: CGFloat = 48
    /// App Library's field starts 77 px in.
    static let sideInset: CGFloat = 25.67
    /// The round ✕ beside the field is as tall as the field, 12.67 pt from
    /// it (the reference: 79 px across, 21 px from the field).
    static let closeSize: CGFloat = 48
    static let closeGap: CGFloat = 12.67
    /// The ✕ itself: 18.6 pt across in the reference.
    static let closeGlyphSize: CGFloat = 19
    /// The magnifier's ink starts 18.33 pt into the field (132 px against 77).
    static let glyphInset: CGFloat = 18.33
    /// The placeholder's text starts 48 pt into the field (222 px), so
    /// 29.67 pt from where the magnifier starts.
    static let textInset: CGFloat = 48
    /// The placeholder and what's typed: an "L" 47 px tall at 3x, which is
    /// SF Pro's cap height at 22 pt, regular (a 5 px stem). That's Title 2.
    static let fieldTextStyle = UIFont.TextStyle.title2
    /// Room kept at the field's trailing end for the clear button.
    static let textTrailing: CGFloat = 8
    /// Between the field and the top of the keyboard.
    static let keyboardGap: CGFloat = 8

    // MARK: The list

    /// From the top of the status bar's safe area to where the list starts:
    /// where App Library's top bar starts (90 pt, 28 below the 62 pt status
    /// bar). The bar is at the bottom here, so the list moves up into its place.
    static let listTop: CGFloat = 28
    /// Between the last row and the field, as App Library keeps between its
    /// field and its first row (the field's bottom at 138 pt, the row's top
    /// at 162).
    static let fieldGap: CGFloat = 24
    /// Rows: a 48 pt icon on a 72 pt pitch (216 px between separators).
    static let rowHeight: CGFloat = 72
    static let iconSize: CGFloat = 48
    /// The icon's leading edge, 79 px in.
    static let iconLeading: CGFloat = 26.33
    /// The name starts 90 pt in, and so does its separator (270 px).
    static let textLeading: CGFloat = 90
    /// The separator ends 30.67 pt from the trailing edge (1114 px), clear
    /// of the index.
    static let trailingInset: CGFloat = 30.67
    /// The name: Body, regular, white (a "C" 37 px tall with a 4 px stem).
    static let nameTextStyle = UIFont.TextStyle.body
    /// The separator is 3 px, a whole point, 25 of 255 lighter than what's
    /// behind it: 46 to 72 over the dark backdrop (white at 12%), 96 to 121
    /// over the light (16%). White at 14% is within 3 of both.
    static let separatorHeight: CGFloat = 1
    static let separatorOpacity: CGFloat = 0.14
    /// A section's header: the letter, 15 pt bold (a 10.5 pt cap), in line
    /// with the icons, its baseline 8.33 pt above the first row, in a
    /// 28.33 pt band.
    static let headerHeight: CGFloat = 28.33
    static let headerBaseline: CGFloat = 8.33
    static let headerFontSize: CGFloat = 15
    /// The cloud on an app that isn't downloaded: 19.5 pt across, its
    /// trailing edge 10.33 pt inside the separator's end.
    static let cloudWidth: CGFloat = 19.5
    static let cloudTrailing: CGFloat = 10.33

    // MARK: The index

    /// A–Z and #: letters centred 7.67 pt from the trailing edge (1183 px),
    /// 13.27 pt apart (A at 1002 px, # at 2077), with a 7.33 pt cap height,
    /// which is SF Pro semibold at 10.4 pt. Centred on the list's visible
    /// height, as App Library's is on its own.
    static let indexCenterFromTrailing: CGFloat = 7.67
    static let indexPitch: CGFloat = 13.27
    static let indexFontSize: CGFloat = 10.4
    static let indexWeight = UIFont.Weight.semibold
    /// How wide a finger's target the index is.
    static let indexHitWidth: CGFloat = 30

    // MARK: The backdrop

    /// App Library's search over the Home Screen it came from, fitted pixel
    /// by pixel at 1x: a Gaussian blur with a 40 pt standard deviation,
    /// then 0.85 of each channel less 14 of 255 in dark mode and 22 in
    /// light (rms 2.1 and 3.0 of 255 over the open wallpaper).
    static let blurSigma: CGFloat = 40
    static let backdropScale: CGFloat = 0.85
    static let backdropOffsetDark: CGFloat = -14 / 255
    static let backdropOffsetLight: CGFloat = -22 / 255
    /// White names have to read over any wallpaper: where the blurred
    /// wallpaper would average brighter than this, the backdrop darkens
    /// more. App Library's own backdrops average 0.09 and 0.27.
    static let backdropCeiling: CGFloat = 0.35

    // MARK: The pull

    /// A pull down on the Home Screen this long takes the pill all the way
    /// to the field.
    static let pullDistance: CGFloat = 150
    /// A pull let go of past this much of the warp opens search...
    static let openProgress: CGFloat = 0.4
    /// ...as does one let go of moving down faster than this (pt/s). One
    /// moving up this fast goes back to the pill wherever it is.
    static let openVelocity: CGFloat = 400
    /// The parts of the warp each thing moves over. The grid and the dock
    /// blur and fade over the first part; the backdrop reaches its full
    /// blur a little later, so nothing sharp is left when they're gone; the
    /// list fades in and rises over the last part; the ✕ arrives at the end.
    static let homeFade: ClosedRange<CGFloat> = 0...0.5
    static let backdropRamp: ClosedRange<CGFloat> = 0...0.6
    static let listFade: ClosedRange<CGFloat> = 0.5...1
    static let closeArrival: ClosedRange<CGFloat> = 0.7...1
    /// The text field itself (its caret) shows only once the field is there.
    static let caretArrival: ClosedRange<CGFloat> = 0.9...1
    /// How far below its place the list starts as it fades in.
    static let listRise: CGFloat = 20
    /// Pulling the list down this far past its top, and letting go, closes search.
    static let closePull: CGFloat = 60
}

extension ClosedRange where Bound == CGFloat {
    /// Where `value` is through this range, from 0 at its start to 1 at its end.
    func ramp(_ value: CGFloat) -> CGFloat {
        guard upperBound > lowerBound else { return value >= upperBound ? 1 : 0 }
        return Swift.min(Swift.max((value - lowerBound) / (upperBound - lowerBound), 0), 1)
    }
}
