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

    static let iconSize: CGFloat = 64
    /// From the screen edge to the first column.
    static let sideInset: CGFloat = 30.33
    /// From the bottom of the status bar to the first row.
    static let topInset: CGFloat = 28
    /// From the last row's label to the search pill.
    static let gridBottomGap: CGFloat = 28

    // MARK: Icon

    /// The icon's corner, as a fraction of its side. A continuous corner of
    /// 26% traces Springboard's iOS 27 icon outline (`design/reference/
    /// README.md`, "Icon corners") to within a fifth of a pixel on every row
    /// at 3x when rendered alone, and within half a pixel on screen; the
    /// 22.37% of iOS 18 and earlier is up to 6.6 pixels tighter.
    static let iconCornerRatio: CGFloat = 0.26

    /// The icon's corner at `size`. Everything that draws, clips or moves
    /// to an icon uses this, so no state can show two different corners.
    static func iconRadius(_ size: CGFloat) -> CGFloat {
        size * iconCornerRatio
    }

    static func iconShape(_ size: CGFloat) -> RoundedRectangle {
        RoundedRectangle(cornerRadius: iconRadius(size), style: .continuous)
    }

    static let glyphRatio: CGFloat = 0.5
    /// How far the top of the fill is lightened toward white. Measured on
    /// Messages, whose top is its bottom colour about a quarter of the way to white.
    static let fillLift: Double = 0.24
    /// The glyph's bottom, against its white top: a little of the depth
    /// iOS 27's icon glyphs have.
    static let glyphShade: Double = 0.88
    static let darkFillTop = Color(red: 0.173, green: 0.173, blue: 0.180)
    static let darkFillBottom = Color(red: 0.110, green: 0.110, blue: 0.118)
    static let rimWidth: CGFloat = 0.5
    /// The rim's brightness at the top edge, and the fainter return at the bottom.
    static let rimOpacity: Double = 0.4
    static let rimReturnOpacity: Double = 0.12
    /// Touch-down lays black this strong over the whole tile, glyph included,
    /// and never scales it. On screen that leaves the tile at about 59% of its
    /// brightness, as Springboard's (measured frame by frame on both).
    static let pressedDim: Double = 0.37
    static let pendingDim: Double = 0.35
    static let pieRatio: CGFloat = 0.5
    static let pieRingWidth: CGFloat = 2

    // MARK: Label

    /// Springboard's labels are 12 pt medium: measured by ink width and stem
    /// weight against SF Pro rendered at 12 and 13 pt.
    static let labelSize: CGFloat = 12
    /// Puts the label's baseline 16.3 pt below the icon, as measured.
    static let labelGap: CGFloat = 5
    /// The label may be this much wider than its icon.
    static let labelExtraWidth: CGFloat = 22
    static let labelShadowOpacity: Double = 0.35
    static let labelShadowRadius: CGFloat = 1.5
    static let labelShadowY: CGFloat = 0.5
    static let newDotSize: CGFloat = 7
    static let newDotGap: CGFloat = 4

    // MARK: Glass

    /// The one glass the Home Screen is made of: the dock, the search pill,
    /// the search field, the edit-mode buttons and Clear icons. One
    /// definition, so they always match each other and Springboard's.
    ///
    /// Springboard's dock and pill let the wallpaper through with only a
    /// light frost: over black they are 32 of 255 in light mode and 17 in
    /// dark, with a bright hairline at the edge. `.regular` turns into a pale
    /// grey slab over a dark photo (134 over black); `.clear` measures 32 with
    /// the same hairline, and a black tint takes it to Springboard's 17 in
    /// dark mode.
    static func glass(_ scheme: ColorScheme) -> Glass {
        scheme == .dark ? .clear.tint(darkGlassTint) : .clear
    }

    static let darkGlassTint = Color.black.opacity(0.45)

    // MARK: Dock

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
    static let pillGlyphGap: CGFloat = 3.33
    /// "Search" and its glyph: measured over black, Springboard's text is
    /// 189 of 255 on a 32 glass, which is white at 70%.
    static let pillTextOpacity: Double = 0.7
    /// Springboard's dots, measured in edit mode: 6.67 pt on a 14 pt pitch,
    /// the other pages' at 45% white.
    static let pageDotSize: CGFloat = 6.67
    static let pageDotGap: CGFloat = 7.33
    static let pageDotDim: Double = 0.45

    // MARK: Search

    /// The field the pill turns into sits where iOS 27 puts it: just above
    /// the keyboard, with the results above it.
    static let searchFieldHeight: CGFloat = 48
    static let searchSideInset: CGFloat = 16
    /// Between the field and the top of the keyboard.
    static let searchKeyboardGap: CGFloat = 8
    /// Between the last row of results and the field.
    static let searchResultsGap: CGFloat = 8
    /// Between the magnifier and "Search", at the field's size.
    static let searchGlyphGap: CGFloat = 6
    /// Room kept at the field's trailing end for the clear button.
    static let searchTextTrailing: CGFloat = 6
    /// The placeholder, in the field. (In the pill it is `pillTextOpacity`.)
    static let searchPlaceholderOpacity: Double = 0.6
    static let searchDim: Double = 0.35
    /// Above this average brightness, the wallpaper behind the search field
    /// counts as light, and the field's text turns dark.
    static let brightBackdrop: Double = 0.55
    /// A pull down on the Home Screen this long takes the pill all the way
    /// to the field.
    static let searchPullDistance: CGFloat = 150
    /// A pull let go of past this much of the warp opens search...
    static let searchOpenProgress: CGFloat = 0.4
    /// ...as does one let go of moving down faster than this (pt/s). One
    /// moving up this fast goes back to the pill wherever it is.
    static let searchOpenVelocity: CGFloat = 400
    /// Pulling the results down this far past their top closes search.
    static let searchPull: CGFloat = 60

    // MARK: Edit mode and banner

    /// Springboard's two edit-mode buttons, measured: glass capsules 36 pt in
    /// from the sides, 19 pt from the top, where the hidden status bar was.
    static let editButtonSize = CGSize(width: 66, height: 28)
    static let editButtonInset: CGFloat = 36
    static let editButtonTop: CGFloat = 19
    static let jiggleAngle: Double = 1.6
    static let jiggleShift: CGFloat = 0.6
    /// How close to a screen edge a dragged icon flips the page.
    static let pageFlipEdge: CGFloat = 28
    static let bannerTopGap: CGFloat = 4
    static let bannerPadding = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 18)
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
    var iconRadius: CGFloat { HomeMetrics.iconRadius(iconSize) }
    var sideInset: CGFloat { HomeMetrics.sideInset * scale }
    var columnPitch: CGFloat {
        (size.width - 2 * sideInset - iconSize) / CGFloat(Layout.columns - 1)
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
        (gridBottom - gridTop - cellHeight) / CGFloat(Layout.rows - 1)
    }

    /// The centre of the icon (not the cell) at `index` on its page.
    func iconCenter(_ index: Int) -> CGPoint {
        let column = index % Layout.columns
        let row = index / Layout.columns
        return CGPoint(x: sideInset + iconSize / 2 + CGFloat(column) * columnPitch,
                       y: gridTop + iconSize / 2 + CGFloat(row) * rowPitch)
    }

    /// The grid slot nearest a point on a page, clamped to `count` slots.
    func gridIndex(at point: CGPoint, count: Int) -> Int {
        let column = min(max(Int(((point.x - sideInset - iconSize / 2) / columnPitch).rounded()), 0), Layout.columns - 1)
        let row = min(max(Int(((point.y - gridTop - iconSize / 2) / rowPitch).rounded()), 0), Layout.rows - 1)
        return min(row * Layout.columns + column, max(count, 0))
    }
}
