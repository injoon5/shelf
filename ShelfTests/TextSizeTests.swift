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

    /// The results layer with a query that matches nothing, as a picture.
    private func render(at size: DynamicTypeSize) throws -> Data {
        let model = HomeModel()
        model.query = "nothing matches this"
        let layout = StageLayout()
        layout.geometry = HomeGeometry(size: CGSize(width: 393, height: 852), safeTop: 62, displayRadius: 55, labelHeight: 14)
        layout.resultsBottom = 120
        let stage = StageEnvironment(model: model, library: LibraryStore(demo: [], cache: AppCache(root: temporaryFolder())),
                                     settings: ShelfSettings(), layout: layout)

        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(origin: .zero, size: layout.geometry.size)
        let host = UIHostingController(rootView: ResultsLayer(stage: stage).environment(\.dynamicTypeSize, size))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        for _ in 0..<5 {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let image = UIGraphicsImageRenderer(bounds: host.view.bounds).image { _ in
            host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
        }
        return try #require(image.pngData())
    }
}
