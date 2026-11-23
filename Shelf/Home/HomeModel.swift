import SwiftUI
import Observation

/// The Home Screen's own state: what is open, whether icons are jiggling,
/// what is being dragged. The library itself lives in `LibraryStore`.
@MainActor
@Observable
final class HomeModel {
    /// An app that is open, with the source it was opened with.
    struct Run: Identifiable, Equatable {
        var app: CachedApp
        var source: String
        var id: String { app.slug }
    }

    enum Sheet: Identifiable, Equatable {
        case settings
        case newApp
        case change(CachedApp)

        var id: String {
            switch self {
            case .settings: "settings"
            case .newApp: "new"
            case .change(let app): "change-" + app.slug
            }
        }
    }

    /// The app that is open or opening. Its card (`AppCard`) may still be
    /// on screen after this is cleared, on its way back to its icon.
    var run: Run?
    var sheet: Sheet?

    private(set) var isEditing = false
    /// The icon under the finger during a drag. Its place in the grid is kept
    /// empty while the system's drag preview stands in for it.
    private(set) var dragging: String?

    var isSearching = false
    var query = ""

    var page = 0
    var scroll = ScrollPosition(x: 0)
    /// Dots stand in for the search pill while pages are moving.
    var showsPageDots = false

    // Haptic triggers. They only ever count up.
    private(set) var launches = 0
    private(set) var editStarts = 0
    private(set) var snaps = 0
    /// Per app: how many times it has refused to open. A change shakes its icon.
    private(set) var refusals: [String: Int] = [:]

    /// The pager's width, for scrolling to a page from here.
    @ObservationIgnored var pageWidth: CGFloat = 0
    @ObservationIgnored private var taps = 0
    @ObservationIgnored private var liftedSlug: String?
    @ObservationIgnored private var flip: (target: Int, task: Task<Void, Never>)?
    @ObservationIgnored private var dotsTask: Task<Void, Never>?

    // MARK: Opening

    /// A tap on an icon. An app opens as a card; one whose source isn't
    /// here downloads first, and opens only if nothing else was tapped
    /// meanwhile. Settings opens its sheet. Nothing opens in edit mode, or
    /// over an app that is already open.
    func open(_ id: String, in library: LibraryStore) async {
        guard !isEditing, run == nil else { return }
        taps += 1
        let tap = taps
        if id == Layout.settings {
            launches += 1
            // Opening anything from search closes search, as an app does.
            endSearch()
            sheet = .settings
            return
        }
        guard let app = library.app(id) else { return }
        if app.isRunnable, let source = library.source(for: id) {
            launch(app, source: source, in: library)
            return
        }
        let fetched = await library.fetch(id)
        // A later tap, edit mode or another app took over while it downloaded.
        guard tap == taps, !isEditing, run == nil else { return }
        if fetched, let app = library.app(id), let source = library.source(for: id) {
            launch(app, source: source, in: library)
        } else {
            refusals[id, default: 0] += 1
        }
    }

    private func launch(_ app: CachedApp, source: String, in library: LibraryStore) {
        guard run == nil else { return }
        launches += 1
        library.opened(app.slug)
        run = Run(app: app, source: source)
    }

    /// A card on its way home was caught and let go: it goes back to full
    /// screen. Returns false when it can't, and must land after all: its app
    /// has been deleted since, or another app has opened meanwhile.
    func reopen(_ again: Run, in library: LibraryStore) -> Bool {
        if run?.id == again.id { return true }
        guard run == nil, library.app(again.id) != nil else { return false }
        launches += 1
        run = again
        return true
    }

    func close() {
        run = nil
    }

    // MARK: Edit mode

    /// From an icon's menu. Edit mode and search never show together, so
    /// this closes search, as the menu of a search result can be opened there.
    func startEditing() {
        guard !isEditing else { return }
        editStarts += 1
        withAnimation(Motion.standard) {
            isEditing = true
            isSearching = false
        }
    }

    /// A long press on empty wallpaper. Search covers the wallpaper, so it
    /// can't be one while searching.
    func longPressedWallpaper() {
        guard !isSearching else { return }
        startEditing()
    }

    func stopEditing() {
        cancelFlip()
        liftedSlug = nil
        withAnimation(Motion.standard) {
            isEditing = false
            dragging = nil
        }
    }

    /// An icon was lifted. That isn't a drag yet: the system also asks for the
    /// drag item when it opens the icon's context menu, and most lifts end there.
    func lifted(_ slug: String) {
        liftedSlug = slug
    }

    /// The lifted icon has moved over a drop target, so it really is a drag.
    func dragMoved() -> String? {
        if dragging == nil, let liftedSlug {
            dragging = liftedSlug
        }
        return dragging
    }

    func endDrag() {
        cancelFlip()
        if dragging != nil { snaps += 1 }
        liftedSlug = nil
        withAnimation(Motion.reorder) { dragging = nil }
    }

    // MARK: Pages

    /// Flips to `target` if the dragged icon stays at the edge long enough.
    func holdAtEdge(toward target: Int, pageWidth: CGFloat) {
        if flip?.target == target { return }
        cancelFlip()
        let task = Task { [weak self] in
            try? await Task.sleep(for: Motion.pageFlipHold)
            guard !Task.isCancelled, let self else { return }
            self.flip = nil
            withAnimation(Motion.standard) { self.scroll.scrollTo(x: CGFloat(target) * pageWidth) }
        }
        flip = (target, task)
    }

    func cancelFlip() {
        flip?.task.cancel()
        flip = nil
    }

    /// How many pages there are to scroll through. While editing there is
    /// always an empty page at the end to drop onto, and a dot for it.
    func pageCount(_ pages: [[String]]) -> Int {
        let spare = isEditing && pages.last?.isEmpty == false
        return max(pages.count + (spare ? 1 : 0), 1)
    }

    /// The layout changed under the Home Screen: a sync, a drop, or the end
    /// of edit mode. The page on screen follows its icons, a drag whose icon
    /// has gone ends, and an app deleted while open closes (into the pill,
    /// as it has no icon to land on).
    func layoutChanged(from old: Layout, to new: Layout, in library: LibraryStore) {
        if let held = dragging ?? liftedSlug, new.slot(of: held) == nil {
            cancelFlip()
            liftedSlug = nil
            dragging = nil
        }
        if let run, library.app(run.id) == nil { close() }
        let target = Self.page(following: page, from: old.pages, to: new.pages, count: pageCount(new.pages))
        guard target != page else { return }
        page = target
        if pageWidth > 0 { scroll.scrollTo(x: CGFloat(target) * pageWidth) }
    }

    /// The page to show once the pages change from `old` to `new`: the one
    /// the icons on the page in view went to, so pages that go away before it
    /// don't change what is on screen. A page left with nothing that
    /// survived, and edit mode's spare page, keep their place where they
    /// can, or the last page.
    static func page(following page: Int, from old: [[String]], to new: [[String]], count: Int) -> Int {
        let last = max(count - 1, 0)
        if page < 0 { return 0 }
        // The spare page is the one after the last.
        if page >= old.count { return min(new.count, last) }
        for id in old[page] {
            if let moved = new.firstIndex(where: { $0.contains(id) }) { return min(moved, last) }
        }
        return min(page, last)
    }

    func pagesMoved(_ moving: Bool) {
        dotsTask?.cancel()
        if moving {
            withAnimation(Motion.fade) { showsPageDots = true }
        } else {
            dotsTask = Task { [weak self] in
                try? await Task.sleep(for: Motion.pageDotsStay)
                guard !Task.isCancelled else { return }
                withAnimation(Motion.fade) { self?.showsPageDots = false }
            }
        }
    }

    // MARK: Search

    // The stage (`SearchBar`) plays the warp; these only say where it goes.

    func beginSearch() {
        guard !isEditing, !isSearching else { return }
        query = ""
        isSearching = true
    }

    func endSearch() {
        isSearching = false
    }
}

/// Which copy of an icon: the Home Screen shows an app once on a page or in
/// the dock, and again among search results.
enum IconPlace: Hashable, Sendable {
    case grid, dock, result
}

struct IconKey: Hashable, Sendable {
    var slug: String
    var place: IconPlace
}

extension EnvironmentValues {
    @Entry var iconPlace = IconPlace.grid
}
