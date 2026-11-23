import Network
import Observation
import SwiftUI

/// The state of one New App or Change… sheet: the idea, the key that lets an
/// agent install it, and the pasted reply on its way to becoming an app.
@MainActor
@Observable
final class CreateModel {
    /// The app being changed, or nil for a new one.
    let app: CachedApp?
    /// The app's source when the sheet opened; what the change prompt carries.
    let currentSource: String

    var idea = ""
    private(set) var key: API.InstallKey?
    private(set) var didCopy = false

    /// What the pasted reply parsed into. Non-nil means the preview is up.
    private(set) var reply: ParsedReply?
    var name = ""
    var slug = ""
    private(set) var compileError: CompileError?

    private(set) var isInstalling = false
    private(set) var failure: String?
    /// Counts up when an install succeeds, here or by an agent.
    private(set) var installs = 0
    private(set) var isFinished = false
    private(set) var rejections = 0

    @ObservationIgnored private var copiedTask: Task<Void, Never>?
    private static let keyPoll: Duration = .seconds(3)

    /// Who the preview asks for permissions as (plan §4.0). Changing an app
    /// previews the app itself, so it asks as the app, and its answers are
    /// the app's. A new app asks as a slug of its own that no app can have
    /// (`PermissionLedger.previewPrefix`), so it never answers for an
    /// installed one: Install moves its answers to the slug it's installed
    /// as, and closing the sheet without installing forgets them.
    let permissionSlug: String

    init(app: CachedApp?, source: String?) {
        self.app = app
        currentSource = source ?? ""
        permissionSlug = app?.slug ?? PermissionLedger.previewPrefix + UUID().uuidString
    }

    var isChange: Bool { app != nil }
    var hasIdea: Bool { !idea.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    // MARK: Prompt

    private var install: Prompts.Install? {
        guard let key, key.expires > .now else { return nil }
        var origin = Account.site.absoluteString
        while origin.hasSuffix("/") { origin.removeLast() }
        return Prompts.Install(origin: origin, key: key.key, expires: key.expires)
    }

    func prompt(includeSource: Bool) -> String {
        let idea = idea.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let app else { return Prompts.newApp(idea: idea, install: install) }
        return Prompts.change(idea, slug: app.slug, source: currentSource, includeSource: includeSource, install: install)
    }

    func copy(includeSource: Bool) {
        UIPasteboard.general.string = prompt(includeSource: includeSource)
        didCopy = true
        copiedTask?.cancel()
        copiedTask = Task { [weak self] in
            try? await Task.sleep(for: Motion.copiedStay)
            if !Task.isCancelled { self?.didCopy = false }
        }
    }

    // MARK: Install key

    /// Mints the key when the sheet opens, so Copy Prompt never waits. Offline,
    /// there is no key and the prompt goes out without its Installing section.
    func mint(library: LibraryStore) async {
        guard key == nil, let api = library.api else { return }
        key = try? await KeyRing.shared.key(for: app?.slug, api: api)
    }

    /// Checks whether an agent has used the key. Runs while the sheet is open
    /// and Shelf is in front, and once more each time Shelf comes back.
    func watch(library: LibraryStore) async {
        while !Task.isCancelled, !isFinished {
            if let key, let api = library.api, let status = try? await api.keyStatus(key.id) {
                switch status {
                case .used:
                    KeyRing.shared.forget(key)
                    installs += 1
                    isFinished = true
                    Task { await library.sync() }
                    return
                case .expired:
                    KeyRing.shared.forget(key)
                    self.key = nil
                    await mint(library: library)
                case .waiting:
                    break
                }
            }
            try? await Task.sleep(for: Self.keyPoll)
        }
    }

    // MARK: Paste and preview

    func paste(_ text: String, library: LibraryStore) {
        let parsed = ReplyParser.parse(text)
        guard !parsed.source.isEmpty else {
            rejections += 1
            return
        }
        compileError = nil
        failure = nil
        name = Self.fitting(parsed.name ?? app?.meta.name ?? "")
        slug = app?.slug ?? freeSlug(parsed.slug, in: library)
        withAnimation(Motion.standard) { reply = parsed }
    }

    func discardReply() {
        withAnimation(Motion.standard) { reply = nil }
    }

    func previewFailed(_ error: CompileError) {
        compileError = error
    }

    /// The longest name an app can have.
    static let nameLimit = 32

    static func fitting(_ name: String) -> String {
        String(name.prefix(nameLimit))
    }

    /// `habits`, then `habits-2`, `habits-3`… until one is free.
    private func freeSlug(_ base: String, in library: LibraryStore) -> String {
        var candidate = base
        var n = 2
        while library.app(candidate) != nil {
            candidate = "\(base)-\(n)"
            n += 1
        }
        return candidate
    }

    /// The app as it will be saved, for the preview and its icon.
    var previewMeta: AppMeta? {
        guard let reply else { return nil }
        let icon = reply.icon.flatMap { Symbol.resolve($0) == $0 ? $0 : nil }
        return AppMeta(slug: slug.isEmpty ? "preview" : slug, name: name.isEmpty ? "App" : name, icon: icon,
                       tint: reply.tint)
    }

    /// The preview as the permission sheet shows it: the name in the field,
    /// or "New App" while there isn't one, with the icon it will install with.
    var permissionIdentity: AppMeta {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return AppMeta(slug: permissionSlug, name: trimmed.isEmpty ? (app?.meta.name ?? "New App") : trimmed,
                       icon: previewMeta?.icon ?? app?.meta.icon, tint: reply?.tint ?? app?.meta.tint ?? .blue)
    }

    /// The preview's permissions, for its run context (§1.7): the real
    /// capabilities, after the same sheet an installed app gets.
    func previewPermissions(_ gate: PermissionGate) -> GatedAppPermissions {
        GatedAppPermissions(gate: gate) { [weak self] in
            self?.permissionIdentity ?? AppMeta(slug: PermissionLedger.previewPrefix, name: "New App")
        }
    }

    /// The sheet has closed. A sheet still up for the preview goes, and a
    /// new app that wasn't installed takes its answers with it.
    func closed(_ gate: PermissionGate) {
        gate.cancelRequests(for: permissionSlug)
        if !isChange { gate.forget(permissionSlug) }
    }

    var isSlugValid: Bool {
        slug.wholeMatch(of: /[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}/) != nil
    }

    func isSlugTaken(in library: LibraryStore) -> Bool {
        !isChange && library.app(slug) != nil
    }

    func canInstall(in library: LibraryStore) -> Bool {
        reply != nil && !isInstalling && compileError == nil && isSlugValid && !isSlugTaken(in: library)
            && !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    func installReply(library: LibraryStore) async {
        guard let reply, let meta = previewMeta, canInstall(in: library) else { return }
        isInstalling = true
        failure = nil
        defer { isInstalling = false }
        do throws(API.Failure) {
            try await library.install(slug: slug, name: name.trimmingCharacters(in: .whitespaces), icon: meta.icon,
                                      tint: reply.tint, source: reply.source)
            // What the preview was allowed, the installed app is allowed.
            if !isChange {
                library.permissions.ledger.move(from: permissionSlug, to: slug, name: name.trimmingCharacters(in: .whitespaces))
            }
            // The app went in with the admin token; the key in the prompt is
            // no longer needed and shouldn't stay live.
            if let key, let api = library.api {
                KeyRing.shared.forget(key)
                Task { try? await api.revokeKey(key.id) }
            }
            installs += 1
            isFinished = true
        } catch {
            switch error {
            case .rejected(_, let message): failure = message
            case .unauthorized: failure = "Token Expired"
            case .offline: failure = "Can’t Reach Server"
            }
        }
    }
}

/// Unused install keys, kept while they have time left. Opening the sheet
/// again reuses one instead of minting another; the server allows only
/// twenty live keys at once.
@MainActor
final class KeyRing {
    static let shared = KeyRing()
    private var keys: [String: API.InstallKey] = [:]
    /// A key with less time left than this isn't worth handing to an agent.
    private let minimumLife: TimeInterval = 10 * 60

    func key(for slug: String?, api: API) async throws(API.Failure) -> API.InstallKey {
        // Keys belong to the server that issued them.
        let name = api.origin.absoluteString + " " + (slug ?? "")
        if let held = keys[name], held.expires.timeIntervalSinceNow > minimumLife { return held }
        let minted = try await api.mintKey(for: slug)
        keys[name] = minted
        return minted
    }

    func forget(_ key: API.InstallKey) {
        keys = keys.filter { $0.value.id != key.id }
    }
}

/// Whether the phone has a network at all. Install says "Offline" without one.
@MainActor
@Observable
final class Connectivity {
    static let shared = Connectivity()
    private(set) var isOnline = true
    @ObservationIgnored private let monitor = NWPathMonitor()

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.isOnline = online }
        }
        monitor.start(queue: .global(qos: .utility))
    }
}
