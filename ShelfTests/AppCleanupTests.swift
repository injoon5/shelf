import Foundation
import Testing
@testable import Shelf

/// The one way an app's things leave the phone (plan §0.4).
struct AppCleanupTests {
    @Test func theLibrarysStepsAreEverythingKeptPerApp() {
        let folder = temporaryFolder()
        let cleanup = AppCleanup.library(
            cache: AppCache(root: folder.appending(path: "apps")),
            appStorage: AppStorageKeys(.standard),
            data: AppData(root: folder.appending(path: "data"), api: { nil }),
            snapshots: LaunchSnapshots(root: folder.appending(path: "Snapshots")))
        #expect(cleanup.steps.map(\.name) == ["source", "@AppStorage", "DB store", "launch snapshot"])

        let bare = AppCleanup.library(cache: AppCache(root: folder), appStorage: AppStorageKeys(.standard))
        #expect(bare.steps.map(\.name) == ["source", "@AppStorage"])
    }

    /// Where a later feature plugs in: its step runs with the rest, in order.
    @Test func stepsRunInOrderForOneApp() async {
        let log = Locked<[String]>([])
        let cleanup = AppCleanup()
            .adding("first") { slug in log.withLock { $0.append("first \(slug)") } }
            .adding("second") { slug in log.withLock { $0.append("second \(slug)") } }
        await cleanup.remove("habits")
        #expect(log.value == ["first habits", "second habits"])
    }

    @Test func removesEverythingOfOneAppAndCanRunTwice() async throws {
        let folder = temporaryFolder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let suite = "shelf-tests-\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let defaults = UserDefaults(suiteName: suite)!
        let cache = AppCache(root: folder.appending(path: "apps"))
        let data = AppData(root: folder.appending(path: "data"), api: { nil })
        let snapshots = LaunchSnapshots(root: folder.appending(path: "Snapshots"))
        let cleanup = AppCleanup.library(cache: cache, appStorage: AppStorageKeys(defaults), data: data, snapshots: snapshots)

        for slug in ["habits", "habits-2"] {
            try cache.writeSource("// \(slug)", for: slug)
            let session = await data.open(slug, pullTimeout: .zero)
            try session.write(.string("x"), for: "k")
            await data.close(session)
            defaults.set(1, forKey: "kiln.app.\(slug).k")
            let snapshot = try #require(snapshots.folder(for: slug))
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        }

        await cleanup.remove("habits")
        await cleanup.remove("habits")

        #expect(!cache.hasSource(for: "habits"))
        #expect(await data.usage()["habits"] == nil)
        #expect(defaults.object(forKey: "kiln.app.habits.k") == nil)
        #expect(!FileManager.default.fileExists(atPath: snapshots.folder(for: "habits")!.path(percentEncoded: false)))

        #expect(cache.hasSource(for: "habits-2"))
        #expect(await data.usage()["habits-2"] != nil)
        #expect(defaults.integer(forKey: "kiln.app.habits-2.k") == 1)
        #expect(FileManager.default.fileExists(atPath: snapshots.folder(for: "habits-2")!.path(percentEncoded: false)))
    }

    // MARK: Launch snapshots

    @Test func snapshotsLiveInCachesPerApp() {
        let folder = LaunchSnapshots.standard.folder(for: "habits")
        #expect(folder == URL.cachesDirectory.appending(path: "Snapshots/habits", directoryHint: .isDirectory))
    }

    @Test(arguments: ["", ".", "..", "../apps", "a/b", ".hidden"])
    func aSlugCanNeverNameAnotherFolder(slug: String) throws {
        let snapshots = LaunchSnapshots(root: temporaryFolder())
        #expect(snapshots.folder(for: slug) == nil)
    }

    @Test func removeAllTakesEveryApp() throws {
        let root = temporaryFolder()
        let snapshots = LaunchSnapshots(root: root)
        for slug in ["a", "b"] {
            try FileManager.default.createDirectory(at: snapshots.folder(for: slug)!, withIntermediateDirectories: true)
        }
        snapshots.removeAll()
        #expect(!FileManager.default.fileExists(atPath: root.path(percentEncoded: false)))
    }

    // MARK: Slugs

    @Test func validSlugsAreTheServers() {
        for slug in ["habits", "tip-jar", "My_App-2", "a", "0", String(repeating: "a", count: 64)] {
            #expect(AppMeta.isValidSlug(slug), "\(slug)")
        }
        for slug in [":settings", "", "-a", "_a", "a b", "a/b", "a.b", "é", String(repeating: "a", count: 65)] {
            #expect(!AppMeta.isValidSlug(slug), "\(slug)")
        }
    }
}
