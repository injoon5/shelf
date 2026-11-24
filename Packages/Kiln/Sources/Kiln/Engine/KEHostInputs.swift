//
//  KEHostInputs.swift
//  Kiln's engine
//
//  What a hosted view reads from SwiftUI itself, for the app's own view
//  struct: environment values (`@Environment(\.dynamicTypeSize)`), a
//  `@Namespace`, and a `@FocusState` that really moves the keyboard focus.
//  Property wrappers are static in Swift, so each host has one of each, and
//  the app's properties map onto them:
//
//  - **Environment.** `KHostInputs` reads `EnvironmentValues` as a whole, and
//    each bridged key's `read` takes its value from there.
//  - **Namespaces.** One real `Namespace.ID` per host; each of the app's
//    `@Namespace` properties is that ID with the property's name, so two
//    namespaces in one view stay apart (`KNamespaceID`).
//  - **Focus.** One real `FocusState<KV?>` per host. Its value names the app's
//    property and the value it's focused on: `("isEditing", true)` for a
//    `Bool`, `("field", .email)` for an optional. Only one field has focus at
//    a time, so the properties of one view can share it.
//
//  Only types that need one of these get the extra view (`needsHostInputs`),
//  so a view that reads none of them is hosted as before.
//

import SwiftUI

/// The values a host passes its app view.
@MainActor
struct KHostInputValues {
    let environment: EnvironmentValues
    let namespace: Namespace.ID
    let focus: FocusState<KV?>.Binding
    let accessibilityFocus: AccessibilityFocusState<KV?>.Binding
    /// The focused-value slots (Focus.swift's `KFocusSlots`), when the view reads one.
    var focused: [KV?] = []
}

/// Reads SwiftUI's environment, a namespace and a focus state for the
/// app's view inside it.
struct KHostInputs<Content: View>: View {
    @SwiftUI.Environment(\.self) private var environment
    @Namespace private var namespace
    @FocusState private var focus: KV?
    @AccessibilityFocusState private var accessibilityFocus: KV?
    /// The view's own storage: its `@State` changing redraws this view, which
    /// runs the app's body (the closure alone wouldn't tell SwiftUI it changed).
    @ObservedObject var storage: KViewStorage
    var readsFocusedValues = false
    let content: @MainActor (KHostInputValues) -> Content

    var body: some View {
        let inputs = KHostInputValues(environment: environment, namespace: namespace, focus: $focus, accessibilityFocus: $accessibilityFocus)
        if readsFocusedValues {
            KFocusedReader { values in
                var withValues = inputs
                withValues.focused = values
                return content(withValues)
            }
        } else {
            content(inputs)
        }
    }
}

/// An app's `@Namespace` value: the host's real namespace, and the property.
struct KNamespaceID: Hashable {
    let id: Namespace.ID
    let slot: String
}

/// An id inside one of the app's namespaces (`matchedGeometryEffect(id:in:)`).
struct KNamespacedID: Hashable, @unchecked Sendable {
    let slot: String
    let id: KV
}

/// What `$field` carries for `.accessibilityFocused` when it's an `@AccessibilityFocusState`.
struct KAccessibilityFocusProjection {
    let name: String
    let isBool: Bool
    let binding: AccessibilityFocusState<KV?>.Binding
    func token(_ value: KV) -> KV { .tuple([.string(name), value], [nil, nil]) }
}

/// What `$field` carries for `.focused`: the host's focus state, and the property.
struct KFocusProjection {
    let name: String
    let isBool: Bool
    let binding: FocusState<KV?>.Binding

    func token(_ value: KV) -> KV { .tuple([.string(name), value], [nil, nil]) }
}

extension KInterpreter {
    /// Wrappers whose value comes from the host's inputs.
    static let hostInputWrappers: Set<String> = ["FocusState", "Namespace", "AccessibilityFocusState", "FocusedValue", "FocusedBinding",
                                                 "FocusedObject"]

    /// Whether a type's host needs `KHostInputs`: it has a `@FocusState`, a
    /// `@Namespace`, or an `@Environment` value SwiftUI provides.
    func needsHostInputs(_ t: KType) -> Bool {
        if let known = t.hostInputs { return known }
        var needs = false
        for p in t.stored {
            guard let w = p.wrapper else { continue }
            if Self.hostInputWrappers.contains(w) { needs = true; break }
            if w == "Environment", case .keyPath(_, let comps)? = p.wrapperAttribute?.args.first?.value,
               let key = comps.last, registry.environment[key]?.live != nil {
                needs = true
                break
            }
        }
        t.hostInputs = needs
        return needs
    }

    /// Whether a type has `@FocusedValue`, `@FocusedBinding` or `@FocusedObject`.
    func readsFocusedValues(_ t: KType) -> Bool {
        t.stored.contains { ["FocusedValue", "FocusedBinding", "FocusedObject"].contains($0.wrapper ?? "") }
    }

    /// The namespace value of an app's `@Namespace` property, or of a
    /// `Namespace.ID` passed down to another view.
    func namespace(_ v: KV?) -> KNamespaceID? {
        if case .native(.boxed(let b))? = v { return b.get(KNamespaceID.self) }
        return nil
    }
}

extension KViewStorage {
    /// Installs this render's inputs into the app's `@FocusState` and
    /// `@Namespace` properties.
    func connect(_ value: KStructValue, _ inputs: KHostInputValues, _ interp: KInterpreter) {
        for p in value.type.stored {
            guard let w = p.wrapper, let box = box(p.name) else { continue }
            switch w {
            case "Namespace":
                box.seed(.native(.boxed(KBoxed("Namespace.ID", KNamespaceID(id: inputs.namespace, slot: p.name)))))
            case "AccessibilityFocusState":
                let isBool = p.type?.name == "Bool" || {
                    if case .bool = value.fields[p.name] ?? .void { return true }
                    return false
                }()
                let binding = inputs.accessibilityFocus, name = p.name
                setNative(p.name, KAccessibilityFocusProjection(name: name, isBool: isBool, binding: binding))
                box.getter = {
                    guard case .tuple(let parts, _)? = binding.wrappedValue, parts.count == 2, parts[0] == .string(name) else { return isBool ? .bool(false) : .nilValue }
                    return isBool ? .bool(true) : parts[1]
                }
                box.setter = { v in
                    let token = KV.tuple([.string(name), isBool ? .bool(true) : v], [nil, nil])
                    if isBool ? interp.truthy(v) : !v.isNil { binding.wrappedValue = token } else { binding.wrappedValue = nil }
                }
            case "FocusState":
                let isBool = p.type?.name == "Bool" || {
                    if case .bool = value.fields[p.name] ?? .void { return true }
                    return false
                }()
                let projection = KFocusProjection(name: p.name, isBool: isBool, binding: inputs.focus)
                setNative(p.name, projection)
                box.getter = {
                    guard case .tuple(let parts, _)? = projection.binding.wrappedValue, parts.count == 2,
                          parts[0] == .string(projection.name) else { return isBool ? .bool(false) : .nilValue }
                    return isBool ? .bool(true) : parts[1]
                }
                box.setter = { v in
                    let mine: Bool = {
                        if case .tuple(let parts, _)? = projection.binding.wrappedValue { return parts.first == .string(projection.name) }
                        return false
                    }()
                    if isBool {
                        if interp.truthy(v) { projection.binding.wrappedValue = projection.token(.bool(true)) }
                        else if mine { projection.binding.wrappedValue = nil }
                    } else if v.isNil {
                        if mine { projection.binding.wrappedValue = nil }
                    } else {
                        projection.binding.wrappedValue = projection.token(v)
                    }
                }
            default:
                break
            }
        }
        // Focused values: the slot of the key or type each one names.
        for p in value.type.stored {
            guard let w = p.wrapper, ["FocusedValue", "FocusedBinding", "FocusedObject"].contains(w) else { continue }
            var name: String?
            switch p.wrapperAttribute?.args.first?.value {
            case .keyPath(_, let comps)?: name = comps.last
            case .member(.ident(let typeName, _), "self", _)?: name = typeName
            default: name = p.type?.name
            }
            let found: KV? = name.flatMap { n in
                let slot = KFocusSlots.slot(n)
                return slot < inputs.focused.count ? inputs.focused[slot] : nil
            } ?? nil
            if w == "FocusedBinding", case .binding(let b)? = found {
                setBox(p.name, KBox(get: { b.get() }, set: { b.set($0) }))
            } else if let found {
                setBox(p.name, KBox(found))
            } else {
                setBox(p.name, KBox(w == "FocusedValue" ? interp.environmentDefault(p) : .nilValue))
            }
        }
    }
}
