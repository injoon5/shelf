import Foundation

/// Where apps' `@AppStorage` values are. Kiln keeps them all in one shared
/// `UserDefaults`, as `kiln.app.{key}`; `SourceRewriter` scopes each key to
/// its app first, so an app's keys are `kiln.app.{slug}.{key}`.
struct AppStorageKeys: @unchecked Sendable {
    /// What Kiln puts in front of every `@AppStorage` key.
    private static let kilnPrefix = "kiln.app."

    /// What `SourceRewriter` puts in front of each of an app's keys.
    static func scope(_ slug: String) -> String {
        slug + "."
    }

    // `UserDefaults` is thread-safe; it just isn't marked `Sendable`.
    let defaults: UserDefaults

    init(_ defaults: UserDefaults) {
        self.defaults = defaults
    }

    func remove(slug: String) {
        remove(prefix: Self.kilnPrefix + Self.scope(slug))
    }

    func removeAll() {
        remove(prefix: Self.kilnPrefix)
    }

    private func remove(prefix: String) {
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix(prefix) {
            defaults.removeObject(forKey: key)
        }
    }
}
