import Foundation

/// Who Shelf is signed in as: a site and a token. Readable from any thread,
/// because the sync engine and the data store ask for it off the main actor.
enum Account {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cached: API??

    static let defaultSite = URL(string: "https://ij5.dev")!

    /// Shelf's settings live in their own suite. `UserDefaults.standard` is
    /// shared with every app Kiln runs, so nothing of Shelf's goes there.
    /// (`UserDefaults` is thread-safe; it just isn't marked `Sendable`.)
    nonisolated(unsafe) static let defaults = UserDefaults(suiteName: "dev.ij5.shelf.settings")!

    static var site: URL {
        defaults.url(forKey: "site") ?? defaultSite
    }

    /// Nil while signed out.
    static var api: API? {
        lock.withLock {
            if let cached { return cached }
            let api = Keychain.token.map { API(origin: site, token: $0) }
            cached = .some(api)
            return api
        }
    }

    /// Whether two addresses name the same site, however they were typed:
    /// `https://IJ5.dev/` is `https://ij5.dev`.
    static func isSameSite(_ a: URL, _ b: URL) -> Bool {
        func parts(_ url: URL) -> [String] {
            var path = url.path(percentEncoded: true)
            while path.hasSuffix("/") { path.removeLast() }
            return [url.scheme?.lowercased() ?? "", url.host()?.lowercased() ?? "", url.port.map(String.init) ?? "", path]
        }
        return parts(a) == parts(b)
    }

    static func signIn(site: URL, token: String) {
        lock.withLock {
            defaults.set(site, forKey: "site")
            Keychain.token = token
            // Held in memory too, so this launch works even if the Keychain refused the write.
            cached = .some(API(origin: site, token: token))
        }
    }

    static func signOut() {
        lock.withLock {
            Keychain.token = nil
            cached = nil
        }
    }
}
