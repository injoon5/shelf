//
//  Accessibility.swift
//  Bridges: accessibility labels and traits
//

import SwiftUI

@objc(KilnBridges_Accessibility)
final class AccessibilityBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.modifier("accessibilityLabel", .accessibility) { m in
            m.form("_:any") { c, view in
                if let s = c.string(0) { view.accessibilityLabel(Text(s)) } else { view }
            }
        }
        r.modifier("accessibilityHint", .accessibility) { m in
            m.form("_:any") { c, view in
                if let s = c.string(0) { view.accessibilityHint(Text(s)) } else { view }
            }
        }
        r.modifier("accessibilityIdentifier", .accessibility) { m in
            m.form("_:string") { c, view in
                if let s = c.string(0) { view.accessibilityIdentifier(s) } else { view }
            }
        }
        r.modifier("accessibilityValue", .accessibility, support: .stub) { m in m.stub(["_:any"]) }
        r.modifier("accessibilityAddTraits", .accessibility, support: .stub) { m in m.stub(["_:any"]) }
        r.modifier("accessibilityElement", .accessibility, support: .stub) { m in m.stub(["children:any?"]) }
        r.modifier("accessibilityHidden", .accessibility, support: .stub) { m in m.stub(["_:bool"]) }
        r.modifier("help", .accessibility, support: .stub) { m in m.stub(["_:title"]) }
    }
}
