import Foundation

/// A short description of an app for the change prompt when its full source
/// is left out (plan §9.2): header lines, every saved type in full, the `DB`
/// and `@AppStorage` key names, and every other type and function as a
/// signature with its body replaced by `{ … }`. No model is involved.
///
/// CONTRACT — signatures are fixed; bodies belong to the Create package.
enum Outline {
    static func make(from source: String) -> String { source }
}
