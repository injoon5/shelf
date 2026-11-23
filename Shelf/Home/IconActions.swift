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
    /// Screen and Delete App (`longpress-menu-grid-photos.png`). Settings
    /// has only Edit Home Screen: it can't be changed, reloaded, copied,
    /// reverted or deleted. The Home Screen's menu
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
        var last = [IconAction(title: String(localized: "Edit Home Screen"), symbol: "apps.iphone") {
            model.startEditing()
        }]
        // Springboard's Remove App, in red, last, with Edit Home Screen.
        // Shelf has no App Library to remove an app to, so it's Delete App.
        if let app, isDeletable {
            last.append(IconAction(title: String(localized: "Delete App"), symbol: "minus.circle", isDestructive: true) {
                model.askToDelete(app.slug)
            })
        }
        groups.append(last)
        return groups
    }
}
