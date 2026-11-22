import SwiftUI

/// Every number the Home Screen is drawn with, in one place.
///
/// They were measured from Springboard on an iPhone 17 (402 × 874 pt, iOS 27)
/// by reading edges out of a screenshot, and they scale with the screen from
/// there. Tune them here, never in a view.
enum HomeMetrics {
    /// The screen the measurements were taken on.
    static let referenceWidth: CGFloat = 402

    // MARK: Grid

    static let columns = 4
    static let rows = 6
    static var pageSize: Int { columns * rows }

    static let iconSize: CGFloat = 64
    /// From the screen edge to the first column.
    static let sideInset: CGFloat = 30.33
    /// From the bottom of the status bar to the first row.
    static let topInset: CGFloat = 28
    /// From the last row's label to the search pill.
    static let gridBottomGap: CGFloat = 28

    // MARK: Icon

    /// The continuous corner that approximates Apple's icon mask.
    static let iconCornerRatio: CGFloat = 0.2237
    static let glyphRatio: CGFloat = 0.5
    /// How far the top of the fill is lightened toward white.
    static let fillLift: Double = 0.14
    static let darkFillTop = Color(red: 0.173, green: 0.173, blue: 0.180)
    static let darkFillBottom = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let rimWidth: CGFloat = 0.5
    static let rimOpacity: Double = 0.22
    static let pressedBrightness: Double = -0.25
    static let pendingDim: Double = 0.45
    static let pieRatio: CGFloat = 0.5
    static let pieRingWidth: CGFloat = 2

    // MARK: Label

    static let labelSize: CGFloat = 13
    static let labelGap: CGFloat = 4
    /// The label may be this much wider than its icon.
    static let labelExtraWidth: CGFloat = 22
    static let labelShadowOpacity: Double = 0.35
    static let labelShadowRadius: CGFloat = 1.5
    static let labelShadowY: CGFloat = 0.5
    static let newDotSize: CGFloat = 7
    static let newDotGap: CGFloat = 4

    // MARK: Dock

    /// Apps the user can pin. Settings takes the last of the four places.
    static let dockApps = 3
    /// From the screen's edges, sides and bottom alike, which is what makes
    /// the dock concentric with the display.
    static let dockInset: CGFloat = 17
    static let dockPadding: CGFloat = 19.67
    static let dockIconGap: CGFloat = 24
    /// Used when the display's own corner radius can't be read.
    static let fallbackDisplayRadius: CGFloat = 55

    // MARK: Search pill

    static let pillSize = CGSize(width: 78.67, height: 29.33)
    static let pillGap: CGFloat = 20.33
    static let pillGlyphGap: CGFloat = 4
    static let pageDotSize: CGFloat = 7
    static let pageDotGap: CGFloat = 8
    static let pageDotDim: Double = 0.4

    // MARK: Search

    static let searchFieldHeight: CGFloat = 48
    static let searchSideInset: CGFloat = 16
    static let searchTopGap: CGFloat = 8
    static let searchDim: Double = 0.35
    static let searchPull: CGFloat = 60

    // MARK: Edit mode and banner

    static let editButtonInset: CGFloat = 16
    static let jiggleAngle: Double = 1.6
    static let jiggleShift: CGFloat = 0.6
    /// How close to a screen edge a dragged icon flips the page.
    static let pageFlipEdge: CGFloat = 28
    static let bannerTopGap: CGFloat = 4
    static let bannerPadding = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 18)
    static let bannerSpacing: CGFloat = 8
    static let shakeDistance: CGFloat = 8

    // MARK: Hit targets

    static let minimumHit: CGFloat = 44
}

/// Where everything sits on one particular screen.
struct HomeGeometry: Equatable {
    /// The whole screen, safe areas included.
    var size: CGSize
    var safeTop: CGFloat
    var displayRadius: CGFloat
    /// The height one line of label text takes at the current text size.
    var labelHeight: CGFloat

    var scale: CGFloat { size.width / HomeMetrics.referenceWidth }
    var iconSize: CGFloat { (HomeMetrics.iconSize * scale).rounded() }
    var iconRadius: CGFloat { iconSize * HomeMetrics.iconCornerRatio }
    var sideInset: CGFloat { HomeMetrics.sideInset * scale }
    var columnPitch: CGFloat {
        (size.width - 2 * sideInset - iconSize) / CGFloat(HomeMetrics.columns - 1)
    }
    var labelWidth: CGFloat { min(iconSize + HomeMetrics.labelExtraWidth * scale, columnPitch - 2) }
    var cellHeight: CGFloat { iconSize + HomeMetrics.labelGap + labelHeight }

    // MARK: Dock and pill

    var dockInset: CGFloat { HomeMetrics.dockInset * scale }
    var dockPadding: CGFloat { HomeMetrics.dockPadding * scale }
    var dockFrame: CGRect {
        let height = iconSize + 2 * dockPadding
        return CGRect(x: dockInset, y: size.height - dockInset - height,
                      width: size.width - 2 * dockInset, height: height)
    }
    /// Concentric with the display: its radius, less the inset.
    var dockRadius: CGFloat { max(displayRadius - dockInset, iconRadius + dockPadding) }
    var dockIconPitch: CGFloat { iconSize + HomeMetrics.dockIconGap * scale }

    var pillFrame: CGRect {
        let s = HomeMetrics.pillSize
        return CGRect(x: (size.width - s.width) / 2, y: dockFrame.minY - HomeMetrics.pillGap * scale - s.height,
                      width: s.width, height: s.height)
    }

    /// The x of each dock icon's centre when the dock holds `count` icons.
    func dockCenter(_ index: Int, of count: Int) -> CGPoint {
        let span = CGFloat(max(count - 1, 0)) * dockIconPitch
        return CGPoint(x: size.width / 2 - span / 2 + CGFloat(index) * dockIconPitch, y: dockFrame.midY)
    }

    /// The dock slot nearest `x`, when the dock would hold `count` icons.
    func dockIndex(at x: CGFloat, of count: Int) -> Int {
        guard count > 1 else { return 0 }
        let first = dockCenter(0, of: count).x
        return min(max(Int(((x - first) / dockIconPitch).rounded()), 0), count - 1)
    }

    // MARK: Grid

    var gridTop: CGFloat { safeTop + HomeMetrics.topInset * scale }
    var gridBottom: CGFloat { pillFrame.minY - HomeMetrics.gridBottomGap * scale }
    /// Rows share the height between the status bar and the pill evenly, as
    /// Springboard's do, rather than sitting a fixed distance apart.
    var rowPitch: CGFloat {
        (gridBottom - gridTop - cellHeight) / CGFloat(HomeMetrics.rows - 1)
    }

    /// The centre of the icon (not the cell) at `index` on its page.
    func iconCenter(_ index: Int) -> CGPoint {
        let column = index % HomeMetrics.columns
        let row = index / HomeMetrics.columns
        return CGPoint(x: sideInset + iconSize / 2 + CGFloat(column) * columnPitch,
                       y: gridTop + iconSize / 2 + CGFloat(row) * rowPitch)
    }

    /// The grid slot nearest a point on a page, clamped to `count` slots.
    func gridIndex(at point: CGPoint, count: Int) -> Int {
        let column = min(max(Int(((point.x - sideInset - iconSize / 2) / columnPitch).rounded()), 0), HomeMetrics.columns - 1)
        let row = min(max(Int(((point.y - gridTop - iconSize / 2) / rowPitch).rounded()), 0), HomeMetrics.rows - 1)
        return min(row * HomeMetrics.columns + column, max(count, 0))
    }
}
