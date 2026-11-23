import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// Icon Appearance (PLAN.md §0.5): Automatic, Light or Dark, resolved once
/// into the window's icon tone, which every icon reads.
@MainActor
@Suite struct IconAppearanceTests {
    private let screen = CGSize(width: 402, height: 874)

    @Test func automaticFollowsTheSystemAndTheOthersHold() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            #expect(IconAppearance.automatic.tone(system: style) == IconTone(style))
            #expect(IconAppearance.light.tone(system: style) == .light)
            #expect(IconAppearance.dark.tone(system: style) == .dark)
        }
    }

    /// Icon Style is gone. Whatever it held (Clear, Color, or the older
    /// Default, Dark and Tinted) reads as Automatic, and the old key goes.
    @Test(arguments: ["clear", "color", "dark", "tinted"])
    func aStoredIconStyleReadsAsAutomatic(style: String) throws {
        let suite = "shelf.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(style, forKey: ShelfSettings.retiredIconStyleKey)
        let settings = ShelfSettings(defaults: defaults)
        #expect(settings.iconAppearance == .automatic)
        #expect(defaults.object(forKey: ShelfSettings.retiredIconStyleKey) == nil)

        settings.iconAppearance = .dark
        #expect(ShelfSettings(defaults: defaults).iconAppearance == .dark)
    }

    /// Every icon on screen, held light and held dark whatever the system
    /// is: the grid, the dock with Settings, search's rows, an open card's
    /// face, and a sheet's embedded icon (the New App preview, Settings'
    /// row). The lifted and carried icon is the grid's own view, moved.
    @Test func everyIconResolvesThroughTheOneValue() async throws {
        let cache = AppCache(root: temporaryFolder())
        let apps = ["habits", "timer", "water"].map {
            CachedApp(meta: AppMeta(slug: $0, name: $0.capitalized, version: "1"), cachedVersion: "1")
        }
        for app in apps { try cache.writeSource(Demo.source, for: app.slug) }
        let library = LibraryStore(demo: apps, dock: ["habits"], cache: cache)
        let model = HomeModel()
        let settings = ShelfSettings(defaults: try #require(UserDefaults(suiteName: "shelf.tests.\(UUID().uuidString)")))
        let stage = StageController(model: model, library: library, settings: settings)
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: screen)
        window.rootViewController = stage
        window.isHidden = false
        defer { window.isHidden = true }
        let preview = UIHostingController(rootView: IconImage(face: IconFace(apps[1].meta), size: 54))
        preview.view.frame = CGRect(x: 0, y: 0, width: 54, height: 54)
        window.addSubview(preview.view)
        settle(stage)

        // Search's rows, and a card open over everything.
        model.isSearching = true
        settle(stage)
        model.run = HomeModel.Run(app: apps[2], source: Demo.source)
        settle(stage)

        let system = window.windowScene?.screen.traitCollection.userInterfaceStyle ?? .light
        for appearance in [IconAppearance.dark, .light, .automatic] {
            settings.iconAppearance = appearance
            settle(stage)
            let expected = appearance.tone(system: system)
            let icons = artViews(in: window)
            let names = Set(icons.map { String(describing: type(of: $0)) })
            #expect(names.contains("CardFaceView"))
            // Three apps and Settings on the Home Screen, four rows, the card, the preview.
            #expect(icons.count >= 10, "\(icons.count) icons")
            for icon in icons {
                #expect(icon.traitCollection.iconTone == expected, "\(type(of: icon)) under \(appearance)")
                #expect(icon.paintedTone == expected, "\(type(of: icon)) painted under \(appearance)")
            }
        }
        // Labels (and the glass and wallpaper beside them) keep the system's
        // appearance, whatever the icons are held at.
        settings.iconAppearance = system == .dark ? .light : .dark
        settle(stage)
        let labels = labelViews(in: stage.view)
        #expect(!labels.isEmpty)
        for label in labels {
            #expect(label.traitCollection.userInterfaceStyle == system, "\(label.text ?? "")")
        }
    }

    private func labelViews(in view: UIView) -> [UILabel] {
        (view as? UILabel).map { [$0] } ?? view.subviews.flatMap(labelViews)
    }

    private func artViews(in view: UIView) -> [IconArtView] {
        (view as? IconArtView).map { [$0] } ?? view.subviews.flatMap(artViews)
    }

    private func settle(_ controller: UIViewController) {
        for _ in 0..<4 {
            controller.updatePropertiesIfNeeded()
            controller.view.updatePropertiesIfNeeded()
            controller.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
    }
}
