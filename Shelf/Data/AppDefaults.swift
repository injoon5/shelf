import Foundation
import Synchronization

/// Each app's settings: its own `UserDefaults` suite, which its
/// `@AppStorage` and `UserDefaults.standard` resolve to (plan §1.7), so two
/// apps that both store `"count"` never see each other's, and nothing of
/// Shelf's own is within an app's reach.
///
/// Before §1.7 every app's keys were in Shelf's own `UserDefaults.standard`,
/// as `kiln.app.{slug}.{key}` (`SourceRewriter` scoped each key to its app).
/// The first time an app's suite is opened, those keys move into it.
struct AppDefaults: @unchecked Sendable {
    /// Where the keys were before §1.7. `UserDefaults` is thread-safe; it
    /// just isn't marked `Sendable`.
    let legacy: UserDefaults
    /// What every app's suite name starts with.
    let prefix: String

    /// What Kiln put in front of every `@AppStorage` key before §1.7.
    static let legacyPrefix = "kiln.app."

    static let standard = AppDefaults(legacy: .standard, prefix: "shelf.app.")

    init(legacy: UserDefaults, prefix: String) {
        self.legacy = legacy
        self.prefix = prefix
    }

    /// Suites opened this launch, so `removeAll` finds them even before
    /// their file is on disk.
    private static let opened = Mutex(Set<String>())

    func suiteName(for slug: String) -> String {
        prefix + slug
    }

    /// The app's own settings, with anything it kept before §1.7 moved in.
    func suite(for slug: String) -> UserDefaults {
        let name = suiteName(for: slug)
        Self.opened.withLock { _ = $0.insert(name) }
        let suite = UserDefaults(suiteName: name) ?? UserDefaults()
        migrate(slug, into: suite)
        return suite
    }

    /// Moves `kiln.app.{slug}.{key}` from the shared defaults into the
    /// app's suite as `{key}`, once: what moves is gone from the shared ones.
    /// A value the app has already set in its suite wins.
    func migrate(_ slug: String, into suite: UserDefaults) {
        let old = Self.legacyPrefix + slug + "."
        for (key, value) in legacy.dictionaryRepresentation() where key.hasPrefix(old) {
            let name = String(key.dropFirst(old.count))
            if !name.isEmpty, suite.object(forKey: name) == nil {
                suite.set(value, forKey: name)
            }
            legacy.removeObject(forKey: key)
        }
    }

    /// Delete App: the app's suite, and anything it still had in the shared
    /// defaults.
    func remove(slug: String) {
        legacy.removePersistentDomain(forName: suiteName(for: slug))
        removeLegacy(prefix: Self.legacyPrefix + slug + ".")
    }

    /// Sign Out: every app's suite, and every key Kiln kept before §1.7.
    func removeAll() {
        var names = Self.opened.withLock { $0.filter { $0.hasPrefix(prefix) } }
        let preferences = URL.libraryDirectory.appending(path: "Preferences", directoryHint: .isDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(atPath: preferences.path(percentEncoded: false))) ?? []
        for file in files where file.hasPrefix(prefix) && file.hasSuffix(".plist") {
            names.insert(String(file.dropLast(".plist".count)))
        }
        for name in names { legacy.removePersistentDomain(forName: name) }
        removeLegacy(prefix: Self.legacyPrefix)
    }

    private func removeLegacy(prefix: String) {
        for key in legacy.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            legacy.removeObject(forKey: key)
        }
    }
}
