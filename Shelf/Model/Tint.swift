import Foundation

/// The fixed list of icon colours the server accepts. They are names rather
/// than hex codes so each one maps to a system colour, which adapts to light
/// and dark mode on its own.
enum Tint: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    /// An unknown name falls back to blue, from the server or a pasted reply.
    init(name: String) {
        self = Tint(rawValue: name.trimmingCharacters(in: .whitespaces).lowercased()) ?? .blue
    }

    init(from decoder: Decoder) throws {
        self.init(name: try decoder.singleValueContainer().decode(String.self))
    }
}
