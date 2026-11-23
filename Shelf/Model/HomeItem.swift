import Foundation

/// One icon on the Home Screen: an app, or Shelf's own Settings, which sits
/// in the layout like any app (`Layout.settings`) but opens a sheet.
enum HomeItem: Identifiable, Hashable, Sendable {
    case app(CachedApp)
    case settings

    /// Its place in the layout: the app's slug, or `Layout.settings`.
    var id: String {
        switch self {
        case .app(let app): app.slug
        case .settings: Layout.settings
        }
    }

    /// The label under the icon, and what search matches.
    var name: String {
        switch self {
        case .app(let app): app.meta.name
        case .settings: String(localized: "Settings")
        }
    }

    var app: CachedApp? {
        if case .app(let app) = self { return app }
        return nil
    }

    /// No minus badge and no Delete App for Settings (§0.4 reads this).
    var isDeletable: Bool { Layout.isDeletable(id) }
}

extension LibraryStore {
    /// The icon at `id` in the layout: Settings, or an app the library has.
    func item(_ id: String) -> HomeItem? {
        id == Layout.settings ? .settings : app(id).map(HomeItem.app)
    }

    /// Everything that has an icon, Settings included: what search looks through.
    var items: [HomeItem] {
        apps.map(HomeItem.app) + [.settings]
    }
}

extension [HomeItem] {
    /// Items whose name matches `query`: names that start with it first, then
    /// names that contain it, each in alphabetical order. An empty query
    /// matches everything.
    func matching(_ query: String) -> [HomeItem] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        let sorted = sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        guard !needle.isEmpty else { return sorted }
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let starts = sorted.filter { $0.name.range(of: needle, options: options.union(.anchored)) != nil }
        let contains = sorted.filter { item in
            item.name.range(of: needle, options: options) != nil && !starts.contains(item)
        }
        return starts + contains
    }
}
