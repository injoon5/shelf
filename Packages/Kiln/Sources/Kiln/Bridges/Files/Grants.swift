//
//  Grants.swift
//  Bridges: files the person handed the app (PLAN.md §4.1)
//
//  An app's code reads and writes only inside its own folder (`KilnFiles`).
//  The exception is what the person picked for it: a file or folder from
//  `.fileImporter`, where `.fileMover` put one, a file dropped on it. Those
//  URLs are outside the folder, and the app may use them while it runs,
//  as a compiled app may use the security-scoped URLs a picker returns.
//
//  Kiln starts security-scoped access when it hands such a URL to the app,
//  and stops it when the app's screen closes. So the app's own
//  `url.startAccessingSecurityScopedResource()` answers `true` for a picked
//  URL (and `false` for anything else, as iOS does for a URL that isn't
//  security-scoped), and its `stopAccessing…` changes nothing.
//

import Foundation

@MainActor
final class KFileGrants {
    /// Each picked URL, and whether security-scoped access was started for it.
    private var granted: [String: (url: URL, started: Bool)] = [:]

    private init() {}

    /// The run's grants, made (and its teardown registered) when first used.
    static func of(_ context: KilnContext) -> KFileGrants {
        if let grants = context.provided(KFileGrants.self) { return grants }
        let grants = KFileGrants()
        context.provide(grants)
        context.onTearDown { grants.revokeAll() }
        return grants
    }

    /// The person picked `url` for the app: it may read and write it (and
    /// what's inside, for a folder) until the run ends.
    func grant(_ url: URL) {
        let key = Self.key(url)
        guard granted[key] == nil else { return }
        let started = url.startAccessingSecurityScopedResource()
        granted[key] = (url, started)
    }

    /// `url` if the person picked it, or picked a folder it's in.
    func allows(_ url: URL) -> URL? {
        guard url.isFileURL else { return nil }
        let path = Self.key(url)
        let picked = granted.keys.contains { key in path == key || path.hasPrefix(key == "/" ? key : key + "/") }
        return picked ? url.standardizedFileURL : nil
    }

    var isEmpty: Bool { granted.isEmpty }

    private func revokeAll() {
        for (_, entry) in granted where entry.started { entry.url.stopAccessingSecurityScopedResource() }
        granted = [:]
    }

    private static func key(_ url: URL) -> String {
        let p = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        return p.count > 1 && p.hasSuffix("/") ? String(p.dropLast()) : p
    }
}

extension KilnContext {
    /// A URL the app's code names, as a file it may touch: in its folder, or
    /// one the person picked for it.
    @MainActor func resolveFile(_ url: URL) throws -> URL {
        if !url.isFileURL { return try files.resolve(url) }
        if let grants = provided(KFileGrants.self), let picked = grants.allows(url) { return picked }
        return try files.resolve(url)
    }
}
