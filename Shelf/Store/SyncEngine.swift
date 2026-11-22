import Foundation

/// Brings the cache in line with the server (plan §4). It is the only writer
/// of `index.json` once the app is running.
actor SyncEngine {
    /// What a sync reports while it runs, so icons can take their place first
    /// and fill in after.
    enum Event: Sendable {
        /// The server's list, merged with what is cached. Sent before any download.
        case listed([CachedApp])
        case downloading(slug: String)
        case finished(slug: String)
    }

    /// Downloads in flight at once (plan §4, step 2).
    static let maxConcurrentDownloads = 4

    private let cache: AppCache
    private let api: @Sendable () -> API?
    private let appStorage: AppStorageKeys

    /// The sync in flight, which a second caller joins instead of starting another.
    private var running: Task<LibraryIndex, Error>?
    /// The end of the queue that `sync` and `fetch` take turns on.
    private var tail: Task<Void, Never>?
    /// Bumped by `reset`, so work begun before a sign-out writes nothing after it.
    private var generation = 0

    /// `api` returns nil while signed out. `appStorage` is where Kiln keeps
    /// apps' `@AppStorage`; tests pass their own suite.
    init(cache: AppCache, api: @escaping @Sendable () -> API?, appStorage: AppStorageKeys = AppStorageKeys(.standard)) {
        self.cache = cache
        self.api = api
        self.appStorage = appStorage
    }

    /// One full sync. Returns the index as written.
    ///
    /// Throws `API.Failure` only when the list itself can't be fetched; the
    /// cache is then untouched. A source that fails to download does not
    /// throw: the app keeps its old version (or none) and the etag is dropped
    /// so the next sync tries again.
    func sync(onEvent: @escaping @Sendable (Event) -> Void = { _ in }) async throws -> LibraryIndex {
        if let running { return try await running.value }
        let task = enqueue { engine in try await engine.performSync(onEvent: onEvent) }
        running = task
        defer { if running == task { running = nil } }
        return try await task.value
    }

    /// Downloads one app's source now: the tap on an icon that has none.
    func fetch(_ slug: String) async throws -> LibraryIndex {
        try await enqueue { engine in try await engine.performFetch(slug) }.value
    }

    /// Clears an app's blue dot.
    func markOpened(_ slug: String) -> LibraryIndex {
        var index = cache.readIndex()
        guard let i = index.apps.firstIndex(where: { $0.slug == slug }), index.apps[i].isNew else { return index }
        index.apps[i].isNew = false
        try? cache.writeIndex(index)
        return index
    }

    /// Sign Out: the cache, and every app's `@AppStorage` keys.
    func reset() {
        generation += 1
        running = nil
        cache.removeAll()
        appStorage.removeAll()
    }

    // MARK: Queue

    /// Runs `work` after everything queued before it, so syncs and fetches
    /// never interleave their reads and writes of the index.
    private func enqueue<T: Sendable>(
        _ work: @escaping @Sendable (isolated SyncEngine) async throws -> T
    ) -> Task<T, Error> {
        let previous = tail
        let task = Task<T, Error> {
            await previous?.value
            return try await work(self)
        }
        tail = Task { _ = try? await task.value }
        return task
    }

    // MARK: Sync

    private func performSync(onEvent: @Sendable (Event) -> Void) async throws -> LibraryIndex {
        guard let api = api() else { throw API.Failure.unauthorized }
        let generation = self.generation
        let before = cache.readIndex()
        // A source that went missing on disk is not current, whatever the index says.
        let onDisk = Dictionary(
            before.apps.map { app in (app.slug, app.cachedVersion != nil && cache.hasSource(for: app.slug)) },
            uniquingKeysWith: { first, _ in first })
        let canSkip = onDisk.values.allSatisfy { $0 }

        let listing = try await api.apps(ifNoneMatch: canSkip ? before.etag : nil)
        try checkGeneration(generation)

        guard case .apps(let listed, let etag) = listing else {
            var index = cache.readIndex()
            index.syncedAt = .now
            try cache.writeIndex(index)
            return index
        }

        // The server's order, its metadata, and what is on disk.
        let old = Dictionary(before.apps.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<String>()
        var merged: [CachedApp] = []
        for meta in listed where seen.insert(meta.slug).inserted {
            let cached = old[meta.slug]
            merged.append(CachedApp(
                meta: meta,
                cachedVersion: onDisk[meta.slug] == true ? cached?.cachedVersion : nil,
                isNew: cached?.isNew ?? false))
        }
        onEvent(.listed(merged))

        let stale = merged.filter { !$0.isCurrent }.map(\.slug)
        let downloaded = try await download(stale, with: api, generation: generation, onEvent: onEvent)

        // Read again: `markOpened` may have cleared a dot while sources downloaded.
        let latest = Dictionary(cache.readIndex().apps.map { ($0.slug, $0) }, uniquingKeysWith: { first, _ in first })
        let firstSync = before.apps.isEmpty
        for i in merged.indices {
            let slug = merged[i].slug
            if let latestApp = latest[slug] { merged[i].isNew = latestApp.isNew }
            guard let full = downloaded[slug] else { continue }
            let changed = merged[i].cachedVersion != full.meta.version
            merged[i].meta = full.meta
            merged[i].cachedVersion = full.meta.version
            if changed && !firstSync { merged[i].isNew = true }
        }

        let index = LibraryIndex(
            etag: merged.allSatisfy(\.isCurrent) ? etag : nil,
            apps: merged,
            syncedAt: .now)
        try checkGeneration(generation)
        try cache.writeIndex(index)

        // Only now that the index no longer lists them: remove what is gone.
        let listedSlugs = Set(merged.map(\.slug))
        let gone = Set(before.apps.map(\.slug)).union(cache.sourceSlugs()).subtracting(listedSlugs)
        for slug in gone {
            cache.removeSource(for: slug)
            appStorage.remove(slug: slug)
        }
        return index
    }

    /// Downloads and writes `slugs`, a few at a time. Returns what landed on disk.
    private func download(
        _ slugs: [String],
        with api: API,
        generation: Int,
        onEvent: @Sendable (Event) -> Void
    ) async throws -> [String: AppFull] {
        var done: [String: AppFull] = [:]
        try await withThrowingTaskGroup(of: (String, AppFull?).self) { group in
            var queue = slugs.makeIterator()
            func start(_ slug: String) {
                onEvent(.downloading(slug: slug))
                group.addTask { (slug, try? await api.app(slug)) }
            }
            for _ in 0..<Self.maxConcurrentDownloads {
                guard let slug = queue.next() else { break }
                start(slug)
            }
            while let (slug, full) = try await group.next() {
                try checkGeneration(generation)
                if let full, full.meta.slug == slug, (try? cache.writeSource(full.source, for: slug)) != nil {
                    done[slug] = full
                }
                onEvent(.finished(slug: slug))
                if let next = queue.next() { start(next) }
            }
        }
        return done
    }

    // MARK: Fetch

    private func performFetch(_ slug: String) async throws -> LibraryIndex {
        guard let api = api() else { throw API.Failure.unauthorized }
        let generation = self.generation
        let full = try await api.app(slug)
        try checkGeneration(generation)
        try cache.writeSource(full.source, for: slug)

        var index = cache.readIndex()
        if let i = index.apps.firstIndex(where: { $0.slug == slug }) {
            let app = index.apps[i]
            // An update to source that was already here earns the dot; a first download doesn't.
            if let cachedVersion = app.cachedVersion, cachedVersion != full.meta.version { index.apps[i].isNew = true }
            // The listing behind the etag no longer describes this app.
            if app.meta.version != full.meta.version { index.etag = nil }
            index.apps[i].meta = full.meta
            index.apps[i].cachedVersion = full.meta.version
        } else {
            index.etag = nil
            index.apps.append(CachedApp(meta: full.meta, cachedVersion: full.meta.version))
        }
        try cache.writeIndex(index)
        return index
    }

    private func checkGeneration(_ generation: Int) throws {
        // A sign-out happened mid-sync: write nothing more.
        if generation != self.generation { throw API.Failure.unauthorized }
    }
}
