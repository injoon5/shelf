// iOS availability from `@available` attributes.

import Foundation

public struct Version: Comparable, Codable, Sendable, CustomStringConvertible {
    public var parts: [Int]

    public init(_ s: String) {
        parts = s.split(separator: ".").compactMap { Int($0) }
        while parts.count > 1 && parts.last == 0 { parts.removeLast() }
        if parts.isEmpty { parts = [0] }
    }

    public static func < (a: Version, b: Version) -> Bool {
        for k in 0..<max(a.parts.count, b.parts.count) {
            let x = k < a.parts.count ? a.parts[k] : 0
            let y = k < b.parts.count ? b.parts[k] : 0
            if x != y { return x < y }
        }
        return false
    }

    /// `17.0`, `26.1`: always at least major.minor.
    public var description: String {
        parts.count == 1 ? "\(parts[0]).0" : parts.map(String.init).joined(separator: ".")
    }

    /// Apple writes `deprecated: 100000.0` for "will be deprecated, no date yet".
    public var isPlaceholder: Bool { (parts.first ?? 0) >= 9999 }
}

public struct Availability: Equatable, Sendable {
    public var introduced: Version?
    public var deprecated: Version?
    /// `@available(*, deprecated)` or `@available(iOS, deprecated)` with no version.
    public var deprecatedNoVersion = false
    public var unavailable = false
    public var message: String?
    public var renamed: String?

    public init() {}

    public var isDeprecated: Bool { deprecatedNoVersion || (deprecated.map { !$0.isPlaceholder } ?? false) }

    /// Applies a member's own attributes on top of its context's.
    public func refined(by own: Availability) -> Availability {
        var r = self
        if let i = own.introduced { r.introduced = max(i, r.introduced ?? i) }
        if let d = own.deprecated { r.deprecated = r.deprecated.map { min($0, d) } ?? d }
        if own.deprecatedNoVersion { r.deprecatedNoVersion = true }
        if own.unavailable { r.unavailable = true }
        if let m = own.message { r.message = m }
        if let n = own.renamed { r.renamed = n }
        return r
    }

    static let iOSNames: Set<String> = ["iOS", "anyAppleOS"]

    /// Reads every `@available` among `attrs` as it applies to iOS.
    public static func iOS(_ attrs: [Attribute]) -> Availability {
        var a = Availability()
        for attr in attrs where attr.name == "available" {
            guard let args = attr.args else { continue }
            let items = args.splitTopLevel(",")
            guard let first = items.first, !first.isEmpty else { continue }
            let isLongForm = first.count == 1 && items.count > 1 && items.dropFirst().contains { item in
                guard let w = item.first?.text else { return false }
                return ["introduced", "deprecated", "obsoleted", "unavailable", "message", "renamed", "noasync"].contains(w)
            }
            if isLongForm {
                let platform = first[0].text
                guard iOSNames.contains(platform) || platform == "*" else { continue }
                for item in items.dropFirst() {
                    guard let key = item.first?.text else { continue }
                    let value = item.count >= 3 ? Array(item[2...]) : []
                    switch key {
                    case "introduced": if let v = value.first { a.introduced = Version(v.text) }
                    case "deprecated":
                        if let v = value.first { a.deprecated = Version(v.text) } else { a.deprecatedNoVersion = true }
                    case "obsoleted": a.unavailable = true
                    case "unavailable": a.unavailable = true
                    case "message": a.message = value.first.map { unquote($0.text) }
                    case "renamed": a.renamed = value.first.map { unquote($0.text) }
                    default: break
                    }
                }
            } else {
                // Shorthand: `iOS 17.0, macOS 14.0, *`.
                for item in items where item.count >= 2 && iOSNames.contains(item[0].text) {
                    let v = Version(item[1].text)
                    a.introduced = max(v, a.introduced ?? v)
                }
            }
        }
        return a
    }

    static func unquote(_ s: String) -> String {
        var t = s
        if t.hasPrefix("\"") { t.removeFirst() }
        if t.hasSuffix("\"") { t.removeLast() }
        return t
    }
}
