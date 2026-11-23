//
//  Accessibility.swift
//  Bridges: accessibility labels, traits, actions, rotors and speech
//
//  Each is SwiftUI's own, so VoiceOver reads a Kiln app as it would the same
//  app compiled. `@AccessibilityFocusState` is the host's real one
//  (KEHostInputs), and rotor entries and linked groups use the host's real
//  namespace.
//

import SwiftUI

@objc(KilnBridges_Accessibility)
final class AccessibilityBridges: KBridgeFamily {
    override class func register(into r: KRegistry) {
        descriptions(r)
        structure(r)
        actions(r)
        focusAndRotors(r)
        speech(r)
        r.wrapper("AccessibilityFocusState", .accessibility, notes: "A `Bool` or an optional `Hashable`, as `@FocusState`, for VoiceOver's focus.")
        r.modifier("help", .accessibility, support: .stub) { m in m.stub(["_:title"]) }
    }

    @MainActor static func text(_ c: KCall, _ ref: KArgRef) -> Text {
        if case .view(let v)? = c[ref], let t = c.r.text(v) { return t }
        return Text(c.string(ref) ?? "")
    }

    @MainActor static func traits(_ v: KV?) -> AccessibilityTraits {
        let all: [String: AccessibilityTraits] = [
            "isButton": .isButton, "isHeader": .isHeader, "isSelected": .isSelected, "isLink": .isLink, "isSearchField": .isSearchField,
            "isImage": .isImage, "playsSound": .playsSound, "isKeyboardKey": .isKeyboardKey, "isStaticText": .isStaticText,
            "isSummaryElement": .isSummaryElement, "updatesFrequently": .updatesFrequently, "startsMediaSession": .startsMediaSession,
            "allowsDirectInteraction": .allowsDirectInteraction, "causesPageTurn": .causesPageTurn, "isModal": .isModal, "isToggle": .isToggle,
        ]
        switch v {
        case .native(.implicit(let n, _))?: return all[n] ?? []
        case .array(let items)?: return items.reduce(into: AccessibilityTraits()) { $0.formUnion(traits($1)) }
        case .set(let items)?: return items.reduce(into: AccessibilityTraits()) { $0.formUnion(traits($1)) }
        default: return []
        }
    }

    // MARK: Descriptions

    static func descriptions(_ r: KRegistry) {
        for name in ["accessibilityLabel", "accessibilityHint", "accessibilityValue"] {
            r.modifier(name, .accessibility) { m in
                m.form("_:any") { c, view in
                    switch name {
                    case "accessibilityLabel": view.accessibilityLabel(text(c, 0))
                    case "accessibilityHint": view.accessibilityHint(text(c, 0))
                    default: view.accessibilityValue(text(c, 0))
                    }
                }
                m.form("_:any isEnabled:bool") { c, view in
                    if #available(iOS 18, macOS 15, *) {
                        let on = c.bool("isEnabled", default: true)
                        switch name {
                        case "accessibilityLabel": AnyView(view.accessibilityLabel(text(c, 0), isEnabled: on))
                        case "accessibilityHint": AnyView(view.accessibilityHint(text(c, 0), isEnabled: on))
                        default: AnyView(view.accessibilityValue(text(c, 0), isEnabled: on))
                        }
                    } else {
                        view
                    }
                }
                if name == "accessibilityLabel" {
                    m.form("content:closure") { c, view in
                        // `accessibilityLabel { label in … }` (iOS 18): the app's label view.
                        if #available(iOS 18, macOS 15, *), case .function(let fn)? = c["content"] {
                            let interp = c.interp
                            AnyView(view.accessibilityLabel { label in KRenderer(interp: interp).renderContent(.function(fn), [KNativeContent.value(AnyView(label))]) })
                        } else {
                            view
                        }
                    }
                }
            }
        }
        r.modifier("accessibilityIdentifier", .accessibility) { m in
            m.form("_:string") { c, view in view.accessibilityIdentifier(c.string(0) ?? "") }
            m.form("_:string isEnabled:bool") { c, view in
                if #available(iOS 18, macOS 15, *) { AnyView(view.accessibilityIdentifier(c.string(0) ?? "", isEnabled: c.bool("isEnabled", default: true))) } else { view }
            }
        }
        r.modifier("accessibilityAddTraits", .accessibility) { m in
            m.form("_:AccessibilityTraits") { c, view in view.accessibilityAddTraits(traits(c[0])) }
        }
        r.modifier("accessibilityRemoveTraits", .accessibility) { m in
            m.form("_:AccessibilityTraits") { c, view in view.accessibilityRemoveTraits(traits(c[0])) }
        }
        r.type("AccessibilityTraits", .accessibility) { t in
            t.internal()
            t.anyStatic { _, name in .native(.implicit(name, [])) }
        }
        r.modifier("accessibilityHeading", .accessibility) { m in
            m.form("_:any") { c, view in
                let levels: [String: AccessibilityHeadingLevel] = ["h1": .h1, "h2": .h2, "h3": .h3, "h4": .h4, "h5": .h5, "h6": .h6, "unspecified": .unspecified]
                view.accessibilityHeading(levels[c.symbol(0) ?? ""] ?? .unspecified)
            }
        }
        r.modifier("accessibilityInputLabels", .accessibility) { m in
            m.form("_:any") { c, view in
                view.accessibilityInputLabels((c[0]?.asArray ?? []).map { Text(c.r.string($0) ?? "") })
            }
        }
        r.modifier("accessibilityCustomContent", .accessibility) { m in
            m.form("_:any _:any importance:any?") { c, view in
                let key = Text(c.string(0) ?? "")
                let value = c[1].map { v -> Text in if case .view(let tv) = v, let t = c.r.text(tv) { return t }; return Text(c.r.string(v) ?? "") }
                view.accessibilityCustomContent(key, value ?? Text(""), importance: c.symbol("importance") == "high" ? .high : .default)
            }
        }
        r.modifier("accessibilityTextContentType", .accessibility) { m in
            m.form("_:any") { c, view in
                let types: [String: AccessibilityTextContentType] = ["plain": .plain, "console": .console, "fileSystem": .fileSystem, "messaging": .messaging,
                                                                     "narrative": .narrative, "sourceCode": .sourceCode, "spreadsheet": .spreadsheet,
                                                                     "wordProcessing": .wordProcessing]
                view.accessibilityTextContentType(types[c.symbol(0) ?? ""] ?? .plain)
            }
        }
        r.modifier("accessibilityScrollStatus", .accessibility, introduced: "26.0") { m in
            m.form("_:any isEnabled:bool?") { c, view in
                if #available(iOS 26, macOS 26, *) {
                    AnyView(view.accessibilityScrollStatus(LocalizedStringResource(stringLiteral: c.string(0) ?? ""), isEnabled: c.bool("isEnabled", default: true)))
                } else {
                    view
                }
            }
        }
        r.modifier("assistiveAccessNavigationIcon", .accessibility, introduced: "26.0") { m in
            m.form("_:any") { c, view in
                #if os(iOS)
                if #available(iOS 26, *), case .view(let v)? = c[0], let image = KCanvas.image(v, c.r) { AnyView(view.assistiveAccessNavigationIcon(image)) } else { view }
                #else
                view
                #endif
            }
            m.form("systemImage:string") { c, view in
                #if os(iOS)
                if #available(iOS 26, *) { AnyView(view.assistiveAccessNavigationIcon(systemImage: c.string("systemImage") ?? "")) } else { view }
                #else
                view
                #endif
            }
        }
        // `.accessibility(label:)` and its kin, deprecated but still written.
        r.modifier("accessibility", .accessibility, notes: "Deprecated: prefer `accessibilityLabel` and the rest.") { m in
            for label in ["label", "hint", "value", "hidden", "identifier", "addTraits", "removeTraits", "sortPriority", "activationPoint", "inputLabels",
                          "selectionIdentifier"] {
                m.form("\(label):any") { c, view in
                    let v = c[.label(label)]
                    switch label {
                    case "label": AnyView(view.accessibilityLabel(text(c, .label(label))))
                    case "hint": AnyView(view.accessibilityHint(text(c, .label(label))))
                    case "value": AnyView(view.accessibilityValue(text(c, .label(label))))
                    case "hidden": AnyView(view.accessibilityHidden(v.map { c.interp.truthy($0) } ?? true))
                    case "identifier": AnyView(view.accessibilityIdentifier(c.string(.label(label)) ?? ""))
                    case "addTraits": AnyView(view.accessibilityAddTraits(traits(v)))
                    case "removeTraits": AnyView(view.accessibilityRemoveTraits(traits(v)))
                    case "sortPriority": AnyView(view.accessibilitySortPriority(v?.asDouble ?? 0))
                    case "activationPoint": AnyView(view.accessibilityActivationPoint(c.r.unitPoint(v) ?? .center))
                    case "inputLabels": AnyView(view.accessibilityInputLabels((v?.asArray ?? []).map { Text(c.r.string($0) ?? "") }))
                    default: view
                    }
                }
            }
        }
    }

    // MARK: Structure

    static func structure(_ r: KRegistry) {
        r.modifier("accessibilityElement", .accessibility) { m in
            m.form("children:any?") { c, view in
                switch c.symbol("children") {
                case "combine": view.accessibilityElement(children: .combine)
                case "contain": view.accessibilityElement(children: .contain)
                default: view.accessibilityElement(children: .ignore)
                }
            }
        }
        r.modifier("accessibilityHidden", .accessibility) { m in
            m.form("_:bool") { c, view in view.accessibilityHidden(c.bool(0, default: true)) }
            m.form("_:bool isEnabled:bool") { c, view in
                if #available(iOS 18, macOS 15, *) { AnyView(view.accessibilityHidden(c.bool(0, default: true), isEnabled: c.bool("isEnabled", default: true))) } else { view }
            }
        }
        r.modifier("accessibilitySortPriority", .accessibility) { m in
            m.form("_:number") { c, view in view.accessibilitySortPriority(c.double(0) ?? 0) }
        }
        r.modifier("accessibilityChildren", .accessibility) { m in
            m.form("children:content") { c, view in
                let children = c.content("children")
                view.accessibilityChildren { children }
            }
        }
        r.modifier("accessibilityRepresentation", .accessibility) { m in
            m.form("representation:content") { c, view in
                let rep = c.content("representation")
                view.accessibilityRepresentation { rep }
            }
        }
        r.modifier("accessibilityIgnoresInvertColors", .accessibility) { m in
            m.form("_:bool?") { c, view in view.accessibilityIgnoresInvertColors(c.bool(0, default: true)) }
        }
        r.modifier("accessibilityRespondsToUserInteraction", .accessibility) { m in
            m.form("_:bool?") { c, view in view.accessibilityRespondsToUserInteraction(c.bool(0, default: true)) }
        }
        r.modifier("accessibilityShowsLargeContentViewer", .accessibility) { m in
            m.form("") { _, view in view.accessibilityShowsLargeContentViewer() }
            m.form("_:content") { c, view in
                let content = c.content(0)
                view.accessibilityShowsLargeContentViewer { content }
            }
        }
        r.modifier("accessibilityActivationPoint", .accessibility) { m in
            m.form("_:any") { c, view in
                if case .native(.point(let x, let y))? = c[0] { AnyView(view.accessibilityActivationPoint(CGPoint(x: x, y: y))) }
                else { AnyView(view.accessibilityActivationPoint(c.r.unitPoint(c[0]) ?? .center)) }
            }
        }
        for name in ["accessibilityDragPoint", "accessibilityDropPoint"] {
            r.modifier(name, .accessibility) { m in
                m.form("_:any description:any") { c, view in
                    let point = c.r.unitPoint(c[0]) ?? .center
                    let text = Text(c.string("description") ?? "")
                    if name == "accessibilityDragPoint" { AnyView(view.accessibilityDragPoint(point, description: text)) }
                    else { AnyView(view.accessibilityDropPoint(point, description: text)) }
                }
            }
        }
        r.modifier("accessibilityDirectTouch", .accessibility) { m in
            m.form("_:bool? options:any?") { c, view in
                view.accessibilityDirectTouch(c.bool(0, default: true),
                                              options: c.symbol("options") == "silentOnTouch" ? .silentOnTouch : (c.symbol("options") == "requiresActivation" ? .requiresActivation : []))
            }
        }
        r.modifier("accessibilityLinkedGroup", .accessibility) { m in
            m.form("id:any in:any") { c, view in
                if let ns = c.interp.namespace(c["in"]) {
                    AnyView(view.accessibilityLinkedGroup(id: KNamespacedID(slot: ns.slot, id: c["id"] ?? .nilValue), in: ns.id))
                } else {
                    view
                }
            }
        }
        r.modifier("accessibilityLabeledPair", .accessibility) { m in
            m.form("role:any id:any in:any") { c, view in
                if let ns = c.interp.namespace(c["in"]) {
                    AnyView(view.accessibilityLabeledPair(role: c.symbol("role") == "content" ? .content : .label,
                                                          id: KNamespacedID(slot: ns.slot, id: c["id"] ?? .nilValue), in: ns.id))
                } else {
                    view
                }
            }
        }
    }

    // MARK: Actions

    static func actions(_ r: KRegistry) {
        r.modifier("accessibilityAction", .accessibility) { m in
            m.form("_:any? _:action") { c, view in
                #if os(iOS)
                let kind: AccessibilityActionKind = c.symbol(0) == "escape" ? .escape : (c.symbol(0) == "magicTap" ? .magicTap : .default)
                #else
                let kind: AccessibilityActionKind = c.symbol(0) == "escape" ? .escape : .default
                #endif
                view.accessibilityAction(kind, c.action(c.has(1) ? 1 : 0))
            }
            m.form("named:any _:action") { c, view in view.accessibilityAction(named: Text(c.string("named") ?? ""), c.action(0)) }
            m.form("action:action label:content") { c, view in
                let label = c.content("label")
                view.accessibilityAction(action: c.action("action")) { label }
            }
        }
        r.modifier("accessibilityActions", .accessibility) { m in
            m.form("_:content") { c, view in
                let content = c.content(0)
                view.accessibilityActions { content }
            }
            m.form("category:any _:content") { c, view in
                let content = c.content(0)
                view.accessibilityActions { content }
            }
        }
        r.modifier("accessibilityAdjustableAction", .accessibility) { m in
            m.form("_:closure") { c, view in
                if case .function(let fn)? = c[0] {
                    let interp = c.interp
                    AnyView(view.accessibilityAdjustableAction { direction in
                        interp.perform(fn, [.native(.implicit(direction == .increment ? "increment" : "decrement", []))])
                    })
                } else {
                    view
                }
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a.first else { return [] }
                return [KProbeCall(fn: fn, args: [.native(.implicit("increment", []))], use: .action)]
            }
        }
        r.modifier("accessibilityScrollAction", .accessibility) { m in
            m.form("_:closure") { c, view in
                if case .function(let fn)? = c[0] {
                    let interp = c.interp
                    AnyView(view.accessibilityScrollAction { edge in
                        let n = edge == .top ? "top" : (edge == .bottom ? "bottom" : (edge == .leading ? "leading" : "trailing"))
                        interp.perform(fn, [.native(.implicit(n, []))])
                    })
                } else {
                    view
                }
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a.first else { return [] }
                return [KProbeCall(fn: fn, args: [.native(.implicit("bottom", []))], use: .action)]
            }
        }
        r.modifier("accessibilityZoomAction", .accessibility) { m in
            m.form("_:closure") { c, view in
                if case .function(let fn)? = c[0] {
                    let interp = c.interp
                    AnyView(view.accessibilityZoomAction { action in
                        let direction = KV.native(.implicit(action.direction == .zoomIn ? "zoomIn" : "zoomOut", []))
                        interp.perform(fn, [.tuple([direction, .native(.point(action.location.x, action.location.y))], ["direction", "location"])])
                    })
                } else {
                    view
                }
            }
            m.probe { _, a, _ in
                guard case .function(let fn)? = a.first else { return [] }
                return [KProbeCall(fn: fn, args: [.tuple([.native(.implicit("zoomIn", [])), .native(.point(0, 0))], ["direction", "location"])], use: .action)]
            }
        }
    }

    // MARK: Focus and rotors

    static func focusAndRotors(_ r: KRegistry) {
        r.modifier("accessibilityFocused", .accessibility) { m in
            m.form("_:binding") { c, view in
                if let p = c.kbinding(0)?.native as? KAccessibilityFocusProjection { view.accessibilityFocused(p.binding, equals: p.token(.bool(true))) } else { view }
            }
            m.form("_:binding equals:any") { c, view in
                if let p = c.kbinding(0)?.native as? KAccessibilityFocusProjection { view.accessibilityFocused(p.binding, equals: p.token(c["equals"] ?? .nilValue)) } else { view }
            }
        }
        r.modifier("accessibilityDefaultFocus", .accessibility, introduced: "26.0") { m in
            m.form("_:binding _:any") { c, view in
                if #available(iOS 26, macOS 26, *), let p = c.kbinding(0)?.native as? KAccessibilityFocusProjection {
                    AnyView(view.accessibilityDefaultFocus(p.binding, p.isBool ? p.token(.bool(true)) : p.token(c[1] ?? .nilValue)))
                } else {
                    view
                }
            }
        }
        r.view("AccessibilityRotorEntry", .accessibility) { v in
            v.manifestKind = "content"
            v.forms(["_:any id:any in:any? textRange:any? prepare:closure?", "_:any id:any in:any? prepare:closure?",
                     "_:any textRange:any prepare:closure?"]) { _ in EmptyView() }
        }
        r.modifier("accessibilityRotor", .accessibility, notes: "Entries with `id:` find views with the same `.id`, or `.accessibilityRotorEntry(id:in:)`.") { m in
            m.form("_:any entries:content") { c, view in rotor(c, view) }
        }
        r.modifier("accessibilityRotorEntry", .accessibility) { m in
            m.form("id:any in:any") { c, view in
                if let ns = c.interp.namespace(c["in"]) {
                    AnyView(view.accessibilityRotorEntry(id: KNamespacedID(slot: ns.slot, id: c["id"] ?? .nilValue), in: ns.id))
                } else {
                    view
                }
            }
        }
    }

    struct RotorEntry: Identifiable {
        let id: Int
        let label: Text
        let target: KV
        let namespace: KNamespaceID?
    }

    @MainActor static func rotor(_ c: KCall, _ view: AnyView) -> AnyView {
        var entries: [RotorEntry] = []
        for v in c.views("entries").flatMap(\.flattened) {
            let rows: [KView]
            if v.primitiveName == "ForEach", case .primitive(_, let args, let labels, _) = v.kind {
                rows = c.r.forEachRows(KArgs(args: args, labels: labels)).flatMap { $0.views.flatMap(\.flattened) }
            } else {
                rows = [v]
            }
            for row in rows {
                guard case .primitive("AccessibilityRotorEntry", let args, let labels, _) = row.kind else { continue }
                let a = KArgs(args: args, labels: labels)
                let label: Text = { if case .view(let tv)? = a.first, let t = c.r.text(tv) { return t }; return Text(c.r.string(a.first) ?? "") }()
                entries.append(RotorEntry(id: entries.count, label: label, target: a["id"] ?? .nilValue, namespace: c.interp.namespace(a["in"])))
            }
        }
        let system: [String: AccessibilitySystemRotor] = ["headings": .headings, "links": .links, "boldText": .boldText, "italicText": .italicText,
                                                          "underlineText": .underlineText, "misspelledWords": .misspelledWords, "landmarks": .landmarks,
                                                          "images": .images, "textFields": .textFields, "tables": .tables, "lists": .lists]
        let label = Text(c.string(0) ?? "")
        let sys = c.symbol(0).flatMap { system[$0] }
        if let ns = entries.compactMap(\.namespace).first {
            let content = ForEach(entries) { e in AccessibilityRotorEntry(e.label, id: KNamespacedID(slot: ns.slot, id: e.target), in: ns.id) }
            if let sys { return AnyView(view.accessibilityRotor(sys) { content }) }
            return AnyView(view.accessibilityRotor(label) { content })
        }
        let content = ForEach(entries) { e in AccessibilityRotorEntry(e.label, id: e.target) }
        if let sys { return AnyView(view.accessibilityRotor(sys) { content }) }
        return AnyView(view.accessibilityRotor(label) { content })
    }

    // MARK: Speech

    static func speech(_ r: KRegistry) {
        r.modifier("speechAdjustedPitch", .accessibility) { m in
            m.form("_:number") { c, view in view.speechAdjustedPitch(c.double(0) ?? 0) }
            m.text { c, t in t.speechAdjustedPitch(c.double(0) ?? 0) }
        }
        for name in ["speechAlwaysIncludesPunctuation", "speechAnnouncementsQueued", "speechSpellsOutCharacters"] {
            r.modifier(name, .accessibility) { m in
                m.form("_:bool?") { c, view in
                    let on = c.bool(0, default: true)
                    switch name {
                    case "speechAlwaysIncludesPunctuation": AnyView(view.speechAlwaysIncludesPunctuation(on))
                    case "speechAnnouncementsQueued": AnyView(view.speechAnnouncementsQueued(on))
                    default: AnyView(view.speechSpellsOutCharacters(on))
                    }
                }
                m.text { c, t in
                    let on = c.bool(0, default: true)
                    switch name {
                    case "speechAlwaysIncludesPunctuation": return t.speechAlwaysIncludesPunctuation(on)
                    case "speechAnnouncementsQueued": return t.speechAnnouncementsQueued(on)
                    default: return t.speechSpellsOutCharacters(on)
                    }
                }
            }
        }
    }
}
