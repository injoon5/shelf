//
//  Accessibility.swift
//  Bridges: accessibility labels and traits
//

import SwiftUI

@objc(KilnBridges_Accessibility)
final class AccessibilityBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        // On a `Tab`, `isEnabled:` too; the `TabView` reads them (Bridges/Navigation/Tabs.swift).
        r.modifier("accessibilityLabel", .accessibility) { m in
            m.form("_:any") { c, view in
                if let s = c.string(0) { view.accessibilityLabel(Text(s)) } else { view }
            }
            m.form("_:any isEnabled:bool?", receiver: "TabContent") { _, view in view }
        }
        r.modifier("accessibilityHint", .accessibility) { m in
            m.form("_:any") { c, view in
                if let s = c.string(0) { view.accessibilityHint(Text(s)) } else { view }
            }
            m.form("_:any isEnabled:bool?", receiver: "TabContent") { _, view in view }
        }
        r.modifier("accessibilityIdentifier", .accessibility) { m in
            m.form("_:string") { c, view in
                if let s = c.string(0) { view.accessibilityIdentifier(s) } else { view }
            }
            m.form("_:string isEnabled:bool?", receiver: "TabContent") { _, view in view }
        }
        r.modifier("accessibilityValue", .accessibility) { m in
            m.form("_:any") { c, view in
                if let s = c.string(0) { view.accessibilityValue(Text(s)) } else { view }
            }
            m.form("_:any isEnabled:bool?", receiver: "TabContent") { _, view in view }
        }
        r.modifier("accessibilityInputLabels", .accessibility) { m in
            m.form("_:any") { c, view in
                view.accessibilityInputLabels(((try? c.interp.sequence(c[0] ?? .array([]))) ?? []).compactMap { c.r.string($0) }.map { Text($0) })
            }
            m.form("_:any isEnabled:bool?", receiver: "TabContent") { _, view in view }
        }
        r.modifier("accessibilityAddTraits", .accessibility, support: .stub) { m in m.stub(["_:any"]) }
        r.modifier("accessibilityElement", .accessibility, support: .stub) { m in m.stub(["children:any?"]) }
        r.modifier("accessibilityHidden", .accessibility, support: .stub) { m in m.stub(["_:bool"]) }
    }
}
