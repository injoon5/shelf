//
//  KilnFiles.swift
//  Kiln's run context: the app's own folder
//
//  An app's files live in one folder the host gives it (Shelf's
//  `Application Support/files/<slug>/`), laid out like an iOS app's
//  container so `URL.documentsDirectory` and `.cachesDirectory` stay apart:
//
//      <root>/Documents
//      <root>/Library/Application Support
//      <root>/Library/Caches
//      <root>/tmp
//
//  Every path the app's code reads, writes, lists, moves or deletes goes
//  through `resolve`, and one that leaves the folder (`..`, an absolute
//  path elsewhere, a symbolic link out) is an error with the app's line.
//

import Foundation

public struct KilnFiles: Sendable, Equatable {
    /// The app's folder. Made when the app first uses it.
    public let root: URL

    public init(root: URL) {
        self.root = root.standardizedFileURL
    }

    /// `URL.documentsDirectory`, `FileManager`'s `.documentDirectory`.
    public var documents: URL { folder("Documents") }
    /// `URL.applicationSupportDirectory`.
    public var applicationSupport: URL { folder("Library/Application Support") }
    /// `URL.cachesDirectory`.
    public var caches: URL { folder("Library/Caches") }
    /// `URL.temporaryDirectory`, `FileManager.default.temporaryDirectory`.
    public var temporary: URL { folder("tmp") }
    /// `URL.homeDirectory`: the folder itself.
    public var home: URL { folder("") }

    /// One of the folders above, made if it isn't there yet.
    private func folder(_ path: String) -> URL {
        let url = path.isEmpty ? root : root.appending(path: path, directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Why a path was refused.
    public enum Refusal: Error, Equatable, CustomStringConvertible {
        case outside(String)
        case notAFile(String)

        public var description: String {
            switch self {
            case .outside(let p): return "\(p) is outside the app's folder"
            case .notAFile(let u): return "\(u) isn't a file: read web addresses with URLSession"
            }
        }
    }

    /// `url` as a file in the folder, with `.` and `..` gone and symbolic
    /// links followed, or a refusal when it is anywhere else.
    public func resolve(_ url: URL) throws -> URL {
        guard url.isFileURL else { throw Refusal.notAFile(url.absoluteString) }
        let real = Self.real(url.standardizedFileURL)
        let base = Self.real(root)
        let path = real.path(percentEncoded: false), basePath = base.path(percentEncoded: false)
        let trimmedBase = basePath.hasSuffix("/") ? String(basePath.dropLast()) : basePath
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        guard trimmed == trimmedBase || trimmed.hasPrefix(trimmedBase + "/") else {
            throw Refusal.outside(url.path(percentEncoded: false))
        }
        return real
    }

    /// A path as the app wrote it (`"notes.txt"`, `"/…/Documents/notes.txt"`):
    /// relative to the folder when it isn't absolute.
    public func resolve(path: String) throws -> URL {
        try resolve(path.hasPrefix("/") ? URL(fileURLWithPath: path) : root.appending(path: path))
    }

    /// Bytes the app keeps in its folder, for the host's Settings.
    public func usage() -> Int {
        Self.size(of: root)
    }

    /// Bytes under `url`, every file counted once.
    public static func size(of url: URL) -> Int {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey, .isRegularFileKey]
        guard let walk = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys)) else { return 0 }
        var total = 0
        for case let file as URL in walk {
            guard let values = try? file.resourceValues(forKeys: keys), values.isRegularFile == true else { continue }
            total += values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0
        }
        return total
    }

    /// `url` with its symbolic links followed, as far as it exists: a file
    /// not yet written resolves through its nearest folder that is there.
    static func real(_ url: URL) -> URL {
        var existing = url
        var rest: [String] = []
        while !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)), existing.pathComponents.count > 1 {
            rest.insert(existing.lastPathComponent, at: 0)
            existing.deleteLastPathComponent()
        }
        var resolved = existing.resolvingSymlinksInPath()
        for part in rest { resolved.append(path: part) }
        return resolved.standardizedFileURL
    }
}
