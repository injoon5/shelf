import Foundation
import Testing
import UIKit
@testable import Shelf

/// Delete App on the Home Screen (PLAN.md §0.4): the minus badge, the menu
/// item, the alert, and the icon leaving and coming back. The data half
/// (`LibraryStore.delete`) is `LibraryStoreTests`'.
@MainActor
@Suite struct DeleteAppUITests {
    private let geometry = HomeGeometry(size: CGSize(width: 402, height: 874), safeTop: 62, labelHeight: 14.3)

    private func demo(_ slugs: [String] = ["habits", "notes", "todos"]) -> LibraryStore {
        let apps = slugs.map { CachedApp(meta: AppMeta(slug: $0, name: $0.capitalized), cachedVersion: "1") }
        return LibraryStore(demo: apps, cache: AppCache(root: temporaryFolder()))
    }

    // MARK: Where

    /// Delete App goes last, in red, with Edit Home Screen, as Springboard's
    /// Remove App does (`longpress-menu-grid-photos.png`); Settings has none.
    @Test func deleteAppIsLastInAnAppsMenu() throws {
        let library = demo()
        let model = HomeModel()
        let app = try #require(library.app("habits"))
        let groups = HomeItem.app(app).menu(model: model, library: library)
        let last = try #require(groups.last)
        #expect(last.map(\.title) == ["Edit Home Screen", "Delete App"])
        let delete = try #require(last.last)
        #expect(delete.isDestructive)
        #expect(delete.symbol == "minus.circle")
        #expect(groups.dropLast().joined().allSatisfy { !$0.isDestructive })

        // It asks; nothing is deleted until the alert says so.
        delete.perform()
        #expect(model.deleteRequest == "habits")
        #expect(library.app("habits") != nil)

        let settings = HomeItem.settings.menu(model: model, library: library)
        #expect(!settings.joined().contains { $0.title == "Delete App" })
    }

    /// Every icon has the minus badge in edit mode but Settings.
    @Test func everyIconButSettingsHasTheBadge() {
        let app = IconView(item: .app(CachedApp(meta: AppMeta(slug: "a", name: "A"), cachedVersion: "1")), iconSize: 64)
        let settings = IconView(item: .settings, iconSize: 64)
        for icon in [app, settings] {
            icon.setCell(iconSize: 64, labelWidth: 76, labelHeight: 14.3, labelFont: .systemFont(ofSize: 12))
            icon.setBadge(true, animated: false)
        }
        #expect(app.showsMinusBadge)
        #expect(!settings.showsMinusBadge)
        // Its centre is 3.67 pt in from the artwork's corner, and a finger
        // there hits it.
        let corner = CGPoint(x: (app.bounds.width - 64) / 2, y: 0)
        #expect(app.badgeContains(CGPoint(x: corner.x + HomeMetrics.badgeInset, y: HomeMetrics.badgeInset)))
        #expect(!app.badgeContains(CGPoint(x: app.bounds.midX, y: 40)))
        app.setBadge(false, animated: false)
        #expect(!app.badgeContains(CGPoint(x: corner.x + HomeMetrics.badgeInset, y: HomeMetrics.badgeInset)))
    }

    @Test func settingsCantAskToBeDeleted() {
        let model = HomeModel()
        model.askToDelete(Layout.settings)
        #expect(model.deleteRequest == nil)
    }

    // MARK: The alert

    /// Springboard's wording, with what's different about Shelf: every
    /// device, and no undo. Cancel, then Delete in red.
    @Test func theAlertIsSpringboards() {
        let alert = DeleteAlert.make(name: "Habits", onDelete: {}, onCancel: {})
        #expect(alert.preferredStyle == .alert)
        #expect(alert.title == "Delete “Habits”?")
        #expect(alert.message == "Deleting this app will also delete its data on all your devices. This can’t be undone.")
        #expect(alert.actions.map(\.title) == ["Cancel", "Delete"])
        #expect(alert.actions.map(\.style) == [.cancel, .destructive])
    }

    // MARK: Deleting

    /// A minus badge asks; Delete in the alert deletes; Cancel doesn't.
    @Test func theBadgeAsksAndTheAlertDeletes() async {
        let library = demo()
        let model = HomeModel()
        let view = HomeView(model: model, library: library, overlay: HomeOverlay())

        view.onDelete("notes")
        #expect(model.deleteRequest == "notes")
        model.cancelDelete()
        #expect(await model.confirmDelete(in: library) == nil)
        #expect(library.app("notes") != nil)

        view.onDelete("habits")
        #expect(await model.confirmDelete(in: library) == .deleted)
        #expect(model.deleteRequest == nil)
        #expect(library.app("habits") == nil)
        #expect(library.layout.slot(of: "habits") == nil)
        #expect(library.layout.slot(of: "notes") != nil)
    }

    /// On screen, a deleted icon shrinks away where it is (out of the icons
    /// that can be pressed); refused before it has gone, the same icon turns
    /// around, and the layout is as it was.
    @Test func aRefusedDeletionBringsTheSameIconBack() async throws {
        let h = StoreHarness()
        defer { h.cleanUp() }
        for slug in ["habits", "notes", "todos"] { h.library.put(slug, version: "\(slug)-1") }
        await h.store.sync()
        let before = h.store.layout
        h.library.update {
            $0.deleteRefusal = StubResponse(status: 503)
            // Long enough to see it go (the check polls every 20 ms), and
            // shorter than the 200 ms shrink, so it turns around mid-way.
            $0.deleteDelay = .milliseconds(120)
        }

        let model = HomeModel()
        // In the host app's scene, so Core Animation plays the shrink in
        // real time rather than finishing it at once off screen.
        let scene = try #require(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: geometry.size)
        let view = HomeView(model: model, library: h.store, overlay: HomeOverlay())
        view.frame = window.bounds
        window.addSubview(view)
        window.isHidden = false
        view.geometry = geometry
        func settle() {
            view.setNeedsUpdateProperties()
            view.updatePropertiesIfNeeded()
            view.layoutIfNeeded()
        }
        settle()
        settle()
        let icon = try #require(view.iconView("notes"))

        // What the alert's Delete does (`theBadgeAsksAndTheAlertDeletes`);
        // this window has no controller to show the alert from.
        let deletion = Task { await h.store.delete("notes") }
        #expect(await eventually { await h.store.app("notes") == nil })
        settle()
        #expect(view.iconView("notes") == nil)
        #expect(icon.isLeaving)
        #expect(icon.layer.opacity == 0)

        let result = await deletion.value
        #expect(result == .restored(.rejected(status: 503, message: "The server had a problem. Try again later.")), "\(String(describing: result))")
        settle()
        #expect(view.iconView("notes") === icon)
        #expect(!icon.isLeaving)
        #expect(icon.layer.opacity == 1)
        #expect(h.store.layout == before)
        window.isHidden = true
    }

    /// The exit runs from wherever the icon is on screen to nothing, and a
    /// return springs back from there to full size.
    @Test func leavingAndComingBackEndWhereTheyShould() throws {
        let icon = IconView(item: .settings, iconSize: 64)
        var gone = false
        icon.leave { gone = true }
        #expect(icon.isLeaving)
        #expect(icon.layer.opacity == 0)
        #expect(icon.layer.transform.m11 < 0.01)
        let shrink = try #require(icon.layer.animation(forKey: "transform") as? CABasicAnimation)
        #expect(abs(shrink.duration - Motion.iconLeave) < 0.001)

        icon.comeBack()
        #expect(!icon.isLeaving)
        #expect(icon.layer.opacity == 1)
        #expect(abs(icon.layer.transform.m11 - 1) < 0.001)
        #expect(icon.layer.animation(forKey: "transform.scale") is CASpringAnimation)
        #expect(!gone)
    }
}
