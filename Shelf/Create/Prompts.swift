import Foundation

/// The prompts Shelf copies (plan §9.1 and the Appendix), filled in from the
/// templates in `Resources/Prompts`.
///
/// CONTRACT — signatures are fixed; bodies belong to the Create package.
enum Prompts {
    /// The one-time key that lets an agent install the app itself.
    struct Install: Equatable, Sendable {
        /// The site, with no trailing slash: `https://ij5.dev`.
        var origin: String
        var key: String
        var expires: Date
    }

    /// The new-app prompt. Without `install` (offline, no key) the Installing
    /// section is left out and the rest still works by paste.
    static func newApp(idea: String, install: Install?) -> String { idea }

    /// The change prompt. `includeSource` picks the full source or the outline.
    static func change(_ change: String, slug: String, source: String, includeSource: Bool, install: Install?) -> String { change }
}
