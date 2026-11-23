//
//  Hashing.swift
//  Bridges: Hasher, for an app's own `hash(into:)`
//
//  A type that writes `hash(into:)` is hashed by what it combines (KEProtocols
//  installs the hook), so a `Set` and a dictionary's keys agree with its `==`.
//

import SwiftUI

extension LanguageBridges {
    static func hashing(_ r: KRegistry) {
        r.type("Hasher", .language, notes: "In your own `hash(into:)`: `hasher.combine(id)`.") { t in
            t.initializer { _ in .native(.object("Hasher", KRef(KHasherBox()))) }
            t.method("combine", "_:any") { c in
                c.object(KHasherBox.self)?.combined.append(c.first ?? .void)
                return .void
            }
            t.method("finalize", "") { c in
                var h = Hasher()
                h.combine(c.object(KHasherBox.self)?.combined ?? [])
                return .int(h.finalize())
            }
        }
    }
}
