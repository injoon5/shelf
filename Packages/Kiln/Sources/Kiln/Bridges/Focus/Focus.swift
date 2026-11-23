//
//  Focus.swift
//  Bridges: focus and the keyboard
//

import SwiftUI

@objc(KilnBridges_Focus)
final class FocusBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        r.modifier("focused", .focus, support: .stub, notes: "Accepted; `@FocusState` doesn't move the keyboard focus yet.") { m in
            m.stub(["_:binding", "_:binding equals:any"])
        }
        r.modifier("onSubmit", .focus) { m in
            m.form("of:any? _:action") { c, view in view.onSubmit(c.action(0)) }
        }
        r.modifier("submitLabel", .focus, support: .partial, notes: "Always `.done`.") { m in
            m.form("_:SubmitLabel") { _, view in view.submitLabel(.done) }
        }
        r.modifier("keyboardType", .focus) { m in
            m.form("_:UIKeyboardType") { c, view in
                #if os(iOS)
                let types: [String: UIKeyboardType] = ["decimalPad": .decimalPad, "numberPad": .numberPad, "emailAddress": .emailAddress,
                    "phonePad": .phonePad, "URL": .URL, "twitter": .twitter, "asciiCapable": .asciiCapable, "numbersAndPunctuation": .numbersAndPunctuation]
                if let n = c.symbol(0) { view.keyboardType(types[n] ?? .default) } else { view }
                #else
                view
                #endif
            }
        }
        r.modifier("textInputAutocapitalization", .focus) { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                if let n = c.symbol(0) {
                    view.textInputAutocapitalization(n == "never" ? .never : (n == "words" ? .words : (n == "characters" ? .characters : .sentences)))
                } else {
                    view
                }
                #else
                view
                #endif
            }
        }
        r.modifier("autocorrectionDisabled", .focus) { m in
            m.form("_:bool?") { _, view in view.autocorrectionDisabled() }
        }
        r.modifier("textContentType", .focus, support: .stub) { m in m.stub(["_:any"]) }
        r.wrapper("FocusedValue", .focus, support: .stub, notes: "Reads its `@Entry` default; focused views don't set it yet.")
        r.modifier("focusedValue", .focus, support: .stub, notes: "Accepted; `@FocusedValue` reads its `@Entry` default.") { m in
            m.stub(["_:any _:any"])
        }
        r.modifier("scrollDismissesKeyboard", .focus, support: .stub) { m in m.stub(["_:any"]) }
    }
}
