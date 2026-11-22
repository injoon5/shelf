import SwiftUI

/// The fixed list of icon colours the server accepts. They are names rather
/// than hex codes so each one maps to a system colour, which adapts to light
/// and dark mode on its own.
enum Tint: String, CaseIterable, Codable, Sendable {
    case red, orange, yellow, green, mint, teal, cyan, blue, indigo, purple, pink, brown, gray

    /// An unknown name falls back to blue, the same rule the parser uses.
    init(name: String) {
        self = Tint(rawValue: name.trimmingCharacters(in: .whitespaces).lowercased()) ?? .blue
    }

    init(from decoder: Decoder) throws {
        self.init(name: try decoder.singleValueContainer().decode(String.self))
    }

    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .cyan: .cyan
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}
