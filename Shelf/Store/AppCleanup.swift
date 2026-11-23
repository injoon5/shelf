import Foundation

/// Everything the phone keeps for one app, and the one way to remove it
/// (plan §0.4). Delete App runs it, and so does a sync that finds an app gone
/// from the server, so a deletion on one phone leaves nothing behind on any.
///
/// Each thing Shelf keeps per app is one step. A feature that starts keeping
/// something per app adds its step in `library(…)`, and from then on both
/// ways of deleting clear it. Still to come:
/// - the app's files (§4.1);
/// - its permission grants (§4.0);
/// - its widgets (§6).
///
/// The layout isn't a step: `LibraryStore` reconciles it with the library
/// whenever the library changes, which drops the app's slot.
///
/// Every step has to be safe to run for an app that has nothing there, and
/// to run twice: a queued deletion runs it once when the app is deleted and
/// again when the sync that sends it sees the app gone.
struct AppCleanup: Sendable {
    struct Step: Sendable {
        /// What the step removes, for tests and for reading.
        var name: String
        var run: @Sendable (_ slug: String) async -> Void
    }

    private(set) var steps: [Step] = []

    /// This cleanup with one more step, run after the others.
    func adding(_ name: String, _ run: @escaping @Sendable (_ slug: String) async -> Void) -> AppCleanup {
        var copy = self
        copy.steps.append(Step(name: name, run: run))
        return copy
    }

    /// Removes everything the phone keeps for `slug`.
    func remove(_ slug: String) async {
        for step in steps { await step.run(slug) }
    }
}

extension AppCleanup {
    /// Everything Shelf keeps per app. `data` and `snapshots` are optional
    /// so a `SyncEngine` can be tested on its own, and for the demo, whose
    /// apps keep no data anyone would miss.
    static func library(
        cache: AppCache,
        appStorage: AppStorageKeys,
        data: AppData? = nil,
        snapshots: LaunchSnapshots? = nil
    ) -> AppCleanup {
        var cleanup = AppCleanup()
            .adding("source") { cache.removeSource(for: $0) }
            .adding("@AppStorage") { appStorage.remove(slug: $0) }
        if let data {
            // Pending writes go with it, unpushed: the server's copy is going too.
            cleanup = cleanup.adding("DB store") { await data.remove($0) }
        }
        if let snapshots {
            cleanup = cleanup.adding("launch snapshot") { snapshots.remove($0) }
        }
        return cleanup
    }
}
