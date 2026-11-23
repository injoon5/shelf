import SwiftUI
import UIKit

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
    /// The pie keeps a ring's width clear inside the ring.
    static var pieInset: CGFloat { pieRingWidth * 2 }

    // MARK: Label

    /// The Home Screen's icons and edit buttons stop growing here, as
    /// Springboard's do, so the grid never breaks. The empty library, "No
    /// Results" and the banner follow `ShelfMetrics.textSizeCap` instead.
    static let textSizeCap = DynamicTypeSize.xLarge

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

    /// The black that tints the Home Screen's glass in dark mode
    /// (`HomeGlass`).
    static let darkGlassTint = UIColor.black.withAlphaComponent(0.45)

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
    /// Room either side of the dots when there are enough to widen the pill.
    static let pillDotsPadding: CGFloat = 7.33

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

    // MARK: Wallpaper

    /// How far the gradient's middle points stray from their places, as a
    /// fraction of the screen.
    static let wallpaperReach: Float = 0.12

    // MARK: Edit mode and banner

    /// Springboard's two edit-mode buttons, measured: glass capsules 36 pt in
    /// from the sides, 19 pt from the top, where the hidden status bar was.
    static let editButtonSize = CGSize(width: 66, height: 28)
    static let editButtonInset: CGFloat = 36
    static let editButtonTop: CGFloat = 19
    static let jiggleAngle: Double = 1.6
    static let jiggleShift: CGFloat = 0.6
    /// Springboard's minus badge, measured in edit mode: a 27 pt grey disc
    /// whose centre is 3.67 pt in from the icon's top-left corner, with a
    /// dark dash 11.67 × 2 pt.
    static let badgeSize: CGFloat = 27
    static let badgeInset: CGFloat = 3.67
    static let badgeFill = UIColor(red: 149 / 255, green: 148 / 255, blue: 148 / 255, alpha: 1)
    static let badgeDash = CGSize(width: 11.67, height: 2)
    /// How close to a screen edge a dragged icon flips the page.
    static let pageFlipEdge: CGFloat = 28
    static let bannerTopGap: CGFloat = 4
    static let bannerPadding = EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 18)
    static let shakeDistance: CGFloat = 8

    // MARK: Long press

    /// The icon under a long press, measured from `longpress-menu-grid-
    /// photos.png`: 73.3 pt across for a 64 pt icon, about its own centre.
    static let liftScale: CGFloat = 1.146
    /// Everything but the lifted icon and its menu goes to 80% (255 to 204,
    /// 62 to 50 in the capture).
    static let liftDim: CGFloat = 0.2
    /// How far a finger can stray before a press stops being a tap or a
    /// hold, and how far it moves under a lifted icon before it is a drag.
    static let touchSlop: CGFloat = 10

    // MARK: Menu

    /// Springboard's quick-action menu, measured in the same capture: 250 pt
    /// wide, 8.33 pt from the lifted icon, its edge in line with the icon's,
    /// 42 pt rows (the glyph's centre 40.3 pt in, the text 64.7 pt in), and
    /// about 10 pt above the first row and below the last.
    static let menuWidth: CGFloat = 250
    static let menuGap: CGFloat = 8.33
    static let menuRowHeight: CGFloat = 42
    static let menuPadding: CGFloat = 10
    static let menuGlyphCenter: CGFloat = 40.33
    static let menuTextStart: CGFloat = 64.67
    static let menuTrailing: CGFloat = 20
    static let menuCornerRadius: CGFloat = 26
    /// A thin line between groups of actions.
    static let menuSectionGap: CGFloat = 8
    /// The menu keeps this far from the screen's sides.
    static let menuMargin: CGFloat = 16

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

    /// Where the icon at `slot` is drawn while `page` is in view and the
    /// dock holds `dockCount`: an icon on another page is a whole page's
    /// width off to that side. What a card lands on when no view has
    /// reported the icon's frame, as happens for pages out of view.
    func iconFrame(at slot: Layout.Slot, dockCount: Int, page: Int) -> CGRect {
        let center = switch slot {
        case .dock(let index):
            dockCenter(index, of: dockCount)
        case .page(let p, let index):
            iconCenter(index).applying(.init(translationX: CGFloat(p - page) * size.width, y: 0))
        }
        return CGRect(x: center.x - iconSize / 2, y: center.y - iconSize / 2, width: iconSize, height: iconSize)
    }

    /// The grid slot nearest a point on a page, clamped to `count` slots.
    func gridIndex(at point: CGPoint, count: Int) -> Int {
        let column = min(max(Int(((point.x - sideInset - iconSize / 2) / columnPitch).rounded()), 0), Layout.columns - 1)
        let row = min(max(Int(((point.y - gridTop - iconSize / 2) / rowPitch).rounded()), 0), Layout.rows - 1)
        return min(row * Layout.columns + column, max(count, 0))
    }
}

extension HomeGeometry {
    /// Where an icon carried with its artwork's centre at `point` (on
    /// screen) would go, with `page` in view: a place in the dock while it is
    /// over the dock, or the nearest place on the page, never past the last
    /// icon there. Nil over a full dock that it isn't already in: the dock
    /// refuses a newcomer, and the icon keeps the place it had.
    func dropSlot(for id: String, at point: CGPoint, page: Int, in layout: Layout) -> Layout.Slot? {
        if dockFrame.contains(point) {
            guard layout.dockHasRoom(for: id) else { return nil }
            let count = layout.dock.contains(id) ? layout.dock.count : layout.dock.count + 1
            return .dock(index: dockIndex(at: point.x, of: count))
        }
        let others = page < layout.pages.count ? layout.pages[page].filter { $0 != id }.count : 0
        return .page(page, index: gridIndex(at: point, count: others))
    }

    /// Which way, if any, a carried icon at `x` asks the pages to turn:
    /// held within `pageFlipEdge` of a side that has a page beyond it.
    func flipTarget(at x: CGFloat, page: Int, pageCount: Int) -> Int? {
        if x < HomeMetrics.pageFlipEdge, page > 0 { return page - 1 }
        if x > size.width - HomeMetrics.pageFlipEdge, page < pageCount - 1 { return page + 1 }
        return nil
    }
}
