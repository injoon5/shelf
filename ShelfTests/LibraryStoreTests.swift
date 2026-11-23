import Foundation
import Testing
@testable import Shelf

/// A `LibraryStore` over a `FakeLibrary`, with its own cache, data, layout,
/// `@AppStorage` suite, snapshots and permission ledger.
@MainActor
struct StoreHarness {
    let library = FakeLibrary()
    let folder = temporaryFolder()
    let suite = "shelf-tests-\(UUID().uuidString)"
    let store: LibraryStore

    var cache: AppCache { AppCache(root: folder.appending(path: "apps")) }
    var defaults: UserDefaults { UserDefaults(suiteName: suite)! }
    var snapshots: LaunchSnapshots { LaunchSnapshots(root: folder.appending(path: "Snapshots")) }
    var permissionsFile: URL { folder.appending(path: "permissions.json") }

    init() {
        store = Self.store(over: library, in: folder, suite: suite)
    }

    /// Another `LibraryStore` over the same disk: Shelf after a relaunch.
    func relaunched() -> LibraryStore {
        Self.store(over: library, in: folder, suite: suite)
    }

    private static func store(over library: FakeLibrary, in folder: URL, suite: String) -> LibraryStore {
        let api = library.server.api()
        return LibraryStore(cache: AppCache(root: folder.appending(path: "apps")),
                            data: AppData(root: folder.appending(path: "data"), api: { nil }),
                            layoutURL: folder.appending(path: "layout.json"),
                            server: { api },
                            appStorage: AppStorageKeys(UserDefaults(suiteName: suite)!),
                            snapshots: LaunchSnapshots(root: folder.appending(path: "Snapshots")),
                            permissions: PermissionGate(ledger: PermissionLedger(file: folder.appending(path: "permissions.json")),
                                                        system: FixedSystemPermissions.allowingEverything(),
                                                        asker: SilentAsker()))
    }

    /// Gives an app something of everything the phone keeps per app (its
    /// source is there already): a `DB` value not yet pushed, an
    /// `@AppStorage` key, a launch snapshot and a permission answer.
    func plant(_ slug: String) async throws {
        store.permissions.ledger.set(.allowed, .location, for: slug, name: slug)
        let session = await store.data.open(slug, pullTimeout: .zero)
        try session.write(.int(1), for: "count")
        await store.data.close(session)
        defaults.set(3, forKey: "kiln.app.\(slug).count")
        let snapshot = try #require(snapshots.folder(for: slug))
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try Data("png".utf8).write(to: snapshot.appending(path: "light.png"))
    }

    /// What the phone still keeps for `slug`, by name.
    func leftovers(_ slug: String) -> Set<String> {
        var found: Set<String> = []
        if cache.hasSource(for: slug) { found.insert("source") }
        if FileManager.default.fileExists(atPath: folder.appending(path: "data/\(slug).json").path(percentEncoded: false)) {
            found.insert("DB store")
        }
        if defaults.object(forKey: "kiln.app.\(slug).count") != nil { found.insert("@AppStorage") }
        if let snapshot = snapshots.folder(for: slug), FileManager.default.fileExists(atPath: snapshot.path(percentEncoded: false)) {
            found.insert("launch snapshot")
        }
        // As the phone would find it after a relaunch: on disk.
        if PermissionLedger(file: permissionsFile).answer(.location, for: slug) != nil { found.insert("permission grants") }
        return found
    }

    var everything: Set<String> { ["source", "DB store", "@AppStorage", "launch snapshot", "permission grants"] }

    func cleanUp() {
        try? FileManager.default.removeItem(at: folder)
        UserDefaults.standard.removePersistentDomain(forName: suite)
    }
}

@MainActor
@Suite struct LibraryStoreTests {
    /// A tap on an icon whose source isn't here, with a token the server no
    /// longer takes: the same as a sync that fails that way.
    @Test func aFetchWithARejectedTokenSaysSo() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        await h.store.sync()
        h.library.update { $0.unauthorized = true }

        #expect(await h.store.fetch("habits") == false)
        #expect(h.store.tokenRejected)
        #expect(h.store.banner == .tokenExpired)
    }

    @Test func aFetchOfflineSaysSo() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        await h.store.sync()
        h.library.update { $0.offline = true }

        #expect(await h.store.fetch("habits") == false)
        #expect(!h.store.tokenRejected)
        #expect(h.store.banner == .offline)
    }

    /// The app was deleted elsewhere: a sync takes its icon away, instead of
    /// leaving one that can never open.
    @Test func aFetchOfADeletedAppSyncsItAway() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        h.library.put("notes", version: "n1")
        await h.store.sync()
        h.library.remove("notes")

        #expect(await h.store.fetch("notes") == false)
        #expect(h.store.app("notes") == nil)
        #expect(h.store.app("habits") != nil)
        #expect(h.store.banner == nil)
    }

    @Test func aFetchThatWorksOpens() async {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("habits", version: "v1")
        await h.store.sync()
        h.library.put("habits", version: "v2")

        #expect(await h.store.fetch("habits"))
        #expect(h.store.app("habits")?.cachedVersion == "v2")
        #expect(h.store.banner == nil)
    }
}

// MARK: - Deleting apps

@MainActor
@Suite struct DeleteAppTests {
    /// A library of three, synced, with something of everything planted for each.
    private func library() async throws -> StoreHarness {
        let h = StoreHarness()
        for slug in ["habits", "notes", "todos"] { h.library.put(slug, version: "\(slug)-1") }
        await h.store.sync()
        for slug in ["habits", "notes", "todos"] { try await h.plant(slug) }
        return h
    }

    @Test func online() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        #expect(h.leftovers("habits") == h.everything)
        h.library.update { $0.deleteDelay = .milliseconds(300) }

        let deletion = Task { await h.store.delete("habits") }
        // The icon goes at once; what it keeps waits for the server's answer.
        #expect(await eventually { await h.store.app("habits") == nil })
        #expect(h.store.layout.slot(of: "habits") == nil)
        #expect(h.leftovers("habits") == h.everything)

        #expect(await deletion.value == .deleted)
        #expect(h.leftovers("habits").isEmpty)
        #expect(h.library.slugs == ["notes", "todos"])
        let request = try #require(h.library.deleteRequests("habits").first)
        #expect(request.query == ["data": "delete"])
        #expect(h.store.apps.map(\.slug) == ["notes", "todos"])
        #expect(h.cache.readIndex().apps.map(\.slug) == ["notes", "todos"])
        #expect(h.cache.readDeletions().isEmpty)
        #expect(h.store.banner == nil)
        // Nothing of the others was touched.
        #expect(h.leftovers("notes") == h.everything)
        #expect(h.leftovers("todos") == h.everything)

        // Nothing brings it back.
        await h.store.sync()
        #expect(h.store.app("habits") == nil)
        #expect(h.relaunched().app("habits") == nil)
    }

    @Test func offlineIsQueuedAndSentBeforeTheNextListing() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.update { $0.offline = true }

        #expect(await h.store.delete("habits") == .queued)
        #expect(h.store.app("habits") == nil)
        #expect(h.store.layout.slot(of: "habits") == nil)
        #expect(h.leftovers("habits").isEmpty)
        #expect(h.cache.readDeletions() == ["habits"])
        // Offline isn't a failure here: nothing to report.
        #expect(h.store.banner == nil)

        // Still hidden after a relaunch, and a sync while still offline
        // changes nothing.
        let relaunched = h.relaunched()
        #expect(relaunched.app("habits") == nil)
        await relaunched.sync()
        #expect(relaunched.app("habits") == nil)
        #expect(h.cache.readDeletions() == ["habits"])

        h.library.update { $0.offline = false }
        let before = h.library.server.requests.count
        await relaunched.sync()
        let sent = h.library.server.requests.dropFirst(before).map { "\($0.method) \($0.path)" }
        #expect(sent.first == "DELETE /api/apps/habits")
        #expect(sent.dropFirst().first == "GET /api/apps")
        #expect(h.library.slugs == ["notes", "todos"])
        #expect(h.cache.readDeletions().isEmpty)
        #expect(relaunched.apps.map(\.slug) == ["notes", "todos"])
        #expect(h.leftovers("notes") == h.everything)
    }

    /// The server no longer has it: that's deleted.
    @Test func aMissingAppIsDeleted() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.remove("habits")

        #expect(await h.store.delete("habits") == .deleted)
        #expect(h.library.deleteRequests("habits").count == 1)
        #expect(h.store.app("habits") == nil)
        #expect(h.leftovers("habits").isEmpty)
        #expect(h.cache.readDeletions().isEmpty)
        #expect(h.store.banner == nil)
    }

    @Test func aRefusalRestoresTheApp() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.store.move("notes", to: .dock(index: 0))
        h.store.commitLayout()
        let layout = h.store.layout
        let apps = h.store.apps
        h.library.update { $0.deleteRefusal = .json(#"{"error": "Not now."}"#, status: 500) }

        let deletion = await h.store.delete("notes")

        #expect(deletion == .restored(.rejected(status: 500, message: "Not now.")))
        #expect(h.store.apps == apps)
        #expect(h.store.layout == layout)
        #expect(h.store.layout.slot(of: "notes") == .dock(index: 0))
        #expect(h.leftovers("notes") == h.everything)
        #expect(h.cache.readIndex().apps.map(\.slug) == apps.map(\.slug))
        #expect(h.cache.readDeletions().isEmpty)
        // As a failed sync reports it.
        #expect(h.store.banner == .offline)
        #expect(!h.store.tokenRejected)
        #expect(h.library.slugs == ["habits", "notes", "todos"])
        // A relaunch has it too, in its place.
        let relaunched = h.relaunched()
        #expect(relaunched.app("notes") != nil)
        #expect(relaunched.layout.slot(of: "notes") == .dock(index: 0))
    }

    @Test func aRejectedTokenRestoresTheAppAndSaysSo() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.update { $0.unauthorized = true }

        #expect(await h.store.delete("habits") == .restored(.unauthorized))
        #expect(h.store.app("habits") != nil)
        #expect(h.leftovers("habits") == h.everything)
        #expect(h.store.tokenRejected)
        #expect(h.store.banner == .tokenExpired)
    }

    /// An icon alone on its page brings the page back with it, not just the
    /// icon on the end of another.
    @Test func aRestoredAppGetsItsOwnPageBack() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.store.move("todos", to: .page(1, index: 0))
        let layout = h.store.layout
        #expect(layout.pages == [["habits", "notes"], ["todos"]])
        h.library.update { $0.deleteRefusal = StubResponse(status: 503) }

        #expect(await h.store.delete("todos") == .restored(.rejected(status: 503, message: "The server had a problem. Try again later.")))
        #expect(h.store.layout == layout)
    }

    @Test(arguments: [":settings", "", "../habits", ".hidden", "-habits", "has space", "a/b", String(repeating: "a", count: 65)])
    func onlyAppsCanBeDeleted(slug: String) async throws {
        let h = try await library()
        defer { h.cleanUp() }
        let before = h.library.server.requests.count

        #expect(await h.store.delete(slug) == .refused)
        #expect(h.library.server.requests.count == before)
        #expect(h.store.apps.count == 3)
    }

    /// Server slugs can be wider than Shelf's own.
    @Test func anyServerSlugCanBeDeleted() async throws {
        let h = StoreHarness()
        defer { h.cleanUp() }
        h.library.put("My_App-2", version: "1")
        await h.store.sync()
        #expect(await h.store.delete("My_App-2") == .deleted)
        #expect(h.library.slugs.isEmpty)
    }

    /// Deleted on another phone or the web: this phone's sync removes
    /// everything too, through the same cleanup.
    @Test func aDeletionElsewhereRemovesEverythingHere() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.remove("habits")

        await h.store.sync()

        #expect(h.store.app("habits") == nil)
        #expect(h.store.layout.slot(of: "habits") == nil)
        #expect(h.leftovers("habits").isEmpty)
        #expect(h.leftovers("notes") == h.everything)
    }

    /// A queued deletion that the server refuses for good: the app comes back
    /// with that sync, and the failure shows.
    @Test func aQueuedDeletionRefusedForGoodComesBack() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.update { $0.offline = true }
        #expect(await h.store.delete("habits") == .queued)
        h.library.update {
            $0.offline = false
            $0.deleteRefusal = .json(#"{"error": "No."}"#, status: 403)
        }

        await h.store.sync()

        #expect(h.store.app("habits")?.isRunnable == true)
        #expect(h.cache.readDeletions().isEmpty)
        #expect(h.store.banner == .offline)
    }

    /// A server error leaves it queued, and the sync fails as a failed
    /// listing would.
    @Test func aQueuedDeletionWaitsOutAServerError() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.update { $0.offline = true }
        #expect(await h.store.delete("habits") == .queued)
        h.library.update {
            $0.offline = false
            $0.deleteRefusal = StubResponse(status: 503)
        }

        let listed = h.library.listRequests.count
        await h.store.sync()

        #expect(h.store.app("habits") == nil)
        #expect(h.cache.readDeletions() == ["habits"])
        #expect(h.library.listRequests.count == listed)
        #expect(h.store.banner == .offline)

        h.library.update { $0.deleteRefusal = nil }
        await h.store.sync()
        #expect(h.cache.readDeletions().isEmpty)
        #expect(h.library.slugs == ["notes", "todos"])
    }

    /// Installing under a slug whose deletion is queued sends the deletion
    /// first, so the next sync doesn't delete the new app.
    @Test func installingOverAQueuedDeletionSendsItFirst() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        h.library.update { $0.offline = true }
        #expect(await h.store.delete("habits") == .queued)
        h.library.update { $0.offline = false }
        let before = h.library.server.requests.count

        try await h.store.install(slug: "habits", name: "Habits", icon: nil, tint: .green, source: "// Name: Habits\n")

        let sent = h.library.server.requests.dropFirst(before).map { "\($0.method) \($0.path)" }
        #expect(Array(sent.prefix(2)) == ["DELETE /api/apps/habits", "PUT /api/apps/habits"])
        #expect(h.cache.readDeletions().isEmpty)
        await h.store.sync()
        #expect(h.store.app("habits") != nil)
        #expect(h.library.slugs.contains("habits"))
    }

    // MARK: Signing out

    /// Sign Out takes every app's permission answers, and the file.
    @Test func signingOutForgetsEveryPermission() async throws {
        let h = try await library()
        defer { h.cleanUp() }
        #expect(h.leftovers("notes").contains("permission grants"))

        await h.store.signOut()

        #expect(h.store.permissions.ledger.entries.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: h.permissionsFile.path(percentEncoded: false)))
        #expect(PermissionLedger(file: h.permissionsFile).entries.isEmpty)
    }
}
