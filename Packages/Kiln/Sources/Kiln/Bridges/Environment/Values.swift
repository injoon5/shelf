//
//  Values.swift
//  Bridges: SwiftUI's environment values
//
//  Each is read from SwiftUI where the view is shown (KEHostInputs), so
//  `@Environment(\.dynamicTypeSize)` is the real one, and the ones SwiftUI
//  lets a view set have a `write` for `.environment(\.key, value)`.
//  Enum-like values are symbols (`.compact`, `.dark`), as the app writes them.
//
//  `\.scenePhase` is the lower of the system's phase and the run's own
//  (`KilnContext.scenePhase`, which the host sets: `.active` while the app's
//  card is open). `\.openURL` is SwiftUI's action, which the run's root
//  routes through the host (`KilnContext.openURL`).
//

import SwiftUI

extension EnvironmentBridges {
    static func environmentValues(_ r: KRegistry) {
        appearance(r)
        text(r)
        drawing(r)
        accessibility(r)
        other(r)
        actions(r)
    }

    /// `.large`, `.compact`: an enum-like value as the symbol the app compares with.
    @MainActor static func symbol(_ v: Any) -> KV {
        var text = String(describing: v)
        if text.hasPrefix("Optional(") { text = String(text.dropFirst(9).dropLast()) }
        if text == "nil" { return .nilValue }
        if let dot = text.lastIndex(of: "."), !text.contains("(") { text = String(text[text.index(after: dot)...]) }
        return .native(.implicit(text, []))
    }

    @MainActor static func name(_ v: KV) -> String? {
        if case .native(.implicit(let n, _)) = v { return n }
        if case .enumV(let e) = v { return e.caseName }
        return nil
    }

    // MARK: Appearance

    static func appearance(_ r: KRegistry) {
        r.environmentValue("colorScheme", .environment, value: { _ in .native(.implicit("light", [])) },
                           read: { env, _ in .native(.implicit(env.colorScheme == .dark ? "dark" : "light", [])) },
                           write: { env, v, _ in env.colorScheme = name(v) == "dark" ? .dark : .light })
        r.environmentValue("colorSchemeContrast", .drawing, value: { _ in .native(.implicit("standard", [])) },
                           read: { env, _ in .native(.implicit(env.colorSchemeContrast == .increased ? "increased" : "standard", [])) })
        let sizes: [(String, UserInterfaceSizeClass)] = [("compact", .compact), ("regular", .regular)]
        for key in ["horizontalSizeClass", "verticalSizeClass"] {
            let path: WritableKeyPath<EnvironmentValues, UserInterfaceSizeClass?> = key == "horizontalSizeClass" ? \.horizontalSizeClass : \.verticalSizeClass
            r.environmentValue(key, .environment, value: { _ in .native(.implicit(key == "horizontalSizeClass" ? "compact" : "regular", [])) },
                               read: { env, _ in env[keyPath: path].map { $0 == .regular ? .native(.implicit("regular", [])) : .native(.implicit("compact", [])) } ?? .nilValue },
                               write: { env, v, _ in env[keyPath: path] = sizes.first { $0.0 == name(v) }?.1 })
        }
        for key in ["realHorizontalSizeClass", "realVerticalSizeClass"] {
            r.environmentValue(key, .environment, value: { _ in .nilValue }, read: { env, _ in
                (key == "realHorizontalSizeClass" ? env.horizontalSizeClass : env.verticalSizeClass).map { symbol($0) } ?? .nilValue
            })
        }
        let typeSizes: [(String, DynamicTypeSize)] = [("xSmall", .xSmall), ("small", .small), ("medium", .medium), ("large", .large), ("xLarge", .xLarge),
            ("xxLarge", .xxLarge), ("xxxLarge", .xxxLarge), ("accessibility1", .accessibility1), ("accessibility2", .accessibility2),
            ("accessibility3", .accessibility3), ("accessibility4", .accessibility4), ("accessibility5", .accessibility5)]
        r.environmentValue("dynamicTypeSize", .text, notes: "Compare with `<`, or read `isAccessibilitySize`.",
                           value: { _ in KDynamicType.wrap(.large) }, read: { env, _ in KDynamicType.wrap(env.dynamicTypeSize) },
                           write: { env, v, _ in if let s = KDynamicType.size(v) { env.dynamicTypeSize = s } })
        r.type("DynamicTypeSize", .text, support: .full) { t in
            for (n, s) in typeSizes { t.staticProperty(n) { _ in KDynamicType.wrap(s) } }
            t.implicit { n, _, _ in typeSizes.first { $0.0 == n }.map { KDynamicType.wrap($0.1) } }
            t.property("isAccessibilitySize") { c in .bool(KDynamicType.size(c.receiver)?.isAccessibilitySize ?? false) }
            t.staticProperty("allCases") { _ in .array(typeSizes.map { KDynamicType.wrap($0.1) }) }
        }
        r.environmentValue("sizeCategory", .text, value: { _ in .native(.implicit("large", [])) }, read: { env, _ in symbol(env.sizeCategory) })
        r.environmentValue("layoutDirection", .text, value: { _ in .native(.implicit("leftToRight", [])) },
                           read: { env, _ in .native(.implicit(env.layoutDirection == .rightToLeft ? "rightToLeft" : "leftToRight", [])) },
                           write: { env, v, _ in env.layoutDirection = name(v) == "rightToLeft" ? .rightToLeft : .leftToRight })
        r.environmentValue("displayScale", .drawing, value: { _ in .double(3) }, read: { env, _ in .double(env.displayScale) },
                           write: { env, v, _ in env.displayScale = v.cg ?? env.displayScale })
        r.environmentValue("pixelLength", .drawing, value: { _ in .double(1.0 / 3) }, read: { env, _ in .double(env.pixelLength) })
        r.environmentValue("isLuminanceReduced", .drawing, value: { _ in .bool(false) }, read: { env, _ in .bool(env.isLuminanceReduced) })
        r.environmentValue("appearsActive", .drawing, value: { _ in .bool(true) }, read: { env, _ in
            if #available(iOS 18, macOS 15, *) { return .bool(env.appearsActive) }
            return .bool(true)
        })
        r.environmentValue("locale", .environment, value: { _ in .native(.object("Locale", KRef(Locale.current as AnyObject))) },
                           read: { env, _ in .native(.object("Locale", KRef(env.locale as AnyObject))) },
                           write: { env, v, _ in if case .native(.object(_, let ref)) = v, let l = ref.value as? Locale { env.locale = l } })
        r.environmentValue("calendar", .environment, value: { _ in .native(.object("Calendar", KRef(Calendar.current as AnyObject))) },
                           read: { env, _ in .native(.object("Calendar", KRef(env.calendar as AnyObject))) },
                           write: { env, v, _ in if case .native(.object(_, let ref)) = v, let cal = ref.value as? Calendar { env.calendar = cal } })
        r.environmentValue("timeZone", .text, value: { _ in .native(.object("TimeZone", KRef(TimeZone.current as AnyObject))) },
                           read: { env, _ in .native(.object("TimeZone", KRef(env.timeZone as AnyObject))) },
                           write: { env, v, _ in if case .native(.object(_, let ref)) = v, let tz = ref.value as? TimeZone { env.timeZone = tz } })
    }

    // MARK: Text

    static func text(_ r: KRegistry) {
        r.environmentValue("font", .text, value: { _ in .nilValue }, read: { env, _ in env.font.map { .native(.font($0)) } ?? .nilValue },
                           write: { env, v, i in env.font = KRenderer(interp: i).font(v) })
        r.environmentValue("lineLimit", .text, value: { _ in .nilValue }, read: { env, _ in env.lineLimit.map { .int($0) } ?? .nilValue },
                           write: { env, v, _ in env.lineLimit = v.asInt })
        r.environmentValue("lineSpacing", .text, value: { _ in .double(0) }, read: { env, _ in .double(env.lineSpacing) },
                           write: { env, v, _ in env.lineSpacing = v.cg ?? 0 })
        r.environmentValue("minimumScaleFactor", .text, value: { _ in .double(1) }, read: { env, _ in .double(env.minimumScaleFactor) },
                           write: { env, v, _ in env.minimumScaleFactor = v.cg ?? 1 })
        r.environmentValue("allowsTightening", .text, value: { _ in .bool(false) }, read: { env, _ in .bool(env.allowsTightening) },
                           write: { env, v, i in env.allowsTightening = i.truthy(v) })
        r.environmentValue("multilineTextAlignment", .text, value: { _ in .native(.implicit("leading", [])) },
                           read: { env, _ in symbol(env.multilineTextAlignment) },
                           write: { env, v, _ in env.multilineTextAlignment = name(v) == "center" ? .center : (name(v) == "trailing" ? .trailing : .leading) })
        r.environmentValue("truncationMode", .text, value: { _ in .native(.implicit("tail", [])) }, read: { env, _ in symbol(env.truncationMode) },
                           write: { env, v, _ in env.truncationMode = name(v) == "head" ? .head : (name(v) == "middle" ? .middle : .tail) })
        r.environmentValue("textCase", .text, value: { _ in .nilValue }, read: { env, _ in env.textCase.map { symbol($0) } ?? .nilValue },
                           write: { env, v, _ in env.textCase = name(v) == "uppercase" ? .uppercase : (name(v) == "lowercase" ? .lowercase : nil) })
        r.environmentValue("textSelectionAffinity", .text, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
            if #available(iOS 18, macOS 15, *) { return symbol(env.textSelectionAffinity) }
            return .native(.implicit("automatic", []))
        })
        r.environmentValue("lineHeight", .text, value: { _ in .nilValue }, read: { env, _ in
            if #available(iOS 26, macOS 26, *) { return env.lineHeight.map { symbol($0) } ?? .nilValue }
            return .nilValue
        })
        r.environmentValue("fontResolutionContext", .text, support: .partial, notes: "For `font.resolve(in:)`.", value: { _ in .nilValue },
                           read: { env, _ in .native(.object("Font.Context", KRef(KBoxRef(env.fontResolutionContext)))) })
    }

    // MARK: Drawing

    static func drawing(_ r: KRegistry) {
        r.environmentValue("imageScale", .drawing, value: { _ in .native(.implicit("medium", [])) }, read: { env, _ in symbol(env.imageScale) },
                           write: { env, v, _ in env.imageScale = name(v) == "large" ? .large : (name(v) == "small" ? .small : .medium) })
        r.environmentValue("symbolRenderingMode", .drawing, value: { _ in .nilValue }, read: { env, _ in
            guard let m = env.symbolRenderingMode else { return .nilValue }
            return symbol(m)
        })
        r.environmentValue("symbolVariants", .drawing, value: { _ in .native(.implicit("none", [])) }, read: { env, _ in
            for (n, v) in [("fill", SymbolVariants.fill), ("circle", .circle), ("square", .square), ("slash", .slash), ("rectangle", .rectangle)]
            where env.symbolVariants.contains(v) { return .native(.implicit(n, [])) }
            return .native(.implicit("none", []))
        })
        r.environmentValue("symbolColorRenderingMode", .drawing, value: { _ in .nilValue }, read: { env, _ in
            if #available(iOS 26, macOS 26, *) { return env.symbolColorRenderingMode.map { symbol($0) } ?? .nilValue }
            return .nilValue
        })
        r.environmentValue("symbolVariableValueMode", .drawing, value: { _ in .nilValue }, read: { env, _ in
            if #available(iOS 26, macOS 26, *) { return env.symbolVariableValueMode.map { symbol($0) } ?? .nilValue }
            return .nilValue
        })
        r.environmentValue("redactionReasons", .drawing, notes: "A set: `redactionReasons.contains(.placeholder)`.", value: { _ in .set([]) }, read: { env, _ in
            var out: Set<KV> = []
            if env.redactionReasons.contains(.placeholder) { out.insert(.native(.implicit("placeholder", []))) }
            if env.redactionReasons.contains(.privacy) { out.insert(.native(.implicit("privacy", []))) }
            if env.redactionReasons.contains(.invalidated) { out.insert(.native(.implicit("invalidated", []))) }
            return .set(out)
        })
        r.environmentValue("backgroundMaterial", .drawing, value: { _ in .nilValue }, read: { env, _ in env.backgroundMaterial.map { symbol($0) } ?? .nilValue })
        r.environmentValue("backgroundProminence", .drawing, value: { _ in .native(.implicit("standard", [])) },
                           read: { env, _ in .native(.implicit(env.backgroundProminence == .increased ? "increased" : "standard", [])) })
        r.environmentValue("backgroundStyle", .drawing, value: { _ in .nilValue }, read: { env, _ in env.backgroundStyle == nil ? .nilValue : .native(.implicit("background", [])) })
        r.environmentValue("contentTransition", .drawing, value: { _ in .native(.implicit("opacity", [])) }, read: { env, _ in
            .native(.implicit(env.contentTransition == .identity ? "identity" : (env.contentTransition == .interpolate ? "interpolate" : "opacity"), []))
        })
        r.environmentValue("contentTransitionAddsDrawingGroup", .drawing, value: { _ in .bool(false) },
                           read: { env, _ in .bool(env.contentTransitionAddsDrawingGroup) },
                           write: { env, v, i in env.contentTransitionAddsDrawingGroup = i.truthy(v) })
        r.environmentValue("materialActiveAppearance", .drawing, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
            if #available(iOS 18, macOS 15, *) { return symbol(env.materialActiveAppearance) }
            return .native(.implicit("automatic", []))
        })
        r.environmentValue("accentColor", .environment, value: { _ in .nilValue }, read: { _, _ in .native(.color(.accentColor)) })
        r.environmentValue("tint", .environment, value: { _ in .native(.color(.accentColor)) }, read: { _, _ in .native(.color(.accentColor)) })
        r.environmentValue("tintColor", .environment, value: { _ in .native(.color(.accentColor)) }, read: { _, _ in .native(.color(.accentColor)) })
        r.environmentValue("foregroundColor", .environment, value: { _ in .nilValue }, read: { _, _ in .nilValue })
        r.environmentValue("allowedDynamicRange", .environment, value: { _ in .nilValue }, read: { env, _ in env.allowedDynamicRange.map { symbol($0) } ?? .nilValue })
    }

    // MARK: Accessibility

    static func accessibility(_ r: KRegistry) {
        let flags: [(String, KeyPath<EnvironmentValues, Bool>)] = [
            ("accessibilityDifferentiateWithoutColor", \.accessibilityDifferentiateWithoutColor),
            ("accessibilityDimFlashingLights", \.accessibilityDimFlashingLights), ("accessibilityEnabled", \.accessibilityEnabled),
            ("accessibilityInvertColors", \.accessibilityInvertColors), ("accessibilityLargeContentViewerEnabled", \.accessibilityLargeContentViewerEnabled),
            ("accessibilityPlayAnimatedImages", \.accessibilityPlayAnimatedImages), ("accessibilityQuickActionsEnabled", \.accessibilityQuickActionsEnabled),
            ("accessibilityReduceMotion", \.accessibilityReduceMotion), ("accessibilityReduceTransparency", \.accessibilityReduceTransparency),
            ("accessibilityShowButtonShapes", \.accessibilityShowButtonShapes), ("accessibilitySwitchControlEnabled", \.accessibilitySwitchControlEnabled),
            ("accessibilityVoiceOverEnabled", \.accessibilityVoiceOverEnabled),
        ]
        for (key, path) in flags {
            r.environmentValue(key, .accessibility, value: { _ in .bool(false) }, read: { env, _ in .bool(env[keyPath: path]) })
        }
        r.environmentValue("accessibilityShowBorders", .accessibility, value: { _ in .bool(false) }, read: { env, _ in
            if #available(iOS 26, macOS 26, *) { return .bool(env.accessibilityShowBorders) }
            return .bool(false)
        })
        r.environmentValue("accessibilityAssistiveAccessEnabled", .accessibility, value: { _ in .bool(false) }, read: { env, _ in
            if #available(iOS 18, macOS 15, *) { return .bool(env.accessibilityAssistiveAccessEnabled) }
            return .bool(false)
        })
        r.environmentValue("accessibilityPrefersCrossFadeTransitions", .accessibility, value: { _ in .bool(false) }, read: { env, _ in
            if #available(iOS 26.4, macOS 26.4, *) { return .bool(env.accessibilityPrefersCrossFadeTransitions) }
            return .bool(false)
        })
        r.environmentValue("accessibilityReduceHighlightingEffects", .accessibility, value: { _ in .bool(false) }, read: { env, _ in
            if #available(iOS 26.4, macOS 26.4, *) { return .bool(env.accessibilityReduceHighlightingEffects) }
            return .bool(false)
        })
        r.environmentValue("legibilityWeight", .accessibility, value: { _ in .native(.implicit("regular", [])) },
                           read: { env, _ in .native(.implicit(env.legibilityWeight == .bold ? "bold" : "regular", [])) })
    }

    // MARK: Others

    static func other(_ r: KRegistry) {
        @MainActor func flag(_ key: String, _ family: KilnFamily, _ path: KeyPath<EnvironmentValues, Bool>, write: WritableKeyPath<EnvironmentValues, Bool>? = nil) {
            r.environmentValue(key, family, value: { _ in .bool(true) }, read: { env, _ in .bool(env[keyPath: path]) },
                               write: write.map { w in { env, v, i in env[keyPath: w] = i.truthy(v) } })
        }
        flag("isFocusEffectEnabled", .environment, \.isFocusEffectEnabled, write: \.isFocusEffectEnabled)
        #if os(iOS)
        flag("isHoverEffectEnabled", .environment, \.isHoverEffectEnabled, write: \.isHoverEffectEnabled)
        flag("isSceneCaptured", .environment, \.isSceneCaptured)
        #else
        r.environmentValue("isHoverEffectEnabled", .environment, value: { _ in .bool(true) }, read: { _, _ in .bool(true) })
        r.environmentValue("isSceneCaptured", .environment, value: { _ in .bool(false) }, read: { _, _ in .bool(false) })
        #endif
        r.environmentValue("scenePhase", .environment, notes: "`.active` while the app's card is open; `.inactive` while it's closing; `.background` when Shelf is.",
                           value: { _ in .native(.implicit("active", [])) }, read: { env, interp in
            .native(.implicit(min(KilnScenePhase(env.scenePhase), interp.context.scenePhase).name, []))
        }, write: { env, v, _ in
            env.scenePhase = name(v) == "background" ? .background : (name(v) == "inactive" ? .inactive : .active)
        })
        r.environmentValue("undoManager", .environment, support: .partial, notes: "`undo()`, `redo()`, `canUndo`, `canRedo` and `registerUndo(withTarget:handler:)`.",
                           value: { _ in .nilValue }, read: { env, _ in env.undoManager.map { .native(.object("UndoManager", KRef($0))) } ?? .nilValue })
        r.environmentValue("description", .environment, value: { _ in .string("EnvironmentValues") }, read: { env, _ in .string(env.description) })
        r.environmentValue("badgeProminence", .environment, value: { _ in .native(.implicit("standard", [])) }, read: { env, _ in symbol(env.badgeProminence) })
        r.environmentValue("menuOrder", .environment, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in symbol(env.menuOrder) })
        r.environmentValue("sidebarRowSize", .environment, value: { _ in .native(.implicit("medium", [])) }, read: { env, _ in symbol(env.sidebarRowSize) })
        r.environmentValue("listRowSpacing", .environment, value: { _ in .nilValue }, read: { _, _ in .nilValue })
        r.environmentValue("listSectionSpacing", .environment, value: { _ in .nilValue }, read: { _, _ in .nilValue })
        for key in ["horizontalScrollBounceBehavior", "verticalScrollBounceBehavior"] {
            r.environmentValue(key, .environment, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
                let b = String(describing: key.hasPrefix("horizontal") ? env.horizontalScrollBounceBehavior : env.verticalScrollBounceBehavior)
                return .native(.implicit(b.contains("always") ? "always" : (b.contains("basedOnSize") ? "basedOnSize" : "automatic"), []))
            })
        }
        for key in ["horizontalScrollIndicatorVisibility", "verticalScrollIndicatorVisibility"] {
            r.environmentValue(key, .environment, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
                let v = key.hasPrefix("horizontal") ? env.horizontalScrollIndicatorVisibility : env.verticalScrollIndicatorVisibility
                return .native(.implicit(v == .hidden ? "hidden" : (v == .visible ? "visible" : (v == .never ? "never" : "automatic")), []))
            })
        }
        r.environmentValue("keyboardShortcut", .environment, value: { _ in .nilValue }, read: { env, _ in env.keyboardShortcut == nil ? .nilValue : .string(String(describing: env.keyboardShortcut!)) })
        r.environmentValue("defaultAppStorageDefaults", .environment, value: { i in .native(.object("UserDefaults", KRef(i.context.defaults))) },
                           read: { _, i in .native(.object("UserDefaults", KRef(i.context.defaults))) })
        r.environmentValue("preferredPencilDoubleTapAction", .environment, value: { _ in .nilValue }, read: { env, _ in
            #if os(iOS)
            return symbol(env.preferredPencilDoubleTapAction)
            #else
            return .nilValue
            #endif
        })
        r.environmentValue("preferredPencilSqueezeAction", .environment, value: { _ in .nilValue }, read: { env, _ in
            #if os(iOS)
            return symbol(env.preferredPencilSqueezeAction)
            #else
            return .nilValue
            #endif
        })
        r.environmentValue("isUserAuthenticationEnabled", .environment, value: { _ in .bool(true) }, read: { env, _ in
            if #available(iOS 18, macOS 15, *) { return .bool(env.isUserAuthenticationEnabled) }
            return .bool(true)
        })
        r.environmentValue("tabBarPlacement", .environment, value: { _ in .nilValue }, read: { env, _ in
            #if os(iOS)
            if #available(iOS 18, *) { return env.tabBarPlacement.map { symbol($0) } ?? .nilValue }
            #endif
            return .nilValue
        })
        r.environmentValue("buttonSizing", .environment, value: { _ in .native(.implicit("automatic", [])) }, read: { env, _ in
            if #available(iOS 26, macOS 26, *) { return symbol(env.buttonSizing) }
            return .native(.implicit("automatic", []))
        })
        r.environmentValue("findContext", .environment, value: { _ in .nilValue }, read: { _, _ in .nilValue })
        r.environmentValue("isTabViewSidebarAvailable", .environment, value: { _ in .bool(false) }, read: { env, _ in
            if #available(iOS 27, macOS 27, *) { return .bool(env.isTabViewSidebarAvailable) }
            return .bool(false)
        })
        r.environmentValue("systemPrefersReducedResourceUsage", .environment, value: { _ in .bool(false) }, read: { env, _ in
            if #available(iOS 27, macOS 27, *) { return .bool(env.systemPrefersReducedResourceUsage) }
            return .bool(false)
        })
        for key in ["overlayArrangementZIndex", "splitArrangementAxis"] {
            r.environmentValue(key, .environment, value: { _ in .nilValue }, read: { _, _ in .nilValue })
        }
    }

    // MARK: Actions

    static func actions(_ r: KRegistry) {
        r.environmentValue("openURL", .text, notes: "Web, mail, phone and Maps links open (outside Shelf); other schemes are refused.",
                           value: { _ in .native(.object("OpenURLAction", KRef(KOpenURL(nil)))) },
                           read: { env, _ in .native(.object("OpenURLAction", KRef(KOpenURL(env.openURL)))) },
                           write: { env, v, _ in if case .native(.object(_, let ref)) = v, let a = (ref.value as? KOpenURL)?.action { env.openURL = a } })
        r.type("OpenURLAction", .text, support: .full) { t in
            t.initializer("handler:closure") { c in
                guard case .function(let fn)? = c["handler"] else { throw c.fail("needs a handler") }
                let interp = c.interp
                return .native(.object("OpenURLAction", KRef(KOpenURL(OpenURLAction { url in
                    let v = (try? interp.entry { try interp.call(fn, [.native(.url(url))], [nil]) }) ?? .nilValue
                    return KOpenURL.result(v)
                }))))
            }
            t.method("callAsFunction", "_:URL") { c in
                if let url = c.url(0) { c.object(KOpenURL.self)?.open(url, c.interp) }
                return .void
            }
            t.method("callAsFunction", "_:URL completion:closure") { c in
                guard let url = c.url(0) else { return .void }
                let interp = c.interp
                let done = c.function("completion")
                c.object(KOpenURL.self)?.open(url, interp) { accepted in if let done { interp.perform(done, [.bool(accepted)]) } }
                return .void
            }
        }
        r.type("OpenURLAction.Result", .text) { t in
            t.internal()
            t.staticProperty("handled") { _ in .native(.implicit("handled", [])) }
            t.staticProperty("discarded") { _ in .native(.implicit("discarded", [])) }
            t.staticProperty("systemAction") { _ in .native(.implicit("systemAction", [])) }
            t.staticMethod("systemAction", "_:URL") { c in .native(.implicit("systemAction", c.args)) }
            t.staticMethod("systemAction", "_:URL prefersInApp:bool") { c in .native(.implicit("systemAction", c.args)) }
        }
        r.environmentValue("refresh", .environment, notes: "nil outside a `.refreshable` view; `await refresh?()`.", value: { _ in .nilValue },
                           read: { env, _ in env.refresh.map { .native(.object("RefreshAction", KRef(KBoxRef($0)))) } ?? .nilValue })
        r.type("RefreshAction", .environment, support: .full) { t in
            t.method("callAsFunction", "", async: true) { c in
                guard let action = c.object(KBoxRef<RefreshAction>.self)?.value else { return .void }
                return .suspension(KSuspension.async(headless: { .void }) { await action(); return .void })
            }
        }
        r.environmentValue("rename", .environment, value: { _ in .nilValue },
                           read: { env, _ in env.rename.map { .native(.object("RenameAction", KRef(KBoxRef($0)))) } ?? .nilValue })
        r.type("RenameAction", .environment, support: .full) { t in
            t.method("callAsFunction", "") { c in
                c.object(KBoxRef<RenameAction>.self)?.value()
                return .void
            }
        }
        r.type("UndoManager", .environment, support: .partial, notes: "`undo()`, `redo()`, `canUndo`, `canRedo` and `registerUndo(withTarget:handler:)`.") { t in
            t.method("undo", "") { c in c.object(UndoManager.self)?.undo(); return .void }
            t.method("redo", "") { c in c.object(UndoManager.self)?.redo(); return .void }
            t.property("canUndo") { c in .bool(c.object(UndoManager.self)?.canUndo ?? false) }
            t.property("canRedo") { c in .bool(c.object(UndoManager.self)?.canRedo ?? false) }
            t.method("removeAllActions", "") { c in c.object(UndoManager.self)?.removeAllActions(); return .void }
            t.method("setActionName", "_:string") { c in c.object(UndoManager.self)?.setActionName(c.string(0) ?? ""); return .void }
            t.method("registerUndo", "withTarget:any handler:closure") { c in
                guard let manager = c.object(UndoManager.self), case .function(let fn)? = c["handler"] else { return .void }
                let interp = c.interp
                let target = c["withTarget"] ?? .nilValue
                manager.registerUndo(withTarget: KBoxRef(target)) { box in interp.perform(fn, [box.value]) }
                return .void
            }
        }
    }
}

/// A value kept by reference, for a native object a value type stands in for.
final class KBoxRef<T>: NSObject {
    let value: T
    init(_ value: T) { self.value = value }
}

/// `@Environment(\.openURL)`: SwiftUI's action (which the run's root routes
/// through the host), or the app's own `OpenURLAction(handler:)`.
@MainActor
final class KOpenURL: NSObject {
    let action: OpenURLAction?
    init(_ action: OpenURLAction?) { self.action = action }

    func open(_ url: URL, _ interp: KInterpreter, completion: ((Bool) -> Void)? = nil) {
        if let action {
            if let completion { action(url, completion: completion) } else { action(url) }
            return
        }
        // No view has shown it yet (a check): the host decides, or nothing opens.
        let opened = interp.context.openURL?(url) ?? false
        completion?(opened)
    }

    static func result(_ v: KV) -> OpenURLAction.Result {
        guard case .native(.implicit(let n, let args)) = v else { return .handled }
        switch n {
        case "discarded": return .discarded
        case "systemAction":
            if case .native(.url(let u))? = args.first { return .systemAction(u) }
            return .systemAction
        default: return .handled
        }
    }
}

/// `DynamicTypeSize` values, which compare by size.
@MainActor
enum KDynamicType {
    static let order: [DynamicTypeSize] = [.xSmall, .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
                                           .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5]
    static func wrap(_ s: DynamicTypeSize) -> KV {
        .native(.boxed(KBoxed("DynamicTypeSize", s, caseName: String(describing: s), order: order.firstIndex(of: s))))
    }
    static func size(_ v: KV) -> DynamicTypeSize? {
        if let s = v.boxed(DynamicTypeSize.self) { return s }
        if case .native(.implicit(let n, _)) = v { return order.first { String(describing: $0) == n } }
        return nil
    }
}
