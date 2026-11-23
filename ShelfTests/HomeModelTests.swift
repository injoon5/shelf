import Foundation
import Testing
@testable import Shelf

/// Springboard's rules for what a tap, a long press, a sync or a search does
/// on the Home Screen (PLAN.md §0.1). The views read these; none of them is
/// decided in a view.
@MainActor
@Suite struct HomeModelTests {
    /// A demo library: every app runnable but "notes", nothing to fetch from.
    private func demo(_ slugs: [String] = ["habits", "notes", "todos"], dock: [String] = []) -> (LibraryStore, URL) {
        let folder = temporaryFolder()
        let cache = AppCache(root: folder)
        let apps = slugs.map { slug in
            CachedApp(meta: AppMeta(slug: slug, name: slug.capitalized, version: "1"),
                      cachedVersion: slug == "notes" ? nil : "1")
        }
        for app in apps where app.isRunnable { try? cache.writeSource("// \(app.slug)", for: app.slug) }
        return (LibraryStore(demo: apps, dock: dock, cache: cache), folder)
    }

    // MARK: Opening

    @Test func aTapOpensAnApp() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open("habits", in: library)
        #expect(model.run?.id == "habits")
    }

    /// The second tap of a double tap lands on an app that is already open.
    @Test func aDoubleTapOpensOnce() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open("habits", in: library)
        await model.open("habits", in: library)
        await model.open("todos", in: library)
        #expect(model.run?.id == "habits")
    }

    /// An app whose source never came, with no way to fetch it: its icon
    /// shakes, and nothing opens.
    @Test func aTapOnAnAppThatHasntDownloadedRefuses() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open("notes", in: library)
        #expect(model.run == nil)
        #expect(model.refusals["notes"] == 1)
    }

    @Test func nothingOpensInEditMode() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        model.startEditing()
        await model.open("habits", in: library)
        await model.open(Layout.settings, in: library)
        #expect(model.run == nil)
        #expect(model.sheet == nil)
    }

    /// A tap on an app that is still downloading, then on another that opens
    /// and closes: the first must not open by itself when its download ends.
    @Test func aDownloadThatALaterTapOvertookDoesntOpen() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("slow", version: "1")
        h.library.put("fast", version: "1")
        h.library.update { $0.failing = ["slow"] }
        await h.store.sync()
        #expect(h.store.app("slow")?.isRunnable == false)
        h.library.update {
            $0.failing = []
            $0.sourceDelay = .milliseconds(300)
        }

        let model = HomeModel()
        let first = Task { await model.open("slow", in: h.store) }
        #expect(await eventually { await h.store.downloading.contains("slow") })
        await model.open("fast", in: h.store)
        #expect(model.run?.id == "fast")
        model.close()
        await first.value
        #expect(model.run == nil)
        #expect(model.refusals["slow"] == nil)
    }

    @Test func aDownloadThatFinishesOpens() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("slow", version: "1")
        h.library.update { $0.failing = ["slow"] }
        await h.store.sync()
        h.library.update { $0.failing = [] }

        let model = HomeModel()
        await model.open("slow", in: h.store)
        #expect(model.run?.id == "slow")
    }

    // MARK: Settings

    /// Settings is an icon, but a tap opens its sheet, not a card.
    @Test func aTapOnSettingsOpensItsSheet() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open(Layout.settings, in: library)
        #expect(model.sheet == .settings)
        #expect(model.run == nil)
    }

    @Test func settingsFromSearchClosesSearch() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        model.beginSearch()
        model.query = "set"
        let best = library.items.matching(model.query).first
        #expect(best == .settings)
        await model.open(Layout.settings, in: library)
        #expect(model.sheet == .settings)
        #expect(!model.isSearching)
    }

    @Test func settingsIsAnItemWhereverItIs() {
        let (library, folder) = demo(dock: ["habits"])
        defer { try? FileManager.default.removeItem(at: folder) }
        #expect(library.layout.dock == ["habits", Layout.settings])
        #expect(library.item(Layout.settings) == .settings)
        #expect(library.item("habits")?.app?.slug == "habits")
        #expect(library.item("gone") == nil)
        #expect(library.items.contains(.settings))
    }

    // MARK: Search

    /// Names that start with the query, then names that contain it, each
    /// alphabetically; Settings among them, as Springboard's search finds it.
    @Test func searchOrder() {
        let (library, folder) = demo(["habits", "notes", "todos", "tip-jar", "reset", "mist"])
        defer { try? FileManager.default.removeItem(at: folder) }
        let names = { (query: String) in library.items.matching(query).map(\.name) }
        #expect(names("") == ["Habits", "Mist", "Notes", "Reset", "Settings", "Tip-Jar", "Todos"])
        #expect(names("t") == ["Tip-Jar", "Todos", "Habits", "Mist", "Notes", "Reset", "Settings"])
        #expect(names("set") == ["Settings", "Reset"])
        #expect(names("  SET ") == ["Settings", "Reset"])
        #expect(names("xyz").isEmpty)
    }

    @Test func searchDoesntOpenInEditMode() {
        let model = HomeModel()
        model.startEditing()
        model.beginSearch()
        #expect(!model.isSearching)
    }

    // MARK: Long press

    /// The menu's Edit Home Screen works from a search result: search closes
    /// and the icons jiggle.
    @Test func editModeFromSearchClosesSearch() {
        let model = HomeModel()
        model.beginSearch()
        model.startEditing()
        #expect(model.isEditing)
        #expect(!model.isSearching)
    }

    /// Search covers the wallpaper, so a long press there can't be meant for it.
    @Test func aLongPressOnTheWallpaperWhileSearchingDoesNothing() {
        let model = HomeModel()
        model.beginSearch()
        model.longPressedWallpaper()
        #expect(!model.isEditing)
        #expect(model.isSearching)

        model.endSearch()
        model.longPressedWallpaper()
        #expect(model.isEditing)
    }

    // MARK: Pages

    @Test func editModeAddsASparePage() {
        let model = HomeModel()
        #expect(model.pageCount([["a"], ["b"]]) == 2)
        model.startEditing()
        #expect(model.pageCount([["a"], ["b"]]) == 3)
        // A page already empty at the end is the spare.
        #expect(model.pageCount([["a"], []]) == 2)
        model.stopEditing()
        #expect(model.pageCount([[]]) == 1)
    }

    /// The spare page doesn't count the icon being carried: carried onto
    /// it, the icon doesn't make another one beyond it to flip to.
    @Test func aCarriedIconMakesNoSecondSparePage() {
        let model = HomeModel()
        model.startEditing()
        model.beginDrag("b")
        #expect(model.pageCount([["a"], ["b"]]) == 2)
        #expect(model.pageCount([["a", "b"]]) == 2)
        model.endDrag()
        #expect(model.pageCount([["a"], ["b"]]) == 3)
    }

    /// Relaunched, Shelf starts on the first page, as Springboard does after a restart.
    @Test func aRelaunchStartsOnTheFirstPage() {
        #expect(HomeModel().page == 0)
    }

    /// Following the page in view as pages come and go.
    @Test func thePageFollowsItsIcons() {
        let follow = { (page: Int, old: [[String]], new: [[String]], count: Int) in
            HomeModel.page(following: page, from: old, to: new, count: count)
        }
        // A sync empties a page before the one in view: its icons moved back one.
        #expect(follow(2, [["a"], ["b"], ["c"]], [["a"], ["c"]], 2) == 1)
        // Leaving edit mode drops an empty middle page.
        #expect(follow(2, [["a"], [], ["c"]], [["a"], ["c"]], 2) == 1)
        // The page in view itself emptied and went: the same place, or the last page.
        #expect(follow(1, [["a"], ["b"], ["c"]], [["a"], ["c"]], 2) == 1)
        #expect(follow(2, [["a"], ["b"], ["c"]], [["a"], ["b"]], 2) == 1)
        // On the spare page: it stays the spare while editing, else the last page.
        #expect(follow(2, [["a"], ["b"]], [["a"], ["b"], ["c"]], 4) == 3)
        #expect(follow(2, [["a"], ["b"]], [["a"], ["b"]], 2) == 1)
        // A drop that pushes icons on doesn't move the page in view.
        #expect(follow(0, [["a", "b"], ["c"]], [["x", "a"], ["b", "c"]], 3) == 0)
        // Rubber-banding past the first page.
        #expect(follow(-1, [["a"]], [["a"]], 1) == 0)
    }

    @Test func thePagerScrollsWhenThePageInViewMoves() {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        model.page = 2
        model.layoutChanged(from: Layout(pages: [["a"], ["b"], ["c"]]), to: Layout(pages: [["a"], ["c"]]), in: library)
        #expect(model.page == 1)
        // At once: the icons in view didn't move on screen, only their page did.
        #expect(model.pageRequest?.page == 1)
        #expect(model.pageRequest?.animated == false)
    }

    /// A carried icon held at a screen edge turns the page, animated, once
    /// it has stayed there long enough; leaving the edge first cancels it.
    @Test func holdingAtAnEdgeTurnsThePage() async throws {
        let model = HomeModel()
        model.holdAtEdge(toward: 1)
        model.cancelFlip()
        try await Task.sleep(for: Motion.pageFlipHold * 1.5)
        #expect(model.pageRequest == nil)

        model.holdAtEdge(toward: 1)
        #expect(await eventually { await model.pageRequest?.page == 1 })
        #expect(model.page == 1)
        #expect(model.pageRequest?.animated == true)
    }

    /// Each request is new, even to the page already asked for, so the
    /// pager can tell it from the last.
    @Test func pageRequestsAreEachNew() {
        let model = HomeModel()
        model.go(to: 1, animated: false)
        let first = model.pageRequest
        model.go(to: 1, animated: false)
        #expect(model.pageRequest != first)
    }

    // MARK: Syncs mid-gesture

    /// The dragged app was deleted elsewhere: the drag ends (the stage then
    /// lets go of the icon).
    @Test func aDragWhoseAppIsDeletedEnds() {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        model.startEditing()
        model.beginDrag("todos")
        #expect(model.dragging == "todos")
        model.layoutChanged(from: Layout(pages: [["habits", "todos"]]), to: Layout(pages: [["habits"]]), in: library)
        #expect(model.dragging == nil)
    }

    /// Another app added or deleted mid-drag: the drag goes on.
    @Test func aDragSurvivesOtherApps() {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        model.startEditing()
        model.beginDrag("todos")
        model.layoutChanged(from: Layout(pages: [["habits", "todos"]]), to: Layout(pages: [["todos", "new"]]), in: library)
        #expect(model.dragging == "todos")
    }

    /// Icons are carried only in edit mode (a drag from the long-press menu
    /// starts it first), and Done lets go of a carried icon.
    @Test func dragsHappenOnlyInEditMode() {
        let model = HomeModel()
        model.beginDrag("todos")
        #expect(model.dragging == nil)
        model.startEditing()
        model.beginDrag("todos")
        #expect(model.dragging == "todos")
        model.stopEditing()
        #expect(model.dragging == nil)
    }

    // MARK: Cards

    /// The open app was deleted elsewhere: its card closes (with no icon, it
    /// lands in the pill).
    @Test func anOpenAppDeletedElsewhereCloses() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open("habits", in: library)
        // The demo library can't sync, so stand in for a store that lost "habits".
        let (smaller, other) = demo(["notes", "todos"])
        defer { try? FileManager.default.removeItem(at: other) }
        model.layoutChanged(from: library.layout, to: smaller.layout, in: smaller)
        #expect(model.run == nil)
    }

    /// A card on its way home is caught and let go: it goes back to full
    /// screen, unless its app is gone or another app opened meanwhile.
    @Test func aCaughtCardReopensOnlyIfItCan() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open("habits", in: library)
        let habits = model.run!
        // Held from open and let go: still the open app.
        #expect(model.reopen(habits, in: library))
        model.close()
        #expect(model.reopen(habits, in: library))
        #expect(model.run?.id == "habits")

        // Closing, and another app tapped meanwhile.
        model.close()
        await model.open("todos", in: library)
        #expect(!model.reopen(habits, in: library))
        #expect(model.run?.id == "todos")

        // Closing, and deleted meanwhile.
        model.close()
        let (smaller, other) = demo(["notes", "todos"])
        defer { try? FileManager.default.removeItem(at: other) }
        #expect(!model.reopen(habits, in: smaller))
        #expect(model.run == nil)
    }

    /// While a card closes, another icon can be tapped: it opens.
    @Test func aTapWhileACardClosesOpensTheNewApp() async {
        let (library, folder) = demo()
        defer { try? FileManager.default.removeItem(at: folder) }
        let model = HomeModel()
        await model.open("habits", in: library)
        model.close()
        await model.open("todos", in: library)
        #expect(model.run?.id == "todos")
    }

    /// An icon on another page has nothing on screen to land on: the card
    /// leaves past that side. No icon at all: the pill.
    @Test func whereACardLands() {
        let pill = CGRect(x: 160, y: 700, width: 80, height: 30)
        let onScreen = CGRect(x: 30, y: 100, width: 64, height: 64)
        #expect(CardMotion.landing(icon: onScreen, screenWidth: 402, pill: pill, iconSize: 64) == (onScreen, false))
        let right = CardMotion.landing(icon: onScreen.offsetBy(dx: 402, dy: 0), screenWidth: 402, pill: pill, iconSize: 64)
        #expect(right.fades && right.frame.minX == 402 && right.frame.minY == 100)
        let left = CardMotion.landing(icon: onScreen.offsetBy(dx: -402, dy: 0), screenWidth: 402, pill: pill, iconSize: 64)
        #expect(left.fades && left.frame.maxX == 0)
        let none = CardMotion.landing(icon: nil, screenWidth: 402, pill: pill, iconSize: 64)
        #expect(none.fades && none.frame.midX == pill.midX && none.frame.midY == pill.midY)
    }

    /// An icon on a page out of view reports no frame, so the stage asks the
    /// layout. Opened from search and closed, a card for an app on page 2
    /// leaves past the right edge at its row. (It fell into the pill.)
    @Test func anIconOnAnotherPageHasAFrameOffToThatSide() {
        let geometry = HomeGeometry(size: .init(width: 402, height: 874), safeTop: 62, displayRadius: 62, labelHeight: 16)
        let home = geometry.iconFrame(at: .page(0, index: 5), dockCount: 4, page: 0)
        #expect(home.midX == geometry.iconCenter(5).x && home.midY == geometry.iconCenter(5).y)
        #expect(home.width == geometry.iconSize)

        let next = geometry.iconFrame(at: .page(1, index: 5), dockCount: 4, page: 0)
        #expect(next == home.offsetBy(dx: 402, dy: 0))
        let landing = CardMotion.landing(icon: next, screenWidth: 402, pill: geometry.pillFrame, iconSize: geometry.iconSize)
        #expect(landing.fades && landing.frame.minX == 402 && landing.frame.minY == home.minY)
        #expect(geometry.iconFrame(at: .page(0, index: 5), dockCount: 4, page: 1) == home.offsetBy(dx: -402, dy: 0))

        let dock = geometry.iconFrame(at: .dock(index: 3), dockCount: 4, page: 1)
        #expect(dock.midX == geometry.dockCenter(3, of: 4).x && dock.midY == geometry.dockFrame.midY)
    }
}
