import Foundation
import Testing
@testable import Shelf

/// A `LibraryStore` over a `FakeLibrary`, with its own cache, data and layout.
@MainActor
struct StoreHarness {
    let library = FakeLibrary()
    let folder = temporaryFolder()
    let suite = "shelf-tests-\(UUID().uuidString)"
    let store: LibraryStore

    init() {
        let api = library.server.api()
        store = LibraryStore(cache: AppCache(root: folder.appending(path: "apps")),
                             data: AppData(root: folder.appending(path: "data"), api: { nil }),
                             layoutURL: folder.appending(path: "layout.json"),
                             server: { api },
                             appStorage: AppStorageKeys(UserDefaults(suiteName: suite)!))
    }

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
