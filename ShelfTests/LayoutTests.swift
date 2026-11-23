import Foundation
import Testing
@testable import Shelf

/// Springboard's rules for where icons go (PLAN.md §0.1, "Layout"), with
/// small pages and docks so every case fits on a line.
struct LayoutTests {
    private let page = 4
    private let dock = 2
    private let settings = Layout.settings

    // MARK: New apps

    @Test func newAppsFillTheLastPageThenStartAnother() {
        var layout = Layout()
        layout.reconcile(with: ["a", "b", "c", "d", "e"], pageSize: page)
        #expect(layout.pages == [["a", "b", "c", "d"], ["e"]])
        layout.reconcile(with: ["a", "b", "c", "d", "e", "f"], pageSize: page)
        #expect(layout.pages == [["a", "b", "c", "d"], ["e", "f"]])
    }

    /// Room on an earlier page doesn't matter: a new app goes after the last icon.
    @Test func aNewAppLandsOnTheLastPageEvenWithRoomEarlier() {
        var layout = Layout(dock: [settings], pages: [["a"], ["b", "c"]])
        layout.reconcile(with: ["a", "b", "c", "d"], pageSize: page)
        #expect(layout.pages == [["a"], ["b", "c", "d"]])
    }

    @Test func removedAndUnknownSlugsLeave() {
        var layout = Layout(dock: ["gone", "a", settings], pages: [["b", "ghost"], ["c"]])
        layout.reconcile(with: ["a", "b", "c"], pageSize: page)
        #expect(layout.dock == ["a", settings])
        #expect(layout.pages == [["b"], ["c"]])
    }

    @Test func aSlugNeverAppearsTwice() {
        var layout = Layout(dock: ["a", settings], pages: [["a", "b", "b", settings]])
        layout.reconcile(with: ["a", "b"], pageSize: page)
        #expect(layout.dock == ["a", settings])
        #expect(layout.pages == [["b"]])
    }

    @Test func anEmptyLibraryKeepsOnePageAndSettings() {
        var layout = Layout(dock: ["a", settings], pages: [["b"], ["c"]])
        layout.reconcile(with: [], pageSize: page)
        #expect(layout == Layout(dock: [settings], pages: [[]]))
    }

    /// A sync that empties a page takes the page away.
    @Test func aSyncThatEmptiesAPageRemovesIt() {
        var layout = Layout(dock: [settings], pages: [["a"], ["b"], ["c"]])
        layout.reconcile(with: ["a", "c"], pageSize: page)
        #expect(layout.pages == [["a"], ["c"]])
    }

    // MARK: Moving

    @Test func movingWithinAPageSlidesTheOthers() {
        var layout = Layout(pages: [["a", "b", "c", "d"]])
        let moved = layout.move("a", to: .page(0, index: 2), pageSize: page, dockSize: dock)
        #expect(moved)
        #expect(layout.pages == [["b", "c", "a", "d"]])
        #expect(layout.slot(of: "a") == .page(0, index: 2))
    }

    @Test func movingOntoAFullPagePushesItsLastIconOn() {
        var layout = Layout(pages: [["a", "b", "c", "d"], ["e"]])
        layout.move("e", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["e", "a", "b", "c"], ["d"]])
    }

    @Test func aSpillCascadesThroughFullPages() {
        var layout = Layout(pages: [["a", "b", "c", "d"], ["e", "f", "g", "h"], ["i"]])
        layout.move("i", to: .page(0, index: 1), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a", "i", "b", "c"], ["d", "e", "f", "g"], ["h"]])
    }

    /// The last page full too: the cascade starts a new page.
    @Test func aSpillOffTheLastPageStartsANewOne() {
        var layout = Layout(dock: ["x"], pages: [["a", "b", "c", "d"], ["e", "f", "g", "h"]])
        layout.move("x", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["x", "a", "b", "c"], ["d", "e", "f", "g"], ["h"]])
    }

    @Test func droppingOnTheSparePageCreatesIt() {
        var layout = Layout(pages: [["a", "b"]])
        layout.move("b", to: .page(1, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a"], ["b"]])
    }

    /// Dragging the only icon off the last page: the page goes, and edit
    /// mode's spare page takes its place, so nothing after it shifts.
    @Test func anEmptiedLastPageGoes() {
        var layout = Layout(pages: [["a"], ["b"]])
        layout.move("b", to: .page(0, index: 1), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a", "b"]])
    }

    /// Dragging the only icon off a page in the middle: the page stays,
    /// empty, until edit mode ends, so the pages after it don't shift under
    /// the finger. (Before, they did: the icon's next hover landed it back
    /// on a page of its own.)
    @Test func anEmptiedMiddlePageStaysUntilEditModeEnds() {
        var layout = Layout(pages: [["a"], ["x"], ["c"]])
        layout.move("x", to: .page(2, index: 1), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a"], [], ["c", "x"]])
        layout.move("x", to: .page(2, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["a"], [], ["x", "c"]])

        layout.removeEmptyPages()
        #expect(layout.pages == [["a"], ["x", "c"]])
    }

    @Test func anEmptiedPageFillsBackUpInACascade() {
        var layout = Layout(pages: [["a", "b", "c", "d"], ["x"], ["e"]])
        layout.move("x", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["x", "a", "b", "c"], ["d"], ["e"]])
    }

    @Test func outOfRangeIndexesAreClamped() {
        var layout = Layout(pages: [["a", "b"]])
        layout.move("a", to: .page(0, index: 99), pageSize: page, dockSize: dock)
        #expect(layout.pages == [["b", "a"]])
    }

    @Test func movingToWhereItAlreadyIsChangesNothing() {
        var layout = Layout(pages: [["a", "b"]])
        let same = layout.move("a", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(!same)
        let unknown = layout.move("zzz", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(!unknown)
    }

    // MARK: The dock

    @Test func pinningAndUnpinning() {
        var layout = Layout(pages: [["a", "b", "c"]])
        let moved1 = layout.move("b", to: .dock(index: 0), pageSize: page, dockSize: dock)
        #expect(moved1)
        let moved2 = layout.move("c", to: .dock(index: 0), pageSize: page, dockSize: dock)
        #expect(moved2)
        #expect(layout.dock == ["c", "b"])
        // The dock is full: a third app is refused and stays where it was.
        let moved3 = layout.move("a", to: .dock(index: 1), pageSize: page, dockSize: dock)
        #expect(!moved3)
        #expect(layout.pages == [["a"]])
        // Reordering inside a full dock is still allowed.
        let moved4 = layout.move("b", to: .dock(index: 0), pageSize: page, dockSize: dock)
        #expect(moved4)
        #expect(layout.dock == ["b", "c"])
        let moved5 = layout.move("c", to: .page(0, index: 0), pageSize: page, dockSize: dock)
        #expect(moved5)
        #expect(layout.dock == ["b"])
        #expect(layout.pages == [["c", "a"]])
    }

    /// Springboard's four places, Settings in one of them.
    @Test func theDockHoldsFourWithSettings() {
        #expect(Layout.dockSize == 4)
        var layout = Layout(dock: ["a", "b", "c", settings], pages: [["d"]])
        #expect(!layout.dockHasRoom(for: "d"))
        let moved6 = layout.move("d", to: .dock(index: 0))
        #expect(!moved6)
        #expect(layout.pages == [["d"]])
        // Taking Settings out makes room.
        let moved7 = layout.move(settings, to: .page(0, index: 0))
        #expect(moved7)
        let moved8 = layout.move("d", to: .dock(index: 3))
        #expect(moved8)
        #expect(layout.dock == ["a", "b", "c", "d"])
        #expect(layout.pages == [[settings]])
    }

    @Test func emptyingTheDockLeavesItEmpty() {
        var layout = Layout(dock: ["a"], pages: [["b"]])
        layout.move("a", to: .page(0, index: 1), pageSize: page, dockSize: dock)
        #expect(layout.dock.isEmpty)
        #expect(layout.pages == [["b", "a"]])
    }

    // MARK: Settings

    @Test func settingsStartsInTheDocksLastPlace() {
        var fresh = Layout()
        fresh.reconcile(with: ["a"], pageSize: page)
        #expect(fresh.dock == [settings])

        var pinned = Layout(dock: ["a", "b"], pages: [[]])
        pinned.reconcile(with: ["a", "b", "c"], pageSize: page)
        #expect(pinned.dock == ["a", "b", settings])
        #expect(pinned.pages == [["c"]])
    }

    @Test func settingsMovesLikeAnyIcon() {
        var layout = Layout(dock: ["a", settings], pages: [["b", "c"], ["d"]])
        let moved9 = layout.move(settings, to: .dock(index: 0))
        #expect(moved9)
        #expect(layout.dock == [settings, "a"])
        let moved10 = layout.move(settings, to: .page(1, index: 0))
        #expect(moved10)
        #expect(layout.dock == ["a"])
        #expect(layout.pages == [["b", "c"], [settings, "d"]])
        // It stays where it was put through a sync.
        layout.reconcile(with: ["a", "b", "c", "d"], pageSize: page)
        #expect(layout.slot(of: settings) == .page(1, index: 0))
        #expect(layout.dock == ["a"])
    }

    @Test func reconcileAlwaysKeepsSettings() {
        var layout = Layout(dock: [], pages: [[settings, "a"]])
        layout.reconcile(with: [], pageSize: page)
        #expect(layout == Layout(dock: [], pages: [[settings]]))
    }

    /// The server can't send the reserved ID as a slug, but if it did, it
    /// still gives one Settings icon, not two.
    @Test func aSlugNamedLikeSettingsAddsNothing() {
        var layout = Layout()
        layout.reconcile(with: ["a", settings], pageSize: page)
        #expect(layout.dock == [settings])
        #expect(layout.pages == [["a"]])
    }

    @Test @MainActor func theReservedIDCanNeverBeASlug() {
        let create = CreateModel(app: nil, source: nil)
        create.slug = settings
        #expect(!create.isSlugValid)
        create.slug = "settings"
        #expect(create.isSlugValid)
    }

    @Test func settingsCantBeDeleted() {
        #expect(!Layout.isDeletable(settings))
        #expect(Layout.isDeletable("habits"))
        #expect(!HomeItem.settings.isDeletable)
    }

    /// A `layout.json` from before Settings was an icon.
    @Test func aV1LayoutGainsSettingsAtTheEndOfTheDock() throws {
        let v1 = Data(#"{"dock":["a","b","c"],"pages":[["d","e"]]}"#.utf8)
        var layout = try JSONDecoder().decode(Layout.self, from: v1)
        layout.reconcile(with: ["a", "b", "c", "d", "e"])
        #expect(layout.dock == ["a", "b", "c", settings])
        #expect(layout.pages == [["d", "e"]])
    }

    @Test func aFullDockPutsSettingsAtTheFrontOfTheFirstPage() {
        var layout = Layout(dock: ["a", "b"], pages: [["c", "d", "e", "f"], ["g"]])
        layout.reconcile(with: ["a", "b", "c", "d", "e", "f", "g"], pageSize: page, dockSize: dock)
        #expect(layout.dock == ["a", "b"])
        // The first page was full, so its last icon moves on, as a drop's would.
        #expect(layout.pages == [[settings, "c", "d", "e"], ["f", "g"]])
    }

    /// Only a damaged file has more in the dock than fits: the extras go to
    /// the front of the first page, after Settings.
    @Test func anOverfullDockSpillsOntoTheFirstPage() {
        var layout = Layout(dock: ["a", "b", "c"], pages: [["d"]])
        layout.reconcile(with: ["a", "b", "c", "d"], pageSize: page, dockSize: dock)
        #expect(layout.dock == ["a", "b"])
        #expect(layout.pages == [[settings, "c", "d"]])
    }

    @Test func aLayoutWithNoPagesGetsOne() throws {
        var layout = try JSONDecoder().decode(Layout.self, from: Data(#"{"dock":[],"pages":[]}"#.utf8))
        layout.reconcile(with: ["a"], pageSize: page)
        #expect(layout == Layout(dock: [settings], pages: [["a"]]))
    }

    // MARK: Geometry

    @Test func geometryRoundTripsSlots() {
        let geometry = HomeGeometry(size: .init(width: 402, height: 874), safeTop: 62, labelHeight: 16)
        for index in 0..<Layout.pageSize {
            #expect(geometry.gridIndex(at: geometry.iconCenter(index), count: Layout.pageSize) == index)
        }
        // A point past the last icon lands after it, not in an empty slot beyond.
        #expect(geometry.gridIndex(at: geometry.iconCenter(23), count: 5) == 5)
        #expect(geometry.iconSize == 64)
        #expect(abs(geometry.rowPitch - 100.33) < 1.5)
        for index in 0..<Layout.dockSize {
            #expect(geometry.dockIndex(at: geometry.dockCenter(index, of: Layout.dockSize).x, of: Layout.dockSize) == index)
        }
    }

    /// Four icons fit the dock as Springboard's do: the outer two the same
    /// distance in from its ends.
    @Test func fourDockIconsFitTheDock() {
        let geometry = HomeGeometry(size: .init(width: 402, height: 874), safeTop: 62, labelHeight: 16)
        let first = geometry.dockCenter(0, of: 4).x - geometry.iconSize / 2
        let last = geometry.dockCenter(3, of: 4).x + geometry.iconSize / 2
        #expect(first > geometry.dockFrame.minX)
        #expect(abs((first - geometry.dockFrame.minX) - (geometry.dockFrame.maxX - last)) < 0.01)
    }
}

/// When `layout.json` is written, and what a bad one does (§0.1, "Persistence").
@MainActor
@Suite struct LayoutPersistenceTests {
    private func relaunch(_ h: StoreHarness) -> LibraryStore {
        let api = h.library.server.api()
        return LibraryStore(cache: AppCache(root: h.folder.appending(path: "apps")),
                            data: AppData(root: h.folder.appending(path: "data"), api: { nil }),
                            layoutURL: h.folder.appending(path: "layout.json"),
                            server: { api },
                            appStorage: AppStorageKeys(UserDefaults(suiteName: h.suite)!))
    }

    private func saved(_ h: StoreHarness) -> Layout? {
        try? JSONDecoder().decode(Layout.self, from: Data(contentsOf: h.folder.appending(path: "layout.json")))
    }

    private func synced() async -> StoreHarness {
        let h = StoreHarness()
        for slug in ["a", "b", "c"] { h.library.put(slug, version: "1") }
        await h.store.sync()
        return h
    }

    /// A sync that changes the layout saves it.
    @Test func aSyncThatChangesTheLayoutSavesIt() async {
        let h = await synced()
        defer { h.cleanUp() }
        #expect(saved(h) == h.store.layout)
        #expect(saved(h)?.dock == [Layout.settings])
    }

    /// A drag moves icons many times a second; only a drop, leaving edit
    /// mode or leaving the foreground writes (`commitLayout`).
    @Test func movesWriteOnlyWhenCommitted() async {
        let h = await synced()
        defer { h.cleanUp() }
        let before = saved(h)
        h.store.move("c", to: .dock(index: 0))
        #expect(saved(h) == before)
        h.store.commitLayout()
        #expect(saved(h)?.dock == ["c", Layout.settings])
    }

    /// Leaving edit mode takes away the pages it emptied, and saves.
    @Test func finishingEditingDropsEmptyPagesAndSaves() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        for slug in (0..<26).map({ "app-\($0)" }) { h.library.put(slug, version: "1") }
        await h.store.sync()
        // 26 apps: a full page, and two on the second. Empty the second
        // into the dock: the spare page takes its place.
        h.store.move("app-24", to: .dock(index: 0))
        h.store.move("app-0", to: .page(1, index: 0))
        h.store.move("app-25", to: .dock(index: 0))
        #expect(h.store.layout.pages.count == 2)
        h.store.move("app-0", to: .page(0, index: 0))
        #expect(h.store.layout.pages.count == 1)

        h.store.move("app-1", to: .page(1, index: 0))
        h.store.move("app-2", to: .page(2, index: 0))
        h.store.move("app-1", to: .page(2, index: 0))
        #expect(h.store.layout.pages.map(\.count) == [22, 0, 2])
        h.store.finishEditing()
        #expect(h.store.layout.pages.map(\.count) == [22, 2])
        #expect(saved(h) == h.store.layout)
    }

    @Test func theLayoutSurvivesARelaunch() async {
        let h = await synced()
        defer { h.cleanUp() }
        h.store.move(Layout.settings, to: .page(0, index: 1))
        h.store.move("a", to: .dock(index: 0))
        h.store.commitLayout()
        let again = relaunch(h)
        #expect(again.layout == h.store.layout)
        #expect(again.layout.dock == ["a"])
        #expect(again.layout.slot(of: Layout.settings) == .page(0, index: 0))
    }

    /// A file that won't decode is as good as none: icons in library order,
    /// Settings in the dock. Nothing is lost but the arrangement.
    @Test func aCorruptLayoutFallsBackToTheDefault() async throws {
        let h = await synced()
        defer { h.cleanUp() }
        try Data("{not json".utf8).write(to: h.folder.appending(path: "layout.json"))
        let again = relaunch(h)
        #expect(again.layout == Layout(dock: [Layout.settings], pages: [["a", "b", "c"]]))
        again.commitLayout()
        #expect(saved(h) == again.layout)
    }

    /// Signed out there's no library, so nothing to save a layout for.
    @Test func signedOutNothingIsWritten() {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = LibraryStore(cache: AppCache(root: folder.appending(path: "apps")),
                                 data: AppData(root: folder.appending(path: "data"), api: { nil }),
                                 layoutURL: folder.appending(path: "layout.json"), server: { nil })
        store.commitLayout()
        #expect(!FileManager.default.fileExists(atPath: folder.appending(path: "layout.json").path(percentEncoded: false)))
    }
}
