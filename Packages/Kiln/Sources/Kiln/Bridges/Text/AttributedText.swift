//
//  AttributedText.swift
//  Bridges: AttributedString, Markdown and timer text
//
//  `AttributedString(markdown:)`, whole-string attributes (`s.foregroundColor
//  = .red`), and `Text(attributed)`; `Text(timerInterval:)`. A
//  `TextEditor(text: $attributed)` keeps the styling (iOS 26).
//

import SwiftUI

/// An AttributedString as Kiln holds it.
final class KAttributedBox {
    var value: AttributedString
    init(_ value: AttributedString) { self.value = value }
}

@MainActor
enum KAttributed {
    static func value(_ v: KV?) -> AttributedString? {
        if case .native(.object("AttributedString", let ref))? = v, let box = ref.value as? KAttributedBox { return box.value }
        return nil
    }

    static func kv(_ a: AttributedString) -> KV { .native(.object("AttributedString", KRef(KAttributedBox(a)))) }
}

extension KTextBridges {
    static func attributed(_ r: KRegistry) {
        r.type("AttributedString", .text, support: .partial,
               notes: "`AttributedString(\"…\")` and `AttributedString(markdown:)`, attributes set on the whole string (`foregroundColor`, `backgroundColor`, `font`, `link`), `append`, and `String(s.characters)`. Ranges and runs aren't bridged.") { t in
            t.initializer("") { _ in KAttributed.kv(AttributedString()) }
            t.initializer("_:string") { c in KAttributed.kv(AttributedString(c.string(0) ?? "")) }
            t.initializer("markdown:string") { c in
                do {
                    return KAttributed.kv(try AttributedString(markdown: c.string("markdown") ?? "",
                                                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                } catch {
                    throw KEThrown(value: KBuiltins.errorValue("The Markdown couldn't be read"))
                }
            }
            @MainActor func box(_ c: KCall) -> KAttributedBox? {
                if case .native(.object(_, let ref)) = c.receiver { return ref.value as? KAttributedBox }
                return nil
            }
            t.property("characters") { c in .string(String(box(c)?.value.characters ?? AttributedString().characters)) }
            t.property("description") { c in .string(String(box(c)?.value.characters ?? AttributedString().characters)) }
            t.property("foregroundColor", { _ in .nilValue }, set: { c in box(c)?.value.foregroundColor = c.r.color(c.first) })
            t.property("backgroundColor", { _ in .nilValue }, set: { c in box(c)?.value.backgroundColor = c.r.color(c.first) })
            t.property("font", { _ in .nilValue }, set: { c in box(c)?.value.font = c.r.font(c.first) })
            t.property("link", { _ in .nilValue }, set: { c in box(c)?.value.link = c.url(0) })
            t.method("append", "_:any") { c in
                guard let b = box(c) else { return .void }
                var out = b.value
                if let other = KAttributed.value(c.first) { out.append(other) } else { out.append(AttributedString(c.string(0) ?? "")) }
                c.mutated = KAttributed.kv(out)
                return .void
            }
        }
    }
}

extension KRenderer {
    /// `Text(attributed)` and `Text(timerInterval:)`, before the other forms.
    func attributedText(_ a: KArgs) -> Text? {
        if let interval = a["timerInterval"], case .range(.native(.date(let lo)), .native(.date(let hi)), _) = interval, lo <= hi {
            var pause: Date? = nil
            if case .native(.date(let p))? = a["pauseTime"] { pause = p }
            return Text(timerInterval: lo...hi, pauseTime: pause, countsDown: a["countsDown"].map { interp.truthy($0) } ?? true,
                        showsHours: a["showsHours"].map { interp.truthy($0) } ?? true)
        }
        if let s = KAttributed.value(a.first) { return Text(s) }
        return nil
    }
}
