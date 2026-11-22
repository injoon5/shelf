import Foundation
import Observation

/// What the Home Screen shows: the apps, where they sit, and how sync is going.
/// Everything here is read on the main actor; the work happens in `SyncEngine`
/// and `AppData`.
@MainActor
@Observable
final class LibraryStore {
    enum Banner: Equatable {
        case offline
        case tokenExpired
    }

    private(set) var apps: [CachedApp]
    private(set) var layout: Layout
    /// Apps whose source is downloading right now.
    private(set) var downloading: Set<String> = []
    private(set) var banner: Banner?
    private(set) var lastSynced: Date?
    private(set) var isSyncing = false
    private(set) var isSignedIn: Bool
    /// The server refused the token. Settings says so until a sync succeeds.
    private(set) var tokenRejected = false
    /// A sync failed while there was nothing cached to show instead.
    private(set) var loadFailure: API.Failure?

    @ObservationIgnored private let cache: AppCache
    @ObservationIgnored private let engine: SyncEngine
    @ObservationIgnored private let data: AppData
    @ObservationIgnored private let layoutURL: URL
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    @ObservationIgnored private var isDemo = false

    init(cache: AppCache = .standard, data: AppData = .shared,
         layoutURL: URL = URL.applicationSupportDirectory.appending(path: "layout.json")) {
        self.cache = cache
        self.data = data
        self.layoutURL = layoutURL
        engine = SyncEngine(cache: cache, api: { Account.api })
        isSignedIn = Account.api != nil

        // Read before the first frame, so the Home Screen never flashes empty.
        let index = cache.readIndex()
        apps = index.apps
        lastSynced = index.syncedAt
        layout = (try? JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))) ?? Layout()
        layout.reconcile(with: apps.map(\.slug))
    }

    func app(_ slug: String) -> CachedApp? {
        apps.first { $0.slug == slug }
    }

    func source(for slug: String) -> String? {
        #if DEBUG
        if isDemo { return Demo.source }
        #endif
        return cache.source(for: slug)
    }

    // MARK: Sync

    /// How old a sync can be before coming back to Shelf syncs again.
    private static let staleAfter: TimeInterval = 600

    func syncIfStale() async {
        if let lastSynced, Date.now.timeIntervalSince(lastSynced) < Self.staleAfter { return }
        await sync()
    }

    func sync() async {
        guard isSignedIn, !isSyncing, !isDemo else { return }
        isSyncing = true
        generation += 1
        let current = generation
        defer {
            isSyncing = false
            downloading = []
            generation += 1
        }
        do {
            let index = try await engine.sync { [weak self] event in
                Task { @MainActor in self?.handle(event, generation: current) }
            }
            generation += 1   // events still in flight are stale from here
            apply(index)
            tokenRejected = false
            loadFailure = nil
            hideBanner()
            let slugs = apps.map(\.slug)
            Task { await data.pull(slugs) }
        } catch {
            // A sync cut short by Sign Out has nothing to report.
            guard isSignedIn else { return }
            let failure = error as? API.Failure ?? .offline
            if failure == .unauthorized { tokenRejected = true }
            if apps.isEmpty {
                loadFailure = failure
            } else {
                show(failure == .unauthorized ? .tokenExpired : .offline)
            }
        }
    }

    /// Downloads one app's source: the tap on an icon that has none yet.
    /// Returns whether the app can run now.
    func fetch(_ slug: String) async -> Bool {
        guard isSignedIn else { return false }
        downloading.insert(slug)
        defer { downloading.remove(slug) }
        guard let index = try? await engine.fetch(slug) else { return false }
        apply(index)
        return app(slug)?.isRunnable == true
    }

    /// Opening an app clears its blue dot.
    func opened(_ slug: String) {
        guard let i = apps.firstIndex(where: { $0.slug == slug }), apps[i].isNew else { return }
        apps[i].isNew = false
        Task { _ = await engine.markOpened(slug) }
    }

    private func handle(_ event: SyncEngine.Event, generation: Int) {
        guard generation == self.generation else { return }
        switch event {
        case .listed(let listed):
            // Icons take their final place now and fill in as sources arrive.
            apps = listed
            reconcileLayout()
        case .downloading(let slug):
            downloading.insert(slug)
        case .finished(let slug, _):
            downloading.remove(slug)
        }
    }

    private func apply(_ index: LibraryIndex) {
        apps = index.apps
        lastSynced = index.syncedAt
        reconcileLayout()
    }

    // MARK: Banner

    private func show(_ banner: Banner) {
        self.banner = banner
        bannerTask?.cancel()
        bannerTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.bannerStay)
            if !Task.isCancelled { self?.banner = nil }
        }
    }

    func hideBanner() {
        bannerTask?.cancel()
        banner = nil
    }

    // MARK: Layout

    /// Moves an icon. Called many times during a drag, so it doesn't save;
    /// `commitLayout` does, when the icon is dropped.
    @discardableResult
    func move(_ slug: String, to slot: Layout.Slot) -> Bool {
        layout.move(slug, to: slot)
    }

    func commitLayout() {
        saveLayout()
    }

    func resetLayout() {
        layout = Layout()
        layout.reconcile(with: apps.map(\.slug))
        saveLayout()
    }

    private func reconcileLayout() {
        let before = layout
        layout.reconcile(with: apps.map(\.slug))
        if layout != before { saveLayout() }
    }

    private func saveLayout() {
        guard let encoded = try? JSONEncoder().encode(layout) else { return }
        try? FileManager.default.createDirectory(at: layoutURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: layoutURL, options: .atomic)
    }

    // MARK: Account

    /// Checks the token against the server before saving anything.
    func signIn(site: URL, token: String) async throws {
        _ = try await API(origin: site, token: token).apps(ifNoneMatch: nil)
        Account.signIn(site: site, token: token)
        isSignedIn = true
        tokenRejected = false
        loadFailure = nil
        await sync()
    }

    /// Clears the token, the cache and each app's storage.
    func signOut() async {
        generation += 1
        Account.signOut()
        isSignedIn = false
        await engine.reset()
        await data.reset()
        apps = []
        lastSynced = nil
        tokenRejected = false
        loadFailure = nil
        hideBanner()
        layout = Layout()
        try? FileManager.default.removeItem(at: layoutURL)
    }

    // MARK: Changing apps

    /// Saves an app to the server. It returns once the server has it; the sync
    /// that follows lands the icon like any other, pie and blue dot included.
    func install(slug: String, name: String, icon: String?, tint: Tint, source: String) async throws {
        guard let api = Account.api else { throw API.Failure.unauthorized }
        _ = try await api.install(slug: slug, name: name, icon: icon, tint: tint, source: source)
        Task { await sync() }
    }

    func revert(_ slug: String) async {
        guard let api = Account.api else { return }
        do {
            _ = try await api.revert(slug)
            await sync()
        } catch {
            show(error as? API.Failure == .unauthorized ? .tokenExpired : .offline)
        }
    }

    #if DEBUG
    /// A library with no server behind it, for previews and screenshots.
    init(demo apps: [CachedApp], dock: [String] = []) {
        cache = AppCache(root: URL.temporaryDirectory.appending(path: "shelf-demo"))
        data = AppData(root: URL.temporaryDirectory.appending(path: "shelf-demo-data"), api: { nil })
        layoutURL = URL.temporaryDirectory.appending(path: "shelf-demo/layout.json")
        engine = SyncEngine(cache: cache, api: { nil })
        isSignedIn = true
        isDemo = true
        self.apps = apps
        layout = Layout(dock: dock, pages: [[]])
        layout.reconcile(with: apps.map(\.slug))
    }
    #endif
}
