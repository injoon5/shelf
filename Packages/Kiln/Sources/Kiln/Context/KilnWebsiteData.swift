//
//  KilnWebsiteData.swift
//  Kiln's run context: each app's own website data (PLAN.md §3.6)
//
//  Every web page an app makes (`WebView(url:)`, `WebPage()`) uses that
//  app's own `WKWebsiteDataStore`, so cookies, local storage and caches
//  never cross between apps:
//
//  - a real run: a persistent store whose identifier is derived from the
//    app's slug (`identifier(for:)`), so it's the same store every time the
//    app opens, and no other app's;
//  - a check (a stub context), or a run the host marks with
//    `context.provide(KilnEphemeralWebsiteData())` (Shelf's try-outs): a
//    store in memory, gone when the run ends.
//
//  The host removes an app's store when the app is deleted
//  (`KilnWebsiteData.remove(for:)`; Shelf's `AppCleanup`).
//

import Foundation
import CryptoKit
#if canImport(WebKit)
import WebKit
#endif

/// Provided by the host to a run whose website data shouldn't outlast it.
public struct KilnEphemeralWebsiteData: Sendable {
    public init() {}
}

public enum KilnWebsiteData {
    /// The identifier of `slug`'s persistent store: a name-based UUID, so the
    /// same app always gets the same store.
    public static func identifier(for slug: String) -> UUID {
        var bytes = Array(SHA256.hash(data: Data("kiln.website-data.\(slug)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5 (name-based)
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }

    /// Removes `slug`'s cookies, storage and caches. Safe for an app that
    /// never opened a page. Fails while a page of it is still open.
    @MainActor
    public static func remove(for slug: String) async throws {
        #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
        let id = identifier(for: slug)
        let existing = await WKWebsiteDataStore.allDataStoreIdentifiers
        guard existing.contains(id) else { return }
        // WebKit's network process lets go of a store a moment after its
        // last page closes: a deletion right after the card closes waits.
        var attempt = 0
        while true {
            do {
                try await WKWebsiteDataStore.remove(forIdentifier: id)
                return
            } catch {
                attempt += 1
                if attempt >= 10 { throw error }
                try await Task.sleep(for: .milliseconds(200))
            }
        }
        #endif
    }

    #if canImport(WebKit) && !os(tvOS) && !os(watchOS)
    /// The store a run's pages use: one per run.
    @MainActor
    static func store(for context: KilnContext) -> WKWebsiteDataStore {
        if let made = context.provided(KWebsiteStore.self)?.store { return made }
        let store: WKWebsiteDataStore
        if context.isStub || context.provided(KilnEphemeralWebsiteData.self) != nil {
            store = .nonPersistent()
        } else {
            store = WKWebsiteDataStore(forIdentifier: identifier(for: context.slug))
        }
        let kept = KWebsiteStore(store: store)
        context.provide(kept)
        // Let go of it with the card, so the app can be deleted.
        context.onTearDown { kept.store = nil }
        return store
    }
    #endif
}

#if canImport(WebKit) && !os(tvOS) && !os(watchOS)
/// A run's store, once made.
@MainActor
final class KWebsiteStore {
    var store: WKWebsiteDataStore?
    init(store: WKWebsiteDataStore) { self.store = store }
}
#endif
