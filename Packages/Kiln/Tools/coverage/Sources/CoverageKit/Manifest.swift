// `kiln-manifest.json`: what Kiln supports. Documented in Packages/Kiln/Docs/manifest.md.
// §1.4's registry exports it; until then InterimManifest derives one from the
// engine's switch statements.

import Foundation

public enum Support: String, Codable, Sendable {
    /// Every overload the manifest lists behaves as in SwiftUI.
    case full
    /// Some forms work; `notes` says which. The interim manifest marks everything it finds this way.
    case partial
    /// Accepted so code compiles in Kiln, but it has no effect (`.gesture` in 0.2.1).
    case stub
}

public struct ManifestOverload: Codable, Equatable, Sendable {
    /// Argument labels in order, `_` for an unlabelled argument: `["_", "in"]`.
    public var labels: [String]
    /// For modifiers, the receiver it's bridged on (`View`, `Shape`, `Text`, `ChartContent`). Omitted: any.
    public var receiver: String?
    /// The minimum iOS version for this overload, if later than the symbol's.
    public var introduced: String?
    public var notes: String?

    public init(labels: [String], receiver: String? = nil, introduced: String? = nil, notes: String? = nil) {
        self.labels = labels; self.receiver = receiver; self.introduced = introduced; self.notes = notes
    }
}

public struct ManifestSymbol: Codable, Equatable, Sendable {
    /// Same scheme as the coverage report: `view:DatePicker`, `modifier:padding`,
    /// `modifier:ToolbarContent.visibilityPriority`, `style:ButtonStyle.glass`, `member:Animation.spring`.
    public var id: String
    public var kind: SymbolKind
    public var name: String
    public var owner: String?
    /// One of the families in Tools/coverage/families.json (the registry's folder name).
    public var family: String
    public var support: Support
    /// The minimum iOS version Kiln offers it on (the SDK's, unless the bridge needs later).
    public var introduced: String?
    /// The overloads bridged. `nil` means "not enumerated" (the interim manifest); `[]` is a property or bare member.
    public var overloads: [ManifestOverload]?
    /// Shown to app authors in the prompt: limits, what to use instead.
    public var notes: String?
    /// Where it's implemented, for maintainers (`Bridges/Controls/DatePicker.swift`).
    public var source: String?

    public init(id: String, kind: SymbolKind, name: String, owner: String? = nil, family: String, support: Support,
                introduced: String? = nil, overloads: [ManifestOverload]? = nil, notes: String? = nil, source: String? = nil) {
        self.id = id; self.kind = kind; self.name = name; self.owner = owner; self.family = family; self.support = support
        self.introduced = introduced; self.overloads = overloads; self.notes = notes; self.source = source
    }
}

public struct Manifest: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// `true` only for the stand-in derived from the 0.2.1 switch files.
    public var interim: Bool
    /// What produced it: `kiln-registry` (§1.4), or `coverage/interim-switch-scan`.
    public var generator: String
    public var description: String?
    public var symbols: [ManifestSymbol]

    public init(interim: Bool, generator: String, description: String? = nil, symbols: [ManifestSymbol]) {
        self.schemaVersion = Manifest.currentSchemaVersion
        self.interim = interim; self.generator = generator; self.description = description
        self.symbols = symbols.sorted { $0.id < $1.id }
    }

    public static func load(_ url: URL) throws -> Manifest {
        let m = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        guard m.schemaVersion == currentSchemaVersion else {
            throw CoverageError("\(url.lastPathComponent) has schemaVersion \(m.schemaVersion); this tool reads \(currentSchemaVersion).")
        }
        return m
    }

    public func encoded() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self) + Data("\n".utf8)
    }
}

public struct CoverageError: Error, CustomStringConvertible {
    public var description: String
    public init(_ d: String) { description = d }
}
