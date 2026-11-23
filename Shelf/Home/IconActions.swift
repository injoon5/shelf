import UIKit

/// One action in an icon's long-press menu.
struct IconAction {
    var title: String
    var symbol: String
    var isDestructive = false
    var isEnabled = true
    var perform: @MainActor () -> Void
}

extension HomeItem {
    /// The icon's menu, in groups: an app's own actions, then Edit Home
    /// Screen. Settings has only Edit Home Screen: it can't be changed,
    /// reloaded, copied, reverted or deleted. The Home Screen's menu
    /// (`IconMenuView`) and a search row's (`SearchList`) are both this list.
    @MainActor
    func menu(model: HomeModel, library: LibraryStore) -> [[IconAction]] {
        var groups: [[IconAction]] = []
        if let app {
            var actions = [
                IconAction(title: String(localized: "Change…"), symbol: "wand.and.sparkles") {
                    model.sheet = .change(app)
                },
                IconAction(title: String(localized: "Reload App"), symbol: "arrow.clockwise") {
                    Task { _ = await library.fetch(app.slug) }
                },
                IconAction(title: String(localized: "Copy Source"), symbol: "doc.on.doc", isEnabled: app.isRunnable) {
                    UIPasteboard.general.string = library.source(for: app.slug)
                },
            ]
            if app.meta.revertible {
                actions.append(IconAction(title: String(localized: "Revert"), symbol: "arrow.uturn.backward") {
                    Task { await library.revert(app.slug) }
                })
            }
            groups.append(actions)
        }
        groups.append([IconAction(title: String(localized: "Edit Home Screen"), symbol: "apps.iphone") {
            model.startEditing()
        }])
        return groups
    }
}
