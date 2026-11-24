//
//  Focus.swift
//  Bridges: focus and the keyboard
//
//  `@FocusState` is the host's real `FocusState` (KEHostInputs), so
//  `.focused($field, equals: .email)` and `field = .email` move the keyboard
//  as SwiftUI's do.
//
//  Focused values (`.focusedValue(\.key, v)`, `@FocusedValue(\.key)`) go
//  through a few real `FocusedValues` slots: each key the app names gets one,
//  by name, so reading and writing meet. `@FocusedBinding` reads a binding
//  put there, and `@FocusedObject` and `@FocusedValue(Model.self)` an object
//  put there with `.focusedObject` or `.focusedValue(model)`.
//

import SwiftUI

@objc(KilnBridges_Focus)
final class FocusBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        focus(r)
        focusedValues(r)
        keyboard(r)
        hardwareKeys(r)
    }

    // MARK: Focus

    static func focus(_ r: KRegistry) {
        r.modifier("focused", .focus, notes: "With `@FocusState`: setting it moves the keyboard, and tapping a field sets it.") { m in
            m.form("_:binding") { c, view in
                if let p = c.kbinding(0)?.native as? KFocusProjection { view.focused(p.binding, equals: p.token(.bool(true))) } else { view }
            }
            m.form("_:binding equals:any") { c, view in
                if let p = c.kbinding(0)?.native as? KFocusProjection { view.focused(p.binding, equals: p.token(c["equals"] ?? .nilValue)) } else { view }
            }
        }
        r.modifier("defaultFocus", .focus) { m in
            m.form("_:binding _:any priority:any?") { c, view in
                if let p = c.kbinding(0)?.native as? KFocusProjection {
                    AnyView(view.defaultFocus(p.binding, p.isBool ? p.token(.bool(true)) : p.token(c[1] ?? .nilValue),
                                              priority: c.symbol("priority") == "userInitiated" ? .userInitiated : .automatic))
                } else {
                    view
                }
            }
        }
        r.modifier("searchFocused", .focus, introduced: "18.0") { m in
            m.form("_:binding") { c, view in
                if #available(iOS 18, macOS 15, *), let p = c.kbinding(0)?.native as? KFocusProjection {
                    AnyView(view.searchFocused(p.binding, equals: p.token(.bool(true))))
                } else {
                    view
                }
            }
            m.form("_:binding equals:any") { c, view in
                if #available(iOS 18, macOS 15, *), let p = c.kbinding(0)?.native as? KFocusProjection {
                    AnyView(view.searchFocused(p.binding, equals: p.token(c["equals"] ?? .nilValue)))
                } else {
                    view
                }
            }
        }
        r.modifier("focusable", .focus) { m in
            m.form("_:bool?") { c, view in view.focusable(c.bool(0, default: true)) }
            m.form("_:bool? interactions:any") { c, view in
                let i: FocusInteractions = c.symbol("interactions") == "edit" ? .edit : (c.symbol("interactions") == "activate" ? .activate : .automatic)
                view.focusable(c.bool(0, default: true), interactions: i)
            }
        }
        r.modifier("focusEffectDisabled", .focus) { m in
            m.form("_:bool?") { c, view in view.focusEffectDisabled(c.bool(0, default: true)) }
        }
        r.environmentValue("isFocused", .focus, value: { _ in .bool(false) }, read: { env, _ in .bool(env.isFocused) })
        r.protocolBridge("FocusedValueKey", .focus, support: .full, notes: "Or `@Entry var key: Value?` in `extension FocusedValues`.")
    }

    // MARK: Focused values

    static func focusedValues(_ r: KRegistry) {
        r.wrapper("FocusedValue", .focus, notes: "`\\.key` from `@Entry` in `extension FocusedValues`, or an `@Observable` type.")
        r.wrapper("FocusedBinding", .focus)
        r.wrapper("FocusedObject", .focus)
        r.modifier("focusedValue", .focus) { m in
            m.form("_:any _:any") { c, view in
                if case .native(.keyPath(let comps))? = c[0], let key = comps.last {
                    view.focusedValue(KFocusSlots.keyPath(KFocusSlots.slot(key)), c[1] ?? .nilValue)
                } else {
                    view
                }
            }
            m.form("_:any") { c, view in
                if let obj = c[0], let name = obj.userType?.name { view.focusedValue(KFocusSlots.keyPath(KFocusSlots.slot(name)), obj) } else { view }
            }
        }
        r.modifier("focusedObject", .focus) { m in
            m.form("_:any") { c, view in
                if let obj = c[0], let name = obj.userType?.name { view.focusedValue(KFocusSlots.keyPath(KFocusSlots.slot(name)), obj) } else { view }
            }
        }
    }

    // MARK: The keyboard

    static func keyboard(_ r: KRegistry) {
        r.modifier("onSubmit", .focus) { m in
            m.form("of:any? _:action") { c, view in
                view.onSubmit(of: c.symbol("of") == "search" ? .search : .text, c.action(0))
            }
        }
        r.modifier("submitLabel", .focus) { m in
            m.form("_:SubmitLabel") { c, view in
                let labels: [String: SubmitLabel] = ["done": .done, "go": .go, "send": .send, "join": .join, "route": .route, "search": .search,
                                                     "return": .return, "next": .next, "continue": .continue]
                view.submitLabel(labels[c.symbol(0) ?? "done"] ?? .done)
            }
        }
        r.modifier("submitScope", .focus) { m in
            m.form("_:bool?") { c, view in view.submitScope(c.bool(0, default: true)) }
        }
        r.modifier("keyboardType", .focus) { m in
            m.form("_:UIKeyboardType") { c, view in
                #if os(iOS)
                let types: [String: UIKeyboardType] = ["decimalPad": .decimalPad, "numberPad": .numberPad, "emailAddress": .emailAddress,
                    "phonePad": .phonePad, "URL": .URL, "twitter": .twitter, "asciiCapable": .asciiCapable, "numbersAndPunctuation": .numbersAndPunctuation,
                    "namePhonePad": .namePhonePad, "webSearch": .webSearch, "asciiCapableNumberPad": .asciiCapableNumberPad, "default": .default]
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
        r.modifier("autocapitalization", .focus) { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                let n = c.symbol(0)
                view.autocapitalization(n == "none" ? .none : (n == "words" ? .words : (n == "allCharacters" ? .allCharacters : .sentences)))
                #else
                view
                #endif
            }
        }
        r.modifier("autocorrectionDisabled", .focus) { m in
            m.form("_:bool?") { c, view in view.autocorrectionDisabled(c.bool(0, default: true)) }
        }
        r.modifier("disableAutocorrection", .focus) { m in
            m.form("_:bool?") { c, view in view.autocorrectionDisabled(c.bool(0, default: true)) }
        }
        r.modifier("textContentType", .focus) { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                let n = c.symbol(0) ?? ""
                view.textContentType(n.isEmpty ? nil : UITextContentType(rawValue: KFocusSlots.contentTypes[n] ?? n))
                #else
                view
                #endif
            }
        }
        r.modifier("scrollDismissesKeyboard", .focus) { m in
            m.form("_:any") { c, view in
                switch c.symbol(0) {
                case "immediately": view.scrollDismissesKeyboard(.immediately)
                case "interactively": view.scrollDismissesKeyboard(.interactively)
                case "never": view.scrollDismissesKeyboard(.never)
                default: view.scrollDismissesKeyboard(.automatic)
                }
            }
        }
        r.environmentValue("autocorrectionDisabled", .focus, value: { _ in .bool(false) }, read: { env, _ in .bool(env.autocorrectionDisabled) },
                           write: { env, v, i in env.autocorrectionDisabled = i.truthy(v) })
        r.environmentValue("disableAutocorrection", .focus, value: { _ in .nilValue }, read: { env, _ in env.autocorrectionDisabled ? .bool(true) : .nilValue })
        r.environmentValue("scrollDismissesKeyboardMode", .focus, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
            .native(.implicit(String(describing: env.scrollDismissesKeyboardMode).replacingOccurrences(of: "ScrollDismissesKeyboardMode.", with: ""), []))
        })
        r.environmentValue("textContentType", .focus, value: { _ in .nilValue }, read: { _, _ in .nilValue })
    }

    // MARK: Hardware keyboards

    static func hardwareKeys(_ r: KRegistry) {
        r.modifier("keyboardShortcut", .focus, notes: "With a hardware keyboard.") { m in
            m.form("_:any") { c, view in
                switch c.symbol(0) {
                case "defaultAction": AnyView(view.keyboardShortcut(.defaultAction))
                case "cancelAction": AnyView(view.keyboardShortcut(.cancelAction))
                default:
                    if let key = KFocusSlots.key(c[0]) { AnyView(view.keyboardShortcut(key)) } else { view }
                }
            }
            m.form("_:any modifiers:any? localization:any?") { c, view in
                if let key = KFocusSlots.key(c[0]) { AnyView(view.keyboardShortcut(key, modifiers: KFocusSlots.modifiers(c["modifiers"]))) } else { view }
            }
        }
        r.modifier("onKeyPress", .focus, notes: "With a hardware keyboard, on a focused view.") { m in
            m.form("_:any action:closure") { c, view in
                if let key = KFocusSlots.key(c[0]), case .function(let fn)? = c["action"] {
                    let interp = c.interp
                    AnyView(view.onKeyPress(key) { KFocusSlots.result(interp, fn, []) })
                } else {
                    view
                }
            }
            m.form("_:any phases:any action:closure") { c, view in
                if let key = KFocusSlots.key(c[0]), case .function(let fn)? = c["action"] {
                    let interp = c.interp
                    AnyView(view.onKeyPress(key, phases: KFocusSlots.phases(c["phases"])) { press in KFocusSlots.result(interp, fn, [KFocusSlots.press(press)]) })
                } else {
                    view
                }
            }
            m.form("keys:any phases:any? action:closure") { c, view in
                if case .function(let fn)? = c["action"] {
                    let interp = c.interp
                    let keys = Set(((try? c.interp.sequence(c["keys"] ?? .array([]))) ?? []).compactMap { KFocusSlots.key($0) })
                    AnyView(view.onKeyPress(keys: keys, phases: KFocusSlots.phases(c["phases"])) { press in KFocusSlots.result(interp, fn, [KFocusSlots.press(press)]) })
                } else {
                    view
                }
            }
            m.form("characters:any phases:any? action:closure") { c, view in
                if case .function(let fn)? = c["action"] {
                    let interp = c.interp
                    AnyView(view.onKeyPress(characters: .alphanumerics, phases: KFocusSlots.phases(c["phases"])) { press in
                        KFocusSlots.result(interp, fn, [KFocusSlots.press(press)])
                    })
                } else {
                    view
                }
            }
            m.form("phases:any? action:closure") { c, view in
                if case .function(let fn)? = c["action"] {
                    let interp = c.interp
                    AnyView(view.onKeyPress(phases: KFocusSlots.phases(c["phases"])) { press in KFocusSlots.result(interp, fn, [KFocusSlots.press(press)]) })
                } else {
                    view
                }
            }
            m.probe { _, a, interp in
                guard case .function(let fn)? = a["action"] else { return [] }
                let wants = KRenderer(interp: interp).closureParamCount(.function(fn)) > 0
                let press = KV.tuple([.string("a"), .string("a"), .array([]), .native(.implicit("down", []))], ["key", "characters", "modifiers", "phase"])
                return [KProbeCall(fn: fn, args: wants ? [press] : [], use: .action)]
            }
        }
        r.modifier("typeSelectEquivalent", .focus) { m in
            m.form("_:any") { c, view in
                if let s = c.string(0) { AnyView(view.typeSelectEquivalent(Text(s))) } else { AnyView(view.typeSelectEquivalent(nil as Text?)) }
            }
        }
        r.type("KeyPress.Result", .focus) { t in
            t.internal()
            t.anyStatic { _, name in .native(.implicit(name, [])) }
        }
    }
}

/// Focused values as a few real `FocusedValues` keys, given out by name.
@MainActor
enum KFocusSlots {
    static let count = 8
    private static var slots: [String: Int] = [:]

    static func slot(_ name: String) -> Int {
        if let s = slots[name] { return s }
        let s = slots.count % count
        slots[name] = s
        return s
    }

    static func keyPath(_ slot: Int) -> WritableKeyPath<FocusedValues, KV?> {
        [\FocusedValues.kiln0, \.kiln1, \.kiln2, \.kiln3, \.kiln4, \.kiln5, \.kiln6, \.kiln7][slot]
    }

    static let contentTypes: [String: String] = [
        "emailAddress": "email", "username": "username", "password": "password", "newPassword": "new-password",
        "oneTimeCode": "one-time-code", "name": "name", "givenName": "given-name", "familyName": "family-name",
        "telephoneNumber": "tel", "URL": "url", "fullStreetAddress": "street-address", "postalCode": "postal-code",
        "addressCity": "address-level2", "countryName": "country-name", "organizationName": "organization",
        "creditCardNumber": "cc-number", "nickname": "nickname", "jobTitle": "job-title", "location": "location",
    ]

    static func key(_ v: KV?) -> KeyEquivalent? {
        switch v {
        case .string(let s)?: return s.first.map { KeyEquivalent($0) }
        case .native(.implicit(let n, _))?:
            let named: [String: KeyEquivalent] = ["return": .return, "escape": .escape, "space": .space, "tab": .tab, "delete": .delete,
                                                 "deleteForward": .deleteForward, "upArrow": .upArrow, "downArrow": .downArrow, "leftArrow": .leftArrow,
                                                 "rightArrow": .rightArrow, "home": .home, "end": .end, "pageUp": .pageUp, "pageDown": .pageDown,
                                                 "clear": .clear]
            return named[n]
        default: return nil
        }
    }

    static func modifiers(_ v: KV?) -> EventModifiers {
        var out: EventModifiers = []
        let names: [String] = {
            switch v {
            case .native(.implicit(let n, _))?: return [n]
            case .array(let a)?: return a.compactMap { if case .native(.implicit(let n, _)) = $0 { return n }; return nil }
            default: return ["command"]
            }
        }()
        for n in names {
            switch n {
            case "command": out.insert(.command)
            case "shift": out.insert(.shift)
            case "option": out.insert(.option)
            case "control": out.insert(.control)
            default: break
            }
        }
        return out
    }

    static func phases(_ v: KV?) -> KeyPress.Phases {
        switch v {
        case .native(.implicit("down", _))?: return .down
        case .native(.implicit("up", _))?: return .up
        case .native(.implicit("repeat", _))?: return .repeat
        case .native(.implicit("all", _))?: return .all
        default: return [.down, .repeat]
        }
    }

    static func press(_ p: KeyPress) -> KV {
        let phase = p.phase == .up ? "up" : (p.phase == .repeat ? "repeat" : "down")
        return .tuple([.string(String(p.key.character)), .string(p.characters), .array([]), .native(.implicit(phase, []))],
                      ["key", "characters", "modifiers", "phase"])
    }

    static func result(_ interp: KInterpreter, _ fn: KFunction, _ args: [KV]) -> KeyPress.Result {
        let v = (try? interp.entry { try interp.call(fn, args, args.map { _ in nil }) }) ?? .nilValue
        if case .native(.implicit("ignored", _)) = v { return .ignored }
        return .handled
    }
}

struct KFocusSlot0: FocusedValueKey { typealias Value = KV }
struct KFocusSlot1: FocusedValueKey { typealias Value = KV }
struct KFocusSlot2: FocusedValueKey { typealias Value = KV }
struct KFocusSlot3: FocusedValueKey { typealias Value = KV }
struct KFocusSlot4: FocusedValueKey { typealias Value = KV }
struct KFocusSlot5: FocusedValueKey { typealias Value = KV }
struct KFocusSlot6: FocusedValueKey { typealias Value = KV }
struct KFocusSlot7: FocusedValueKey { typealias Value = KV }

extension FocusedValues {
    var kiln0: KV? { get { self[KFocusSlot0.self] } set { self[KFocusSlot0.self] = newValue } }
    var kiln1: KV? { get { self[KFocusSlot1.self] } set { self[KFocusSlot1.self] = newValue } }
    var kiln2: KV? { get { self[KFocusSlot2.self] } set { self[KFocusSlot2.self] = newValue } }
    var kiln3: KV? { get { self[KFocusSlot3.self] } set { self[KFocusSlot3.self] = newValue } }
    var kiln4: KV? { get { self[KFocusSlot4.self] } set { self[KFocusSlot4.self] = newValue } }
    var kiln5: KV? { get { self[KFocusSlot5.self] } set { self[KFocusSlot5.self] = newValue } }
    var kiln6: KV? { get { self[KFocusSlot6.self] } set { self[KFocusSlot6.self] = newValue } }
    var kiln7: KV? { get { self[KFocusSlot7.self] } set { self[KFocusSlot7.self] = newValue } }
}

/// Reads the focused-value slots for a host whose view has `@FocusedValue`.
struct KFocusedReader<Content: View>: View {
    @FocusedValue(\.kiln0) private var v0
    @FocusedValue(\.kiln1) private var v1
    @FocusedValue(\.kiln2) private var v2
    @FocusedValue(\.kiln3) private var v3
    @FocusedValue(\.kiln4) private var v4
    @FocusedValue(\.kiln5) private var v5
    @FocusedValue(\.kiln6) private var v6
    @FocusedValue(\.kiln7) private var v7
    let content: ([KV?]) -> Content

    var body: some View { content([v0, v1, v2, v3, v4, v5, v6, v7]) }
}
