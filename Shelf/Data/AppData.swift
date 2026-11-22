import Foundation
import Synchronization

/// One app's key-value store while it is in use: the values in memory, behind
/// a lock, so `ShelfDBProtocol` can answer from any thread without waiting.
///
/// It never touches the main actor or the network. Kiln blocks the main thread
/// while an app's `await URLSession.shared.data(…)` runs, so every answer has
/// to come from here, at once, on the loading thread.
///
/// CONTRACT — signatures are fixed; bodies belong to the Data package.
final class DBSession: Sendable {
    let slug: String

    /// Why a write was refused. The limits are the server's (ij5.dev
    /// `$lib/types`), enforced here so a push can never be refused for good.
    enum Refusal: Error, Equatable, Sendable {
        /// Not 1–128 printable characters, or contains "/".
        case invalidKey
        /// The value's JSON is over 64 KB.
        case valueTooLarge
        /// The app already keeps 1,000 keys.
        case tooManyKeys
        /// The app's values would total over 5 MB.
        case storeFull
    }

    static let maxKeyLength = 128
    static let maxValueBytes = 64 * 1024
    static let maxKeys = 1000
    static let maxStoreBytes = 5 * 1024 * 1024

    /// What `{slug}.json` holds. A dirty key with no entry is a pending delete.
    struct File: Codable, Equatable, Sendable {
        struct Entry: Codable, Equatable, Sendable {
            var value: JSONValue
            /// The server rev this value is known at; 0 for a write not yet pushed.
            var rev: Int
        }
        var entries: [String: Entry] = [:]
        var dirty: [String] = []
        /// The pull cursor: the newest rev seen in a `GET …/data?since=`.
        var rev: Int = 0
    }

    /// The dirty keys at one moment, as one batch for the server.
    struct Batch: Sendable {
        var set: [String: JSONValue]
        var delete: [String]
        /// Each key's write number when the batch was taken. A key written
        /// again since stays dirty when the batch lands.
        fileprivate var marks: [String: Int]
        var isEmpty: Bool { self.set.isEmpty && self.delete.isEmpty }
    }

    private struct State {
        var entries: [String: File.Entry]
        var dirty: Set<String>
        var rev: Int
        /// UTF-8 bytes of each live value's JSON, as the server counts them.
        var sizes: [String: Int]
        var total: Int
        /// The local write number that last touched each key.
        var writes: [String: Int] = [:]
        var writeCount = 0
        /// Bumps on any change, so the store knows when to save.
        var version = 0

        init(_ file: File) {
            entries = file.entries
            dirty = Set(file.dirty)
            rev = file.rev
            sizes = file.entries.mapValues { $0.value.json.count }
            total = sizes.values.reduce(0, +)
        }

        mutating func touch(_ key: String) {
            writeCount += 1
            writes[key] = writeCount
            version += 1
        }

        mutating func store(_ value: JSONValue, size: Int, for key: String, rev: Int) {
            total += size - (sizes[key] ?? 0)
            sizes[key] = size
            entries[key] = File.Entry(value: value, rev: rev)
        }

        mutating func drop(_ key: String) {
            total -= sizes.removeValue(forKey: key) ?? 0
            entries[key] = nil
        }
    }

    private let state: Mutex<State>
    private let onWrite: (@Sendable () -> Void)?

    /// A session on its own: kept in memory, never saved or synced.
    init(slug: String, entries: [String: JSONValue] = [:]) {
        self.slug = slug
        self.state = Mutex(State(File(entries: entries.mapValues { File.Entry(value: $0, rev: 0) })))
        self.onWrite = nil
    }

    /// A session backed by `AppData`, which hears about every local write.
    init(slug: String, file: File, onWrite: @escaping @Sendable () -> Void) {
        self.slug = slug
        self.state = Mutex(State(file))
        self.onWrite = onWrite
    }

    // MARK: Reads and writes, from any thread

    func value(for key: String) -> JSONValue? {
        state.withLock { $0.entries[key]?.value }
    }

    func all() -> [String: JSONValue] {
        state.withLock { $0.entries.mapValues(\.value) }
    }

    /// Sets a value, or quietly drops a write the limits refuse. Use `write`
    /// to learn why.
    func set(_ value: JSONValue, for key: String) {
        try? write(value, for: key)
    }

    func remove(_ key: String) {
        guard Self.isValidKey(key) else { return }
        let changed = state.withLock { state in
            guard state.entries[key] != nil else { return false }
            state.drop(key)
            state.dirty.insert(key)
            state.touch(key)
            return true
        }
        if changed { onWrite?() }
    }

    /// Sets a value if the server's limits allow it. A JSON `null` deletes the
    /// key: the server can't tell a stored `null` from a tombstone.
    func write(_ value: JSONValue, for key: String) throws(Refusal) {
        guard Self.isValidKey(key) else { throw .invalidKey }
        if value == .null { return remove(key) }
        let size = value.json.count
        guard size <= Self.maxValueBytes else { throw .valueTooLarge }
        let changed = try state.withLock { state throws(Refusal) -> Bool in
            let old = state.sizes[key]
            if state.entries[key]?.value == value { return false }
            if old == nil && state.entries.count >= Self.maxKeys { throw .tooManyKeys }
            if state.total - (old ?? 0) + size > Self.maxStoreBytes { throw .storeFull }
            state.store(value, size: size, for: key, rev: 0)
            state.dirty.insert(key)
            state.touch(key)
            return true
        }
        if changed { onWrite?() }
    }

    /// 1–128 characters (Unicode scalars, as the server's `/u` pattern counts
    /// them), none of them a control character (C0, DEL, C1) or "/".
    static func isValidKey(_ key: String) -> Bool {
        let scalars = key.unicodeScalars
        guard (1...maxKeyLength).contains(scalars.count) else { return false }
        return !scalars.contains { scalar in
            let v = scalar.value
            return v <= 0x1F || (0x7F...0x9F).contains(v) || scalar == "/"
        }
    }

    // MARK: For AppData

    /// The bytes of `{slug}.json` and the version they capture.
    func encoded() -> (data: Data, version: Int) {
        let (file, version) = state.withLock { state in
            (File(entries: state.entries, dirty: state.dirty.sorted(), rev: state.rev), state.version)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return ((try? encoder.encode(file)) ?? Data(), version)
    }

    var version: Int { state.withLock { $0.version } }
    var isDirty: Bool { state.withLock { !$0.dirty.isEmpty } }
    /// Bytes of the live values, as the server counts them.
    var storedBytes: Int { state.withLock { $0.total } }

    /// Where a pull starts: the cursor, and the write number at that moment.
    func pullStart() -> (rev: Int, writeCount: Int) {
        state.withLock { ($0.rev, $0.writeCount) }
    }

    /// Applies a pull. A key that is dirty, or that was written after the pull
    /// began, keeps the phone's value: it is pushed next. Returns whether
    /// anything changed.
    @discardableResult
    func merge(_ pulled: API.DataChanges, startedAt writeCount: Int) -> Bool {
        state.withLock { state in
            var changed = false
            for change in pulled.changes {
                if state.dirty.contains(change.key) || (state.writes[change.key] ?? 0) > writeCount { continue }
                if let value = change.value, value != .null {
                    if state.entries[change.key] == File.Entry(value: value, rev: change.rev) { continue }
                    state.store(value, size: value.json.count, for: change.key, rev: change.rev)
                } else {
                    guard state.entries[change.key] != nil else { continue }
                    state.drop(change.key)
                }
                changed = true
            }
            if pulled.rev > state.rev {
                state.rev = pulled.rev
                changed = true
            }
            if changed { state.version += 1 }
            return changed
        }
    }

    /// Every dirty key, as one batch. Nil when nothing is dirty.
    func pendingBatch() -> Batch? {
        state.withLock { state in
            guard !state.dirty.isEmpty else { return nil }
            var batch = Batch(set: [:], delete: [], marks: [:])
            for key in state.dirty.sorted() {
                if let entry = state.entries[key] { batch.set[key] = entry.value } else { batch.delete.append(key) }
                batch.marks[key] = state.writes[key] ?? 0
            }
            return batch
        }
    }

    /// The server took `batch` at `rev`. The pull cursor does not move: other
    /// devices' writes below `rev` haven't been pulled yet.
    func pushed(_ batch: Batch, rev: Int) {
        state.withLock { state in
            for (key, mark) in batch.marks where (state.writes[key] ?? 0) == mark {
                state.dirty.remove(key)
                state.entries[key]?.rev = rev
            }
            state.version += 1
        }
    }

    /// Delete Data: every live key becomes a pending delete.
    func removeAll() {
        state.withLock { state in
            for key in Array(state.entries.keys) {
                state.drop(key)
                state.dirty.insert(key)
                state.touch(key)
            }
            state.version += 1
        }
    }
}

/// Every app's data on the phone (plan §8.3): one JSON file per app in
/// `Application Support/data/`, local first, synced with the server in the
/// background.
///
/// The open `DBSession` is the truth while an app runs; this actor saves it
/// and syncs it.
///
/// CONTRACT — signatures are fixed; bodies belong to the Data package.
actor AppData {
    static let shared = AppData(root: URL.applicationSupportDirectory.appending(path: "data"), api: { Account.api })

    private let root: URL
    private let api: @Sendable () -> API?
    private let pushDelay: Duration
    private let saveDelay: Duration

    /// Every store loaded this launch, open or not.
    private var sessions: [String: DBSession] = [:]
    /// The session version last written to disk.
    private var saved: [String: Int] = [:]
    private var saveTimers: [String: Task<Void, Never>] = [:]
    private var pushTimers: [String: Task<Void, Never>] = [:]
    /// The last push queued per app; pushes of one app run one after another.
    private var pushes: [String: Task<Void, Never>] = [:]
    private var pulls: [String: Task<Void, Never>] = [:]
    /// Bumped by `reset`, so work begun before a sign-out writes nothing after it.
    private var generation = 0

    /// `pushDelay` is how long after the last write dirty keys are pushed;
    /// `saveDelay` how long writes gather before the file is saved.
    init(
        root: URL,
        api: @escaping @Sendable () -> API?,
        pushDelay: Duration = .seconds(2),
        saveDelay: Duration = .milliseconds(250)
    ) {
        self.root = root
        self.api = api
        self.pushDelay = pushDelay
        self.saveDelay = saveDelay
    }

    /// Opens an app's store. Pulls changes first, for at most `pullTimeout`;
    /// after that the app runs with what is on the phone.
    func open(_ slug: String, pullTimeout: Duration = .seconds(1)) async -> DBSession {
        let session = session(slug)
        await Self.wait(for: startPull(slug), atMost: pullTimeout)
        return session
    }

    /// The app closed: save, and push what is dirty.
    func close(_ session: DBSession) async {
        guard sessions[session.slug] === session else { return }
        save(session.slug)
        await push(session.slug)
    }

    /// A throwaway store for a preview, optionally starting from a copy of an
    /// app's real data. Nothing written to it is saved or synced.
    func scratch(copying slug: String?) async -> DBSession {
        guard let slug else { return DBSession(slug: "preview") }
        let entries = sessions[slug]?.all() ?? readFile(slug)?.entries.mapValues(\.value) ?? [:]
        return DBSession(slug: slug, entries: entries)
    }

    /// Pulls every listed app's changes. Called after a library sync.
    func pull(_ slugs: [String]) async {
        guard api() != nil else { return }
        let tasks = slugs.map { startPull($0) }
        for task in tasks { await task.value }
    }

    /// Pushes everything dirty. Called when Shelf goes to the background.
    func pushAll() async {
        for slug in slugsOnDisk() { _ = session(slug) }
        for slug in sessions.keys { save(slug) }
        let dirty = sessions.filter { $0.value.isDirty }.map(\.key)
        await withTaskGroup(of: Void.self) { group in
            for slug in dirty { group.addTask { await self.push(slug) } }
        }
    }

    /// Bytes stored per app, for Settings.
    func usage() async -> [String: Int] {
        for slug in sessions.keys { save(slug) }
        var usage: [String: Int] = [:]
        for slug in slugsOnDisk() {
            let url = root.appending(path: slug + ".json")
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            usage[slug] = size
        }
        return usage
    }

    /// Delete Data: every key of one app, here and (as tombstones) on the server.
    func deleteAll(for slug: String) async {
        let session = session(slug)
        // Learn of keys written elsewhere first, so they go too.
        await startPull(slug).value
        session.removeAll()
        save(slug)
        await push(slug)
    }

    /// Sign Out: every file, with nothing pushed.
    func reset() async {
        generation += 1
        for task in saveTimers.values { task.cancel() }
        for task in pushTimers.values { task.cancel() }
        saveTimers = [:]
        pushTimers = [:]
        pushes = [:]
        pulls = [:]
        sessions = [:]
        saved = [:]
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Sessions and files

    private func session(_ slug: String) -> DBSession {
        if let session = sessions[slug] { return session }
        let session = DBSession(slug: slug, file: readFile(slug) ?? DBSession.File()) { [weak self] in
            Task { await self?.didWrite(slug) }
        }
        sessions[slug] = session
        saved[slug] = session.version
        return session
    }

    private func fileURL(_ slug: String) -> URL? {
        AppCache.isFileSafe(slug) ? root.appending(path: slug + ".json", directoryHint: .notDirectory) : nil
    }

    private func readFile(_ slug: String) -> DBSession.File? {
        guard let url = fileURL(slug), let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(DBSession.File.self, from: data)
    }

    private func slugsOnDisk() -> [String] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path(percentEncoded: false))) ?? []
        return names.filter { $0.hasSuffix(".json") }.map { String($0.dropLast(".json".count)) }
    }

    /// Writes the session's file now, if it changed since the last save.
    private func save(_ slug: String) {
        saveTimers.removeValue(forKey: slug)?.cancel()
        guard let session = sessions[slug], let url = fileURL(slug), saved[slug] != session.version else { return }
        let (data, version) = session.encoded()
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            saved[slug] = version
        } catch {
            // Kept in memory; the next save tries again.
        }
    }

    private func didWrite(_ slug: String) {
        guard sessions[slug] != nil else { return }
        if saveTimers[slug] == nil {
            let delay = saveDelay
            saveTimers[slug] = Task { [weak self] in
                guard (try? await Task.sleep(for: delay)) != nil else { return }
                await self?.save(slug)
            }
        }
        pushTimers[slug]?.cancel()
        let delay = pushDelay
        pushTimers[slug] = Task { [weak self] in
            guard (try? await Task.sleep(for: delay)) != nil else { return }
            await self?.push(slug)
        }
    }

    // MARK: Sync

    /// Pushes the app's dirty keys, after any push of it already under way.
    private func push(_ slug: String) async {
        pushTimers.removeValue(forKey: slug)?.cancel()
        let previous = pushes[slug]
        let task = Task {
            await previous?.value
            await self.pushOnce(slug)
        }
        pushes[slug] = task
        await task.value
        if pushes[slug] == task { pushes[slug] = nil }
    }

    private func pushOnce(_ slug: String) async {
        guard let api = api(), let session = sessions[slug], let batch = session.pendingBatch() else { return }
        let generation = self.generation
        guard let rev = try? await api.push(to: slug, set: batch.set, delete: batch.delete) else { return }
        guard generation == self.generation, sessions[slug] === session else { return }
        session.pushed(batch, rev: rev)
        save(slug)
    }

    /// The pull under way for an app, or a new one.
    private func startPull(_ slug: String) -> Task<Void, Never> {
        if let pull = pulls[slug] { return pull }
        let pull = Task { await self.pullOnce(slug) }
        pulls[slug] = pull
        return pull
    }

    private func pullOnce(_ slug: String) async {
        defer { pulls[slug] = nil }
        guard let api = api() else { return }
        let session = session(slug)
        let generation = self.generation
        let start = session.pullStart()
        guard let changes = try? await api.changes(for: slug, since: start.rev) else { return }
        guard generation == self.generation, sessions[slug] === session else { return }
        if session.merge(changes, startedAt: start.writeCount) { save(slug) }
    }

    /// Waits for `task`, or for `timeout`, whichever ends first. The task keeps
    /// running either way.
    private static func wait(for task: Task<Void, Never>, atMost timeout: Duration) async {
        let once = Once()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            Task {
                await task.value
                if once.claim() { continuation.resume() }
            }
            Task {
                try? await Task.sleep(for: timeout)
                if once.claim() { continuation.resume() }
            }
        }
    }
}

/// True for the first caller only.
private final class Once: Sendable {
    private let claimed = Mutex(false)

    func claim() -> Bool {
        claimed.withLock { claimed in
            defer { claimed = true }
            return !claimed
        }
    }
}
