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

        init(_ failure: API.Failure) {
            self = failure == .unauthorized ? .tokenExpired : .offline
        }
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
    @ObservationIgnored private let server: @Sendable () -> API?
    /// Every app's data. The runner, the New App preview and Settings reach
    /// it through the library, so the demo's apps write only to the demo's.
    @ObservationIgnored let data: AppData
    @ObservationIgnored private let layoutURL: URL
    @ObservationIgnored private var generation = 0
    /// Which sync `isSyncing` is about: an abandoned one never clears it.
    @ObservationIgnored private var syncID = 0
    @ObservationIgnored private var bannerTask: Task<Void, Never>?
    /// Bumped when the account changes, so a fetch begun for the old one
    /// reports nothing about the new one.
    @ObservationIgnored private var account = 0
    @ObservationIgnored private var isDemo = false

    convenience init() {
        self.init(cache: .standard,
                  data: AppData(root: URL.applicationSupportDirectory.appending(path: "data"), api: { Account.api }),
                  layoutURL: URL.applicationSupportDirectory.appending(path: "layout.json"),
                  server: { Account.api })
    }

    /// The library kept in `cache`, `data` and `layoutURL`, talking to
    /// whatever `server` returns: nil while signed out. Tests pass their own.
    init(cache: AppCache, data: AppData, layoutURL: URL, server: @escaping @Sendable () -> API?,
         appStorage: AppStorageKeys = AppStorageKeys(.standard)) {
        self.cache = cache
        self.data = data
        self.layoutURL = layoutURL
        self.server = server
        engine = SyncEngine(cache: cache, api: server, appStorage: appStorage)
        isSignedIn = server() != nil

        // Read before the first frame, so the Home Screen never flashes empty.
        let index = cache.readIndex()
        apps = index.apps
        lastSynced = index.syncedAt
        layout = (try? JSONDecoder().decode(Layout.self, from: Data(contentsOf: layoutURL))) ?? Layout()
        layout.reconcile(with: apps.map(\.slug))
    }

    /// The server the library talks to: nil while signed out, and always
    /// for the demo. Everything that asks the server anything goes through it.
    var api: API? { server() }

    func app(_ slug: String) -> CachedApp? {
        apps.first { $0.slug == slug }
    }

    func source(for slug: String) -> String? {
        cache.source(for: slug)
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
        syncID += 1
        let id = syncID
        generation += 1
        let current = generation
        defer {
            if syncID == id {
                isSyncing = false
                downloading = []
                generation += 1
            }
        }
        do {
            let index = try await engine.sync { [weak self] event in
                Task { @MainActor in self?.handle(event, generation: current) }
            }
            // A sync for an account that has since gone has nothing to show.
            guard generation == current else { return }
            generation += 1   // events still in flight are stale from here
            apply(index)
            tokenRejected = false
            loadFailure = nil
            hideBanner()
            let slugs = apps.map(\.slug)
            Task { await data.pull(slugs) }
        } catch {
            // A sync cut short by Sign Out has nothing to report, even if
            // another account has signed in since.
            guard generation == current else { return }
            report(error)
        }
    }

    /// Downloads one app's source: the tap on an icon that has none yet, and
    /// Reload App. Returns whether the app can run now.
    ///
    /// A failure shows as a failed sync's does. A source the server no longer
    /// has belongs to an app deleted elsewhere, so a sync takes its icon away.
    func fetch(_ slug: String) async -> Bool {
        // The demo has no server to ask, and no token to call expired.
        guard isSignedIn, !isDemo else { return false }
        let account = self.account
        downloading.insert(slug)
        defer { downloading.remove(slug) }
        do {
            apply(try await engine.fetch(slug))
            return app(slug)?.isRunnable == true
        } catch {
            // Signed out or into another account meanwhile: nothing to say.
            guard account == self.account else { return false }
            if case .rejected(status: 404, _)? = error as? API.Failure {
                await sync()
            } else {
                report(error)
            }
            return false
        }
    }

    /// The one rule for a request to the server that failed: a rejected
    /// token is marked, so Settings says so, and the Home Screen shows the
    /// banner, or the error in place of a grid it doesn't have yet.
    private func report(_ error: any Error) {
        let failure = error as? API.Failure ?? .offline
        if failure == .unauthorized { tokenRejected = true }
        if apps.isEmpty {
            loadFailure = failure
        } else {
            show(Banner(failure))
        }
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
        case .finished(let slug):
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
    /// `commitLayout` does, on a drop, on leaving edit mode, and on leaving
    /// the foreground.
    @discardableResult
    func move(_ slug: String, to slot: Layout.Slot) -> Bool {
        layout.move(slug, to: slot)
    }

    func resetLayout() {
        layout = Layout()
        layout.reconcile(with: apps.map(\.slug))
        commitLayout()
    }

    private func reconcileLayout() {
        let before = layout
        layout.reconcile(with: apps.map(\.slug))
        if layout != before { commitLayout() }
    }

    /// Signed out, there is no library to save a layout for.
    func commitLayout() {
        guard isSignedIn, let encoded = try? JSONEncoder().encode(layout) else { return }
        try? FileManager.default.createDirectory(at: layoutURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? encoded.write(to: layoutURL, options: .atomic)
    }

    // MARK: Account

    /// Checks the token against the server before changing anything. A
    /// different site is a different library, so then the old one goes.
    func signIn(site: URL, token: String) async throws(API.Failure) {
        _ = try await API(origin: site, token: token).apps(ifNoneMatch: nil)
        if isSignedIn, !Account.isSameSite(site, Account.site) { await signOut() }
        // A sync still running is for the old token; the new one gets its own.
        await abandonSync()
        Account.signIn(site: site, token: token)
        isSignedIn = true
        tokenRejected = false
        loadFailure = nil
        await sync()
    }

    /// Clears the token, the cache and each app's storage.
    func signOut() async {
        Account.signOut()
        isSignedIn = false
        await abandonSync()
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

    private func abandonSync() async {
        account += 1
        generation += 1
        syncID += 1
        isSyncing = false
        downloading = []
        await engine.abandon()
    }

    // MARK: Changing apps

    /// Saves an app to the server. It returns once the server has it; the sync
    /// that follows lands the icon like any other, pie and blue dot included.
    func install(slug: String, name: String, icon: String?, tint: Tint, source: String) async throws(API.Failure) {
        guard let api else { throw .unauthorized }
        _ = try await api.install(slug: slug, name: name, icon: icon, tint: tint, source: source)
        Task { await sync() }
    }

    func revert(_ slug: String) async {
        guard let api else { return }
        do throws(API.Failure) {
            _ = try await api.revert(slug)
            await sync()
        } catch {
            show(Banner(error))
        }
    }

    #if DEBUG
    /// A library with no server behind it, for previews and screenshots:
    /// `apps`, with their sources already in `cache`. It never syncs.
    init(demo apps: [CachedApp], dock: [String] = [], cache: AppCache) {
        self.cache = cache
        data = AppData(root: URL.temporaryDirectory.appending(path: "shelf-demo-data"), api: { nil })
        layoutURL = cache.root.appending(path: "layout.json")
        server = { nil }
        engine = SyncEngine(cache: cache, api: server)
        isSignedIn = true
        isDemo = true
        self.apps = apps
        layout = Layout(dock: dock, pages: [[]])
        layout.reconcile(with: apps.map(\.slug))
    }
    #endif
}
