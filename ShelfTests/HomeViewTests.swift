import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// The UIKit Home Screen (PLAN.md §0.2): its icons, its rules for drops,
/// pages and menus, and the measurements it is drawn to.
@MainActor
@Suite struct HomeViewTests {
    private let geometry = HomeGeometry(size: CGSize(width: 402, height: 874), safeTop: 62, displayRadius: 55, labelHeight: 14.3)

    // MARK: Icon tone

    /// Unset, icons follow the system's light and dark; set, they hold the
    /// tone whatever the system does (§0.5 sets it from Settings).
    @Test func iconToneFollowsTheSystemUnlessSet() {
        let dark = UITraitCollection(userInterfaceStyle: .dark)
        #expect(dark.iconTone == .dark)
        #expect(UITraitCollection(userInterfaceStyle: .light).iconTone == .light)
        let held = dark.modifyingTraits { $0.iconTone = .light }
        #expect(held.iconTone == .light)
    }

    /// Light icons are the tint with a white glyph; dark ones are the
    /// system's near-black with the glyph in the tint.
    @Test func thePaletteFollowsTheTone() {
        let face = IconFace(symbol: "drop.fill", tint: .teal)
        let light = IconPalette(face, tone: .light)
        let dark = IconPalette(face, tone: .dark)
        #expect(light.glyph == nil)
        #expect(dark.glyph != nil)
        #expect(light.bottom != dark.bottom)
        #expect(IconPalette(face, tone: .dark) == dark)
    }

    // MARK: The outline

    /// The icon's outline against Springboard's, measured the same way on
    /// both (the left edge's inset on pixel rows of a 64 pt icon at 3x, over
    /// black, at a threshold of 40): Calendar's tile in `home-page1-light.png`
    /// reads 47, 35, 29, 21, 16, 11, 7, 3, 1. Core Animation's own
    /// continuous corner reads 52, 36, 30, 22, 17, 11, 7, 4, 2.
    @Test func theOutlineIsSpringboards() throws {
        let side = 64 * 3
        let space = CGColorSpaceCreateDeviceGray()
        let context = try #require(CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side,
                                             space: space, bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 1, alpha: 1)
        let path = IconPath.path(CGRect(x: 0, y: 0, width: side, height: side), radius: HomeMetrics.iconRadius(CGFloat(side)))
        context.addPath(path)
        context.fillPath()
        let pixels = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        // Rows counted from the top; Core Graphics counts from the bottom.
        func inset(_ row: Int) -> Int {
            let y = side - 1 - row
            return (0..<side).first { pixels[y * side + $0] > 40 } ?? side
        }
        let springboard = [0: 47, 2: 35, 4: 29, 8: 21, 12: 16, 18: 11, 24: 7, 32: 3, 40: 1]
        for (row, expected) in springboard {
            #expect(abs(inset(row) - expected) <= 1, "row \(row): \(inset(row)), Springboard \(expected)")
        }
    }

    // MARK: Drops and pages

    @Test func aDropOverTheDockTakesAPlaceThere() {
        var layout = Layout(dock: ["a", Layout.settings], pages: [["b", "c"]])
        let dock = geometry.dockFrame
        let left = CGPoint(x: dock.minX + 10, y: dock.midY)
        #expect(geometry.dropSlot(for: "b", at: left, page: 0, in: layout) == .dock(index: 0))
        // A full dock refuses a newcomer, but not one of its own.
        layout.dock = ["a", "d", "e", Layout.settings]
        #expect(geometry.dropSlot(for: "b", at: left, page: 0, in: layout) == nil)
        #expect(geometry.dropSlot(for: "a", at: CGPoint(x: dock.maxX - 10, y: dock.midY), page: 0, in: layout) == .dock(index: 3))
    }

    /// Over the grid, the nearest place on the page in view, never past the
    /// icons already there.
    @Test func aDropOverTheGridTakesTheNearestPlace() {
        let layout = Layout(dock: [], pages: [["a", "b", "c"], ["d"]])
        #expect(geometry.dropSlot(for: "a", at: geometry.iconCenter(1), page: 0, in: layout) == .page(0, index: 1))
        #expect(geometry.dropSlot(for: "a", at: geometry.iconCenter(20), page: 0, in: layout) == .page(0, index: 2))
        #expect(geometry.dropSlot(for: "a", at: geometry.iconCenter(20), page: 1, in: layout) == .page(1, index: 1))
        // Edit mode's spare page.
        #expect(geometry.dropSlot(for: "a", at: geometry.iconCenter(5), page: 2, in: layout) == .page(2, index: 0))
    }

    @Test func holdingAtAnEdgeAsksForTheNextPage() {
        #expect(geometry.flipTarget(at: 10, page: 1, pageCount: 3) == 0)
        #expect(geometry.flipTarget(at: 395, page: 1, pageCount: 3) == 2)
        #expect(geometry.flipTarget(at: 200, page: 1, pageCount: 3) == nil)
        // Nothing past the first or the last page.
        #expect(geometry.flipTarget(at: 10, page: 0, pageCount: 3) == nil)
        #expect(geometry.flipTarget(at: 395, page: 2, pageCount: 3) == nil)
    }

    // MARK: The menu

    /// Below a grid icon with their leading edges in line; against the
    /// icon's trailing edge when that would run off the screen; above a dock
    /// icon, listed the other way.
    @Test func theMenuOpensBesideItsIcon() {
        let area = CGRect(x: 0, y: 62, width: 402, height: 874 - 62 - 34)
        let size = CGSize(width: HomeMetrics.menuWidth, height: 230)
        let photos = CGRect(x: 118, y: 286, width: 73.3, height: 73.3)
        let below = IconMenuView.placement(size: size, icon: photos, area: area)
        #expect(!below.upward)
        #expect(below.frame.minX == photos.minX)
        #expect(abs(below.frame.minY - (photos.maxY + HomeMetrics.menuGap)) < 0.01)

        let right = CGRect(x: 303, y: 286, width: 73.3, height: 73.3)
        #expect(IconMenuView.placement(size: size, icon: right, area: area).frame.maxX == right.maxX)

        let dock = CGRect(x: 120, y: 768, width: 73.3, height: 73.3)
        let above = IconMenuView.placement(size: CGSize(width: HomeMetrics.menuWidth, height: 104), icon: dock, area: area)
        #expect(above.upward)
        #expect(abs(above.frame.maxY - (dock.minY - HomeMetrics.menuGap)) < 0.01)
    }

    /// Settings' menu is Edit Home Screen alone; an app's has its own
    /// actions first.
    @Test func settingsMenuIsEditHomeScreenAlone() {
        let library = LibraryStore(demo: [], cache: AppCache(root: temporaryFolder()))
        let model = HomeModel()
        let groups = HomeItem.settings.menu(model: model, library: library)
        #expect(groups.map { $0.map(\.title) } == [["Edit Home Screen"]])
        groups[0][0].perform()
        #expect(model.isEditing)

        let app = CachedApp(meta: AppMeta(slug: "a", name: "A", revertible: true), cachedVersion: nil)
        let appGroups = HomeItem.app(app).menu(model: HomeModel(), library: library)
        #expect(appGroups.count == 2)
        #expect(appGroups[0].map(\.title) == ["Change…", "Reload App", "Copy Source", "Revert"])
        #expect(appGroups[0][2].isEnabled == false)
    }

    // MARK: The jiggle

    /// One repeating Core Animation animation per icon, on the layer the
    /// lift doesn't use, each icon starting at its own moment; nothing for
    /// the main thread to do per frame.
    @Test func theJiggleIsARepeatingAnimationOfItsOwn() throws {
        let icons = (0..<8).map { _ in IconView(item: .settings, iconSize: 64) }
        for icon in icons { icon.setJiggling(true) }
        let animations = try icons.map { try #require($0.jiggleLayer.animation(forKey: IconView.jiggleKey)) }
        #expect(animations.allSatisfy { $0.repeatCount == .infinity })
        #expect(Set(animations.map(\.beginTime)).count > 1)
        #expect(icons.allSatisfy { $0.layer.animation(forKey: IconView.jiggleKey) == nil })
        for icon in icons { icon.setJiggling(false) }
        #expect(icons.allSatisfy { $0.jiggleLayer.animation(forKey: IconView.jiggleKey) == nil })
    }

    // MARK: The Home Screen

    private func home(_ slugs: [String], dock: [String]) throws -> (HomeView, HomeModel, LibraryStore, UIWindow) {
        let cache = AppCache(root: temporaryFolder())
        let apps = slugs.map { CachedApp(meta: AppMeta(slug: $0, name: $0.capitalized, version: "1"), cachedVersion: "1") }
        let library = LibraryStore(demo: apps, dock: dock, cache: cache)
        let model = HomeModel()
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: geometry.size)
        let root = UIViewController()
        window.rootViewController = root
        window.isHidden = false
        let overlay = HomeOverlay()
        let view = HomeView(model: model, library: library, overlay: overlay)
        view.frame = root.view.bounds
        overlay.frame = root.view.bounds
        root.view.addSubview(view)
        root.view.addSubview(overlay)
        view.geometry = geometry
        settle(view)
        return (view, model, library, window)
    }

    private func settle(_ view: UIView) {
        for _ in 0..<3 {
            view.updatePropertiesIfNeeded()
            view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Every icon in the layout is a view at the exact point the layout
    /// gives it: what a card opens from and lands on.
    @Test func everyIconIsWhereTheLayoutPutsIt() throws {
        let slugs = (0..<26).map { "app\($0)" }
        let (view, _, library, window) = try home(slugs, dock: ["app0"])
        defer { window.isHidden = true }
        for id in library.layout.dock + library.layout.pages.joined() {
            let icon = try #require(view.iconView(id))
            let frame = try #require(view.iconFrame(for: id))
            let slot = try #require(library.layout.slot(of: id))
            #expect(frame == geometry.iconFrame(at: slot, dockCount: library.layout.dock.count, page: 0))
            let art = icon.artFrame(in: view)
            #expect(abs(art.minX - frame.minX) < 0.01 && abs(art.minY - frame.minY) < 0.01 && art.size == frame.size)
        }
        // Page 2's first icon is a page's width off to the right.
        let next = try #require(library.layout.pages[1].first)
        #expect(try #require(view.iconFrame(for: next)).minX > geometry.size.width)
    }

    /// In edit mode every icon jiggles, and every one but Settings has its
    /// minus badge.
    @Test func editModeJigglesAndBadgesAllButSettings() throws {
        let (view, model, library, window) = try home(["a", "b"], dock: ["a"])
        defer { window.isHidden = true }
        model.startEditing()
        settle(view)
        for id in library.layout.dock + library.layout.pages.joined() {
            let icon = try #require(view.iconView(id))
            #expect(icon.isJiggling)
            #expect(icon.showsMinusBadge == (id != Layout.settings))
        }
        model.stopEditing()
        settle(view)
        #expect(try #require(view.iconView("a")).isJiggling == false)
    }
}
