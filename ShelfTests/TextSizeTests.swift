import SwiftUI
import Testing
import UIKit
@testable import Shelf

/// The Home Screen's layers cap their text in two places: the icons at the
/// Home Screen's cap, and what stands in for them ("No Results", the empty
/// library, the banner) at the app's. A cap on a whole layer would hold the
/// second kind at the first.
@MainActor
@Suite struct TextSizeTests {
    @Test func noResultsFollowsTheAppsCapNotTheHomeScreens() throws {
        let home = try render(at: HomeMetrics.textSizeCap)
        let app = try render(at: ShelfMetrics.textSizeCap)
        let largest = try render(at: .accessibility5)
        #expect(home != app, "\"No Results\" stopped growing at the Home Screen's cap")
        #expect(largest == app, "\"No Results\" grew past the app's cap")
    }

    /// Search's list with a query that matches nothing, as a picture.
    private func render(at size: DynamicTypeSize) throws -> Data {
        let model = HomeModel()
        model.query = "nothing matches this"
        let library = LibraryStore(demo: [], cache: AppCache(root: temporaryFolder()))
        let screen = CGSize(width: 393, height: 852)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: screen)
        let host = UIViewController()
        window.rootViewController = host
        host.traitOverrides.preferredContentSizeCategory = UIContentSizeCategory(size)
        let list = SearchList(model: model, library: library)
        list.frame = host.view.bounds
        list.top = 90
        list.fieldTop = 700
        host.view.addSubview(list)
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<5 {
            list.setNeedsLayout()
            list.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let image = UIGraphicsImageRenderer(bounds: list.bounds).image { _ in
            list.drawHierarchy(in: list.bounds, afterScreenUpdates: true)
        }
        return try #require(image.pngData())
    }
}
