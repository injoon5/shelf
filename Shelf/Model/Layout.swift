import Foundation

/// Where each icon sits. Saved as `layout.json`: `{ dock: [id], pages: [[id]] }`.
///
/// The layout holds slugs, and Shelf's own Settings under `Layout.settings`.
/// It is reconciled against the library after every sync, so it never shows
/// an app that is gone or misses one that is new, and Settings never leaves.
struct Layout: Codable, Equatable, Sendable {
    /// Springboard's grid: four columns of six rows to a page.
    static let columns = 4
    static let rows = 6
    static let pageSize = columns * rows
    /// Springboard's dock: four places, Settings' among them.
    static let dockSize = 4

    /// Settings' place in the layout. Slugs are letters, digits, hyphens and
    /// underscores (`CreateModel.isSlugValid`), so a colon can never be one.
    static let settings = ":settings"

    /// Whether the icon can be deleted. Every app can; Settings is Shelf's own.
    static func isDeletable(_ id: String) -> Bool {
        id != settings
    }

    var dock: [String] = []
    var pages: [[String]] = [[]]

    /// A position an icon can be dropped at.
    enum Slot: Equatable, Sendable {
        case page(Int, index: Int)
        case dock(index: Int)
    }

    /// Makes the layout hold exactly `slugs` and Settings: unknown ones leave,
    /// and new apps go into the first empty slot on the last page, as on iOS.
    ///
    /// A layout from before Settings was an icon (v1) gains it at the end of
    /// the dock. A dock that is already full (only a damaged file can have
    /// more than fits) puts Settings, and anything past its last place, at
    /// the front of the first page, pushing as a drop there would.
    mutating func reconcile(with slugs: [String], pageSize: Int = Layout.pageSize, dockSize: Int = Layout.dockSize) {
        let known = Set(slugs).union([Self.settings])
        var seen = Set<String>()
        func keep(_ id: String) -> Bool { known.contains(id) && seen.insert(id).inserted }
        dock = dock.filter(keep)
        pages = pages.map { $0.filter(keep) }

        var front = Array(dock.dropFirst(dockSize))
        dock = Array(dock.prefix(dockSize))
        if !seen.contains(Self.settings) {
            if dock.count < dockSize { dock.append(Self.settings) } else { front.insert(Self.settings, at: 0) }
        }
        if pages.isEmpty { pages = [[]] }
        for id in front.reversed() { insert(id, onPage: 0, at: 0, pageSize: pageSize) }

        for slug in slugs where !seen.contains(slug) && slug != Self.settings {
            seen.insert(slug)
            if pages.isEmpty || pages[pages.count - 1].count >= pageSize { pages.append([]) }
            pages[pages.count - 1].append(slug)
        }
        removeEmptyPages()
    }

    func slot(of id: String) -> Slot? {
        if let i = dock.firstIndex(of: id) { return .dock(index: i) }
        for (p, page) in pages.enumerated() {
            if let i = page.firstIndex(of: id) { return .page(p, index: i) }
        }
        return nil
    }

    /// Moves an icon to `slot`, sliding the others aside. A full dock refuses a
    /// newcomer; a full page pushes its last icon onto the next one.
    ///
    /// A page the icon leaves empty stays, as Springboard's does until edit
    /// mode ends (`removeEmptyPages`): pages never shift under a finger that
    /// is still dragging. Empty pages at the end go, since edit mode's spare
    /// page stands in for them.
    @discardableResult
    mutating func move(_ id: String, to slot: Slot, pageSize: Int = Layout.pageSize, dockSize: Int = Layout.dockSize) -> Bool {
        guard let from = self.slot(of: id), from != slot else { return false }
        if case .dock = slot, !dockHasRoom(for: id, dockSize: dockSize) { return false }

        dock.removeAll { $0 == id }
        for p in pages.indices { pages[p].removeAll { $0 == id } }

        switch slot {
        case .dock(let index):
            dock.insert(id, at: min(max(index, 0), dock.count))
        case .page(let p, let index):
            insert(id, onPage: max(p, 0), at: index, pageSize: pageSize)
        }
        while pages.count > 1, pages[pages.count - 1].isEmpty { pages.removeLast() }
        return true
    }

    /// Whether `id` can be in the dock: it is already, or there is a place free.
    func dockHasRoom(for id: String, dockSize: Int = Layout.dockSize) -> Bool {
        dock.contains(id) || dock.count < dockSize
    }

    /// Drops empty pages, always leaving one to show: after a sync, and when
    /// edit mode ends.
    mutating func removeEmptyPages() {
        pages.removeAll(where: \.isEmpty)
        if pages.isEmpty { pages = [[]] }
    }

    /// Puts `id` on page `p` at `index`, pushing a full page's last icon onto
    /// the next page, and on through every full page after it.
    private mutating func insert(_ id: String, onPage p: Int, at index: Int, pageSize: Int) {
        while pages.count <= p { pages.append([]) }
        pages[p].insert(id, at: min(max(index, 0), pages[p].count))
        var page = p
        while pages[page].count > pageSize {
            let spill = pages[page].removeLast()
            if page + 1 == pages.count { pages.append([]) }
            pages[page + 1].insert(spill, at: 0)
            page += 1
        }
    }
}
