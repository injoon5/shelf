//
//  Units.swift
//  Bridges: measurements
//
//  A stub until PLAN.md §3.4: `Measurement(value:unit:)` is its value.
//

import SwiftUI

@objc(KilnBridges_Units)
final class UnitsBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.type("Measurement", .units, support: .stub, notes: "Just its value for now; units and conversion come in Round 2.") { t in
            t.initializer { c in c.first ?? .nilValue }
        }
    }
}
