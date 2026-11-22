import Foundation

/// Where each icon sits. Saved as `layout.json`: `{ dock: [slug], pages: [[slug]] }`.
///
/// The layout only ever holds slugs. It is reconciled against the library after
/// every sync, so it never shows an app that is gone or misses one that is new.
struct Layout: Codable, Equatable, Sendable {
    /// Springboard's grid: four columns of six rows to a page.
    static let columns = 4
    static let rows = 6
    static let pageSize = columns * rows
    /// Apps the user can pin. Settings takes the last of the dock's four places.
    static let dockSize = 3

    var dock: [String] = []
    var pages: [[String]] = [[]]

    /// A position an icon can be dropped at.
    enum Slot: Equatable, Sendable {
        case page(Int, index: Int)
        case dock(index: Int)
    }

    /// Makes the layout hold exactly `slugs`: unknown ones leave, and new ones
    /// go into the first empty slot on the last page, as on iOS.
    mutating func reconcile(with slugs: [String], pageSize: Int = Layout.pageSize) {
        let known = Set(slugs)
        var seen = Set<String>()
        func keep(_ slug: String) -> Bool { known.contains(slug) && seen.insert(slug).inserted }
        dock = dock.filter(keep)
        pages = pages.map { $0.filter(keep) }
        for slug in slugs where !seen.contains(slug) {
            if pages.isEmpty || pages[pages.count - 1].count >= pageSize { pages.append([]) }
            pages[pages.count - 1].append(slug)
        }
        normalize()
    }

    func slot(of slug: String) -> Slot? {
        if let i = dock.firstIndex(of: slug) { return .dock(index: i) }
        for (p, page) in pages.enumerated() {
            if let i = page.firstIndex(of: slug) { return .page(p, index: i) }
        }
        return nil
    }

    /// Moves an icon to `slot`, sliding the others aside. A full dock refuses a
    /// newcomer; a full page pushes its last icon onto the next one.
    @discardableResult
    mutating func move(_ slug: String, to slot: Slot, pageSize: Int = Layout.pageSize, dockSize: Int = Layout.dockSize) -> Bool {
        guard let from = self.slot(of: slug), from != slot else { return false }
        if case .dock = slot, !dockHasRoom(for: slug, dockSize: dockSize) { return false }

        dock.removeAll { $0 == slug }
        for p in pages.indices { pages[p].removeAll { $0 == slug } }

        switch slot {
        case .dock(let index):
            dock.insert(slug, at: min(max(index, 0), dock.count))
        case .page(let p, let index):
            while pages.count <= p { pages.append([]) }
            pages[p].insert(slug, at: min(max(index, 0), pages[p].count))
            var page = p
            while pages[page].count > pageSize {
                let spill = pages[page].removeLast()
                if page + 1 == pages.count { pages.append([]) }
                pages[page + 1].insert(spill, at: 0)
                page += 1
            }
        }
        normalize()
        return true
    }

    /// Whether `slug` can be in the dock: it is already, or there is a place free.
    func dockHasRoom(for slug: String, dockSize: Int = Layout.dockSize) -> Bool {
        dock.contains(slug) || dock.count < dockSize
    }

    /// Drops empty pages, always leaving one to show.
    private mutating func normalize() {
        pages.removeAll(where: \.isEmpty)
        if pages.isEmpty { pages = [[]] }
    }
}
