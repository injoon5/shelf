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
    /// Icons whose artwork is hidden because their app's card stands in for
    /// them: open, or in flight. Their labels stay, as on Springboard.
    var cardIcons: Set<String> = []
    /// Where each icon's artwork is, in the stage's coordinates, as last laid
    /// out: what a card grows out of and lands on.
    @ObservationIgnored var iconFrames: [IconKey: CGRect] = [:]

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

    @ObservationIgnored private var liftedSlug: String?
    @ObservationIgnored private var flip: (target: Int, task: Task<Void, Never>)?
    @ObservationIgnored private var dotsTask: Task<Void, Never>?

    // MARK: Opening

    func open(_ slug: String, in library: LibraryStore) async {
        guard !isEditing, run == nil, let app = library.app(slug) else { return }
        if app.isRunnable, let source = library.source(for: slug) {
            launch(app, source: source, in: library)
        } else if await library.fetch(slug), let app = library.app(slug), let source = library.source(for: slug) {
            launch(app, source: source, in: library)
        } else {
            refusals[slug, default: 0] += 1
        }
    }

    private func launch(_ app: CachedApp, source: String, in library: LibraryStore) {
        guard run == nil else { return }
        launches += 1
        library.opened(app.slug)
        run = Run(app: app, source: source)
    }

    /// A card on its way home was caught and sent back to full screen.
    func reopen(_ again: Run) {
        guard run == nil else { return }
        launches += 1
        run = again
    }

    func close() {
        run = nil
    }

    /// Where a card should grow out of or land on for `slug`: the search
    /// result while searching, otherwise its dock or grid icon.
    func iconFrame(_ slug: String, preferResult: Bool) -> CGRect? {
        if preferResult, let frame = iconFrames[IconKey(slug: slug, place: .result)] { return frame }
        return iconFrames[IconKey(slug: slug, place: .dock)] ?? iconFrames[IconKey(slug: slug, place: .grid)]
    }

    // MARK: Edit mode

    func startEditing() {
        guard !isEditing else { return }
        editStarts += 1
        withAnimation(Motion.standard) {
            isEditing = true
            isSearching = false
        }
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
    /// Starting to drag an icon is one of the ways into edit mode.
    @discardableResult
    func dragMoved() -> String? {
        if dragging == nil, let liftedSlug {
            startEditing()
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
