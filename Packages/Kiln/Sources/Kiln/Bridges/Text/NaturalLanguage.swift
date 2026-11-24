//
//  NaturalLanguage.swift
//  Bridges: the NaturalLanguage framework (PLAN.md §3.3)
//
//      let tagger = NLTagger(tagSchemes: [.lexicalClass, .sentimentScore])
//      tagger.string = review
//      let (score, _) = tagger.tag(at: review.startIndex, unit: .paragraph, scheme: .sentimentScore)
//      tagger.enumerateTags(in: review.startIndex..<review.endIndex, unit: .word, scheme: .lexicalClass,
//                           options: [.omitWhitespace, .omitPunctuation]) { tag, range in
//          if tag == .noun { nouns.append(String(review[range])) }
//          return true
//      }
//
//  `NLTokenizer`, `NLTagger`, `NLLanguageRecognizer` and `NLEmbedding` are
//  the framework's own, on the device's own models. Ranges are character
//  offsets, as every string index in Kiln, so `text[range]` reads a token.
//  A tag is a value with its `rawValue` (`"Noun"`, or a sentiment score as
//  text: `Double(tag.rawValue)`), equal to the symbol the app compares it with.
//

import SwiftUI
import NaturalLanguage

/// `NLTag`, `NLLanguage`, `NLTagScheme`: names and raw values.
@MainActor
enum KNL {
    static let tags: [String: NLTag] = [
        "word": .word, "punctuation": .punctuation, "whitespace": .whitespace, "other": .other,
        "noun": .noun, "verb": .verb, "adjective": .adjective, "adverb": .adverb, "pronoun": .pronoun, "determiner": .determiner,
        "particle": .particle, "preposition": .preposition, "number": .number, "conjunction": .conjunction, "interjection": .interjection,
        "classifier": .classifier, "idiom": .idiom, "otherWord": .otherWord, "sentenceTerminator": .sentenceTerminator,
        "openQuote": .openQuote, "closeQuote": .closeQuote, "openParenthesis": .openParenthesis, "closeParenthesis": .closeParenthesis,
        "wordJoiner": .wordJoiner, "dash": .dash, "otherPunctuation": .otherPunctuation, "paragraphBreak": .paragraphBreak,
        "otherWhitespace": .otherWhitespace, "personalName": .personalName, "placeName": .placeName, "organizationName": .organizationName,
    ]
    static let schemes: [String: NLTagScheme] = [
        "tokenType": .tokenType, "lexicalClass": .lexicalClass, "nameType": .nameType, "nameTypeOrLexicalClass": .nameTypeOrLexicalClass,
        "lemma": .lemma, "language": .language, "script": .script, "sentimentScore": .sentimentScore,
    ]
    static let languages: [String: NLLanguage] = [
        "undetermined": .undetermined, "amharic": .amharic, "arabic": .arabic, "armenian": .armenian, "bengali": .bengali,
        "bulgarian": .bulgarian, "burmese": .burmese, "catalan": .catalan, "cherokee": .cherokee, "croatian": .croatian, "czech": .czech,
        "danish": .danish, "dutch": .dutch, "english": .english, "finnish": .finnish, "french": .french, "georgian": .georgian,
        "german": .german, "greek": .greek, "gujarati": .gujarati, "hebrew": .hebrew, "hindi": .hindi, "hungarian": .hungarian,
        "icelandic": .icelandic, "indonesian": .indonesian, "italian": .italian, "japanese": .japanese, "kannada": .kannada,
        "kazakh": .kazakh, "khmer": .khmer, "korean": .korean, "lao": .lao, "malay": .malay, "malayalam": .malayalam,
        "marathi": .marathi, "mongolian": .mongolian, "norwegian": .norwegian, "oriya": .oriya, "persian": .persian, "polish": .polish,
        "portuguese": .portuguese, "punjabi": .punjabi, "romanian": .romanian, "russian": .russian, "simplifiedChinese": .simplifiedChinese,
        "sinhalese": .sinhalese, "slovak": .slovak, "spanish": .spanish, "swedish": .swedish, "tamil": .tamil, "telugu": .telugu,
        "thai": .thai, "tibetan": .tibetan, "traditionalChinese": .traditionalChinese, "turkish": .turkish, "ukrainian": .ukrainian,
        "urdu": .urdu, "vietnamese": .vietnamese,
    ]
    static let units: [String: NLTokenUnit] = ["word": .word, "sentence": .sentence, "paragraph": .paragraph, "document": .document]
    static let options: [String: NLTagger.Options] = ["omitWords": .omitWords, "omitPunctuation": .omitPunctuation,
                                                      "omitWhitespace": .omitWhitespace, "omitOther": .omitOther,
                                                      "joinNames": .joinNames, "joinContractions": .joinContractions]

    static func tag(_ t: NLTag?) -> KV {
        guard let t else { return .nilValue }
        return .native(.boxed(KBoxed("NLTag", t.rawValue, caseName: tags.first { $0.value == t }?.key)))
    }
    static func language(_ l: NLLanguage?) -> KV {
        guard let l else { return .nilValue }
        return .native(.boxed(KBoxed("NLLanguage", l.rawValue, caseName: languages.first { $0.value == l }?.key)))
    }

    /// A symbol or a value the app passed (`.english`, `NLLanguage("en")`).
    static func symbol(_ v: KV?) -> String? {
        switch v {
        case .native(.implicit(let n, let a))? where a.isEmpty: return n
        case .native(.boxed(let b))?: return b.caseName
        default: return nil
        }
    }
    static func languageArg(_ v: KV?) -> NLLanguage? {
        if case .native(.boxed(let b))? = v, b.type == "NLLanguage", let raw = b.get(String.self) { return NLLanguage(raw) }
        if case .string(let s)? = v { return NLLanguage(s) }
        return symbol(v).flatMap { languages[$0] }
    }
    static func scheme(_ v: KV?) -> NLTagScheme? { symbol(v).flatMap { schemes[$0] } }
    static func unit(_ v: KV?) -> NLTokenUnit { symbol(v).flatMap { units[$0] } ?? .word }
    static func taggerOptions(_ v: KV?) -> NLTagger.Options {
        switch v {
        case .array(let a)?: return a.reduce([]) { $0.union(taggerOptions($1)) }
        default: return symbol(v).flatMap { options[$0] } ?? []
        }
    }

    /// Character offsets → `String.Index`es in `text`.
    static func indexRange(_ v: KV?, in text: String) -> Range<String.Index> {
        guard case .range(let lo, let hi, let closed)? = v else { return text.startIndex..<text.endIndex }
        let l = min(max(lo.asInt ?? 0, 0), text.count)
        var h = hi.isNil ? text.count : (hi.asInt ?? text.count)
        if closed && !hi.isNil { h += 1 }
        h = min(max(h, l), text.count)
        return text.index(text.startIndex, offsetBy: l)..<text.index(text.startIndex, offsetBy: h)
    }
    static func index(_ v: KV?, in text: String) -> String.Index {
        text.index(text.startIndex, offsetBy: min(max(v?.asInt ?? 0, 0), text.count))
    }
}

/// An `NLTagger` and the text it was given (its `string`).
final class KTagger {
    let tagger: NLTagger
    init(_ t: NLTagger) { tagger = t }
}

extension KTextBridges {
    static func naturalLanguage(_ r: KRegistry) {
        tokenizer(r)
        tagger(r)
        recognizer(r)
        embedding(r)
        values(r)
    }

    static func tokenizer(_ r: KRegistry) {
        r.type("NLTokenizer", .text, support: .full,
               notes: "`NLTokenizer(unit: .word)`; set `string`, then `tokens(for: text.startIndex..<text.endIndex)` or `enumerateTokens(in:)`.") { t in
            t.initializer("unit:any") { c in .native(.object("NLTokenizer", KRef(NLTokenizer(unit: KNL.unit(c["unit"]))))) }
            @MainActor func tk(_ c: KCall) throws -> NLTokenizer {
                guard let x = c.object(NLTokenizer.self) else { throw c.noMember() }
                return x
            }
            t.property("string", { c in try tk(c).string.map { .string($0) } ?? .nilValue }, set: { c in try tk(c).string = c.args.first?.asString })
            t.property("unit") { c in .native(.implicit(KNL.units.first { $0.value == (try? tk(c).unit) }?.key ?? "word", [])) }
            t.method("setLanguage", "_:any") { c in
                if let l = KNL.languageArg(c[0]) { try tk(c).setLanguage(l) }
                return .void
            }
            t.method("tokens", "for:any") { c in
                let x = try tk(c), text = x.string ?? ""
                return .array(x.tokens(for: KNL.indexRange(c["for"], in: text)).map { KBuiltins.offsetRange($0, in: text) })
            }
            t.method("tokenRange", "at:any") { c in
                let x = try tk(c), text = x.string ?? ""
                return KBuiltins.offsetRange(x.tokenRange(at: KNL.index(c["at"], in: text)), in: text)
            }
            t.method("tokenRange", "for:any") { c in
                let x = try tk(c), text = x.string ?? ""
                return KBuiltins.offsetRange(x.tokenRange(for: KNL.indexRange(c["for"], in: text)), in: text)
            }
            t.method("enumerateTokens", "in:any using:closure") { c in
                let x = try tk(c), text = x.string ?? ""
                guard let f = c.function("using") else { throw c.fail("needs a closure") }
                var failure: Error?
                x.enumerateTokens(in: KNL.indexRange(c["in"], in: text)) { range, attrs in
                    do {
                        let flags: [KV] = [attrs.contains(.numeric) ? .native(.implicit("numeric", [])) : nil,
                                           attrs.contains(.symbolic) ? .native(.implicit("symbolic", [])) : nil,
                                           attrs.contains(.emoji) ? .native(.implicit("emoji", [])) : nil].compactMap { $0 }
                        return c.interp.truthy(try c.interp.call(f, [KBuiltins.offsetRange(range, in: text), .array(flags)], [nil, nil]))
                    } catch { failure = error; return false }
                }
                if let failure { throw failure }
                return .void
            }
        }
    }

    static func tagger(_ r: KRegistry) {
        r.type("NLTagger", .text, support: .full,
               notes: "`NLTagger(tagSchemes: [.lexicalClass, .nameType, .lemma, .sentimentScore])`; set `string`, then `tag(at:unit:scheme:)`, `tags(in:unit:scheme:options:)` or `enumerateTags`. A sentiment score is `Double(tag.rawValue)`.") { t in
            t.initializer("tagSchemes:any") { c in
                let schemes = ((try? c.interp.sequence(c["tagSchemes"] ?? .array([]))) ?? []).compactMap(KNL.scheme)
                return .native(.object("NLTagger", KRef(KTagger(NLTagger(tagSchemes: schemes)))))
            }
            @MainActor func tg(_ c: KCall) throws -> NLTagger {
                guard let x = c.object(KTagger.self)?.tagger else { throw c.noMember() }
                return x
            }
            @MainActor func scheme(_ c: KCall) throws -> NLTagScheme {
                guard let s = KNL.scheme(c["scheme"]) else { throw c.fail("needs a scheme: .lexicalClass, .nameType, .lemma, .sentimentScore…") }
                return s
            }
            t.property("string", { c in try tg(c).string.map { .string($0) } ?? .nilValue }, set: { c in try tg(c).string = c.args.first?.asString })
            t.property("dominantLanguage") { c in KNL.language(try tg(c).dominantLanguage) }
            t.property("tagSchemes") { c in .array(try tg(c).tagSchemes.map { s in .native(.implicit(KNL.schemes.first { $0.value == s }?.key ?? s.rawValue, [])) }) }
            t.method("setLanguage", "_:any range:any") { c in
                let x = try tg(c), text = x.string ?? ""
                if let l = KNL.languageArg(c[0]) { x.setLanguage(l, range: KNL.indexRange(c["range"], in: text)) }
                return .void
            }
            t.method("tag", "at:any unit:any scheme:any") { c in
                let x = try tg(c), text = x.string ?? ""
                guard !text.isEmpty else { return .tuple([.nilValue, .range(.int(0), .int(0), closed: false)], [nil, nil]) }
                let (tag, range) = x.tag(at: KNL.index(c["at"], in: text), unit: KNL.unit(c["unit"]), scheme: try scheme(c))
                return .tuple([KNL.tag(tag), KBuiltins.offsetRange(range, in: text)], [nil, nil])
            }
            t.method("tags", "in:any unit:any scheme:any options:any?") { c in
                let x = try tg(c), text = x.string ?? ""
                let found = x.tags(in: KNL.indexRange(c["in"], in: text), unit: KNL.unit(c["unit"]), scheme: try scheme(c),
                                   options: KNL.taggerOptions(c["options"]))
                return .array(found.map { .tuple([KNL.tag($0.0), KBuiltins.offsetRange($0.1, in: text)], [nil, nil]) })
            }
            t.method("enumerateTags", "in:any unit:any scheme:any options:any? using:closure") { c in
                let x = try tg(c), text = x.string ?? ""
                guard let f = c.function("using") else { throw c.fail("needs a closure") }
                var failure: Error?
                x.enumerateTags(in: KNL.indexRange(c["in"], in: text), unit: KNL.unit(c["unit"]), scheme: try scheme(c),
                                options: KNL.taggerOptions(c["options"])) { tag, range in
                    do {
                        return c.interp.truthy(try c.interp.call(f, [KNL.tag(tag), KBuiltins.offsetRange(range, in: text)], [nil, nil]))
                    } catch { failure = error; return false }
                }
                if let failure { throw failure }
                return .void
            }
            t.staticMethod("availableTagSchemes", "for:any language:any") { c in
                guard let l = KNL.languageArg(c["language"]) else { return .array([]) }
                return .array(NLTagger.availableTagSchemes(for: KNL.unit(c["for"]), language: l).map { s in
                    .native(.implicit(KNL.schemes.first { $0.value == s }?.key ?? s.rawValue, []))
                })
            }
        }
    }

    static func recognizer(_ r: KRegistry) {
        r.type("NLLanguageRecognizer", .text, support: .full,
               notes: "`processString(_:)`, then `dominantLanguage` or `languageHypotheses(withMaximum:)`; `NLLanguageRecognizer.dominantLanguage(for:)`; `languageHints` and `languageConstraints`.") { t in
            t.initializer("") { _ in .native(.object("NLLanguageRecognizer", KRef(NLLanguageRecognizer()))) }
            t.staticMethod("dominantLanguage", "for:string") { c in KNL.language(NLLanguageRecognizer.dominantLanguage(for: c.string("for") ?? "")) }
            @MainActor func rec(_ c: KCall) throws -> NLLanguageRecognizer {
                guard let x = c.object(NLLanguageRecognizer.self) else { throw c.noMember() }
                return x
            }
            t.method("processString", "_:string") { c in try rec(c).processString(c.string(0) ?? ""); return .void }
            t.method("reset", "") { c in try rec(c).reset(); return .void }
            t.property("dominantLanguage") { c in KNL.language(try rec(c).dominantLanguage) }
            t.method("languageHypotheses", "withMaximum:number") { c in
                let h = try rec(c).languageHypotheses(withMaximum: c.int("withMaximum") ?? 3)
                var d: [KV: KV] = [:]
                for (l, p) in h { d[KNL.language(l)] = .double(p) }
                return .dict(d)
            }
            t.property("languageHints", { c in
                var d: [KV: KV] = [:]
                for (l, p) in try rec(c).languageHints { d[KNL.language(l)] = .double(p) }
                return .dict(d)
            }, set: { c in
                guard case .dict(let d)? = c.args.first else { return }
                var hints: [NLLanguage: Double] = [:]
                for (k, v) in d { if let l = KNL.languageArg(k) { hints[l] = v.asDouble ?? 0 } }
                try rec(c).languageHints = hints
            })
            t.property("languageConstraints", { c in .array(try rec(c).languageConstraints.map(KNL.language)) }, set: { c in
                let ls = ((try? c.interp.sequence(c.args.first ?? .array([]))) ?? []).compactMap(KNL.languageArg)
                try rec(c).languageConstraints = ls
            })
        }
    }

    static func embedding(_ r: KRegistry) {
        r.type("NLEmbedding", .text, support: .full,
               notes: "`NLEmbedding.wordEmbedding(for: .english)` (optional: not every language has one): `distance(between:and:)`, `neighbors(for:maximumCount:)`, `vector(for:)`, `contains`; `sentenceEmbedding(for:)`.") { t in
            t.staticMethod("wordEmbedding", "for:any") { c in
                guard let l = KNL.languageArg(c["for"]), let e = NLEmbedding.wordEmbedding(for: l) else { return .nilValue }
                return .native(.object("NLEmbedding", KRef(e)))
            }
            t.staticMethod("sentenceEmbedding", "for:any") { c in
                guard let l = KNL.languageArg(c["for"]), let e = NLEmbedding.sentenceEmbedding(for: l) else { return .nilValue }
                return .native(.object("NLEmbedding", KRef(e)))
            }
            @MainActor func em(_ c: KCall) throws -> NLEmbedding {
                guard let x = c.object(NLEmbedding.self) else { throw c.noMember() }
                return x
            }
            @MainActor func distanceType(_ c: KCall) -> NLDistanceType { .cosine }
            t.property("dimension") { c in .int(try em(c).dimension) }
            t.property("vocabularySize") { c in .int(try em(c).vocabularySize) }
            t.property("language") { c in KNL.language(try em(c).language) }
            t.property("revision") { c in .int(try em(c).revision) }
            t.method("contains", "_:string") { c in .bool(try em(c).contains(c.string(0) ?? "")) }
            t.method("vector", "for:string") { c in try em(c).vector(for: c.string("for") ?? "").map { .array($0.map { .double($0) }) } ?? .nilValue }
            t.method("distance", "between:string and:string distanceType:any?") { c in
                .double(try em(c).distance(between: c.string("between") ?? "", and: c.string("and") ?? "", distanceType: distanceType(c)))
            }
            t.method("neighbors", "for:string maximumCount:number distanceType:any?") { c in
                .array(try em(c).neighbors(for: c.string("for") ?? "", maximumCount: c.int("maximumCount") ?? 5, distanceType: distanceType(c))
                    .map { .tuple([.string($0.0), .double($0.1)], [nil, nil]) })
            }
        }
    }

    static func values(_ r: KRegistry) {
        r.type("NLTag", .text, support: .full, notes: "Compare with `.noun`, `.personalName`…; `rawValue` is its text.") { t in
            for n in KNL.tags.keys { t.staticProperty(n) { _ in KNL.tag(KNL.tags[n]) } }
            t.initializer("_:string") { c in KNL.tag(NLTag(c.string(0) ?? "")) }
            t.initializer("rawValue:string") { c in KNL.tag(NLTag(c.string("rawValue") ?? "")) }
            t.implicit { name, args, _ in args.isEmpty ? KNL.tags[name].map { KNL.tag($0) } : nil }
            t.property("rawValue") { c in
                if case .native(.boxed(let b)) = c.receiver, let raw = b.get(String.self) { return .string(raw) }
                return .nilValue
            }
        }
        r.type("NLLanguage", .text, support: .full, notes: "`.english`…; `rawValue` is its BCP 47 code (\"en\").") { t in
            for n in KNL.languages.keys { t.staticProperty(n) { _ in KNL.language(KNL.languages[n]) } }
            t.initializer("_:string") { c in KNL.language(NLLanguage(c.string(0) ?? "")) }
            t.initializer("rawValue:string") { c in KNL.language(NLLanguage(rawValue: c.string("rawValue") ?? "")) }
            t.implicit { name, args, _ in args.isEmpty ? KNL.languages[name].map { KNL.language($0) } : nil }
            t.property("rawValue") { c in
                if case .native(.boxed(let b)) = c.receiver, let raw = b.get(String.self) { return .string(raw) }
                return .nilValue
            }
        }
        for (type, names) in [("NLTagScheme", Array(KNL.schemes.keys)), ("NLTokenUnit", Array(KNL.units.keys)),
                              ("NLTagger.Options", Array(KNL.options.keys)), ("NLDistanceType", ["cosine"])] {
            r.type(type, .text, support: .full) { t in
                for n in names { t.staticProperty(n) { _ in .native(.implicit(n, [])) } }
            }
        }
    }
}
