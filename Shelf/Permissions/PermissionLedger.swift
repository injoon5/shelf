import Foundation
import Observation

/// Each app's answers (plan §4.0): for every capability, not asked yet,
/// allowed or denied. "Not asked" is the absence of an answer.
///
/// It lives on this phone only, in `Application Support/permissions.json`,
/// and is never synced: a grant is to this device, as iOS's own are, and an
/// app on another phone asks again there. Delete App, a sync that finds an
/// app gone (`AppCleanup`, "permission grants") and Sign Out clear it.
///
/// The file is written in a form that survives other builds of Shelf. An
/// answer is stored as its capability's raw value and the answer's, both
/// strings, and the ones this build doesn't know (a capability a newer build
/// added) are read back and written again untouched, so going back a build
/// and forward again loses nothing. A file that can't be read at all counts
/// as empty: every app asks again, which is the safe way to fail.
@MainActor
@Observable
final class PermissionLedger {
    enum Answer: String, Sendable, Equatable {
        case allowed
        case denied
    }

    /// One app's answers, as stored.
    struct Entry: Equatable, Sendable {
        /// The app's name when it last asked, for Settings when the library
        /// doesn't have the app (yet).
        var name: String
        /// Capability raw value → answer raw value. Strings, so a newer
        /// build's capabilities and answers survive this one.
        var answers: [String: String]
    }

    /// The file's format. Bumped only for a change an older build couldn't
    /// read; adding a capability or an answer isn't one.
    static let version = 1

    /// Slugs the New App preview asks under start with this. No slug can
    /// hold a ":", so a preview never answers for an installed app.
    static let previewPrefix = "preview:"

    /// Where the phone's ledger lives.
    static let standardFile = URL.applicationSupportDirectory.appending(path: "permissions.json")

    /// Slug → its answers.
    private(set) var entries: [String: Entry]
    /// Nil keeps it in memory only: tests, and the stub gate.
    @ObservationIgnored let file: URL?

    init(file: URL?) {
        self.file = file
        entries = file.flatMap(Self.read) ?? [:]
        // A preview never outlives the sheet it ran in. One left over (Shelf
        // quit with the sheet up) is dropped.
        if entries.keys.contains(where: Self.isPreview) {
            entries = entries.filter { !Self.isPreview($0.key) }
            save()
        }
    }

    static func isPreview(_ slug: String) -> Bool {
        slug.hasPrefix(previewPrefix)
    }

    // MARK: Reading

    func answer(_ capability: Capability, for slug: String) -> Answer? {
        entries[slug]?.answers[capability.rawValue].flatMap(Answer.init(rawValue:))
    }

    /// Every app that has an answer for `capability`, by name. Previews
    /// aren't apps yet and aren't listed.
    func apps(for capability: Capability) -> [(slug: String, name: String, answer: Answer)] {
        entries.compactMap { slug, entry in
            guard !Self.isPreview(slug), let answer = answer(capability, for: slug) else { return nil }
            return (slug, entry.name, answer)
        }
        .sorted {
            switch $0.name.localizedStandardCompare($1.name) {
            case .orderedAscending: true
            case .orderedDescending: false
            case .orderedSame: $0.slug < $1.slug
            }
        }
    }

    // MARK: Writing

    /// Records `answer` for `slug` (nil forgets it: not asked again), and
    /// the name the app had.
    func set(_ answer: Answer?, _ capability: Capability, for slug: String, name: String) {
        guard !slug.isEmpty else { return }
        var entry = entries[slug] ?? Entry(name: name, answers: [:])
        if !name.isEmpty { entry.name = name }
        entry.answers[capability.rawValue] = answer?.rawValue
        entries[slug] = entry.answers.isEmpty ? nil : entry
        save()
    }

    /// The New App preview's answers become the installed app's. An answer
    /// the app already has wins, though a new app has none.
    func move(from preview: String, to slug: String, name: String) {
        guard preview != slug, let moved = entries[preview] else { return }
        var entry = entries[slug] ?? Entry(name: name, answers: [:])
        entry.name = name.isEmpty ? moved.name : name
        entry.answers.merge(moved.answers) { kept, _ in kept }
        entries[slug] = entry
        entries[preview] = nil
        save()
    }

    /// Everything `slug` was answered. Safe to run twice, or for an app
    /// that never asked.
    func remove(_ slug: String) {
        guard entries[slug] != nil else { return }
        entries[slug] = nil
        save()
    }

    /// Sign Out: every app's answers, and the file.
    func removeAll() {
        entries = [:]
        if let file { try? FileManager.default.removeItem(at: file) }
    }

    // MARK: The file

    private struct Stored: Codable {
        var version: Int
        var apps: [String: StoredApp]
    }

    private struct StoredApp: Codable {
        var name: String?
        var answers: [String: String]?
    }

    private static func read(_ file: URL) -> [String: Entry]? {
        guard let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return nil }
        var entries: [String: Entry] = [:]
        for (slug, app) in stored.apps where !slug.isEmpty {
            let answers = app.answers ?? [:]
            guard !answers.isEmpty else { continue }
            entries[slug] = Entry(name: app.name ?? slug, answers: answers)
        }
        return entries
    }

    private func save() {
        guard let file else { return }
        if entries.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        let stored = Stored(version: Self.version,
                            apps: entries.mapValues { StoredApp(name: $0.name, answers: $0.answers) })
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        guard let data = try? encoder.encode(stored) else { return }
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A failed write leaves this launch right and the next one asking
        // again, which is safe.
        try? data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
}
