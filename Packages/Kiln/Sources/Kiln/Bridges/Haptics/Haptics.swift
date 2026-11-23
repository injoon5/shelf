//
//  Haptics.swift
//  Bridges: haptic feedback
//
//  Accepted, with no feedback yet (PLAN.md §3.1 makes them real).
//

import SwiftUI

@objc(KilnBridges_Haptics)
final class HapticsBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.modifier("sensoryFeedback", .haptics, support: .stub, notes: "Accepted; no feedback is played yet.") { m in
            m.stub(["_:any trigger:any", "_:any trigger:any condition:closure", "trigger:any _:closure"])
        }
        for name in ["UIImpactFeedbackGenerator", "UINotificationFeedbackGenerator", "UISelectionFeedbackGenerator"] {
            r.type(name, .haptics, support: .stub, notes: "Accepted; no feedback is played yet.") { t in
                t.initializer { _ in .native(.object("Haptics", KRef(NSObject()))) }
            }
        }
        r.type("Haptics", .haptics) { t in
            t.internal()
            t.anyMethod { _, _ in .void }
        }
    }
}
