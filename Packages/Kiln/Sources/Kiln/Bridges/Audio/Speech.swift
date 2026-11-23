//
//  Speech.swift
//  Bridges: AVSpeechSynthesizer and its voices (PLAN.md §3.5)
//
//  `synth.speak(utterance)`, pausing, stopping, the utterance's rate, pitch,
//  volume, delays and voice, `AVSpeechSynthesisVoice` by language or
//  identifier, and the delegate's callbacks. A check never speaks.
//

import Foundation
import AVFoundation

extension AudioBridges {
    static func speech(_ r: KRegistry) {
        r.type("AVSpeechSynthesizer", .audio, support: .full) { t in
            t.initializer("") { c in
                let synth = AVSpeechSynthesizer()
                KAudioRun.of(c.context).track(synth) { synth.stopSpeaking(at: .immediate) }
                return .native(.object("AVSpeechSynthesizer", KRef(synth)))
            }
            @MainActor func synth(_ c: KCall) -> AVSpeechSynthesizer? { c.object(AVSpeechSynthesizer.self) }
            @MainActor func boundary(_ c: KCall) -> AVSpeechBoundary { c.symbol("at") == "word" ? .word : .immediate }
            t.method("speak", "_:any") { c in
                guard let s = synth(c), case .native(.object(_, let ref))? = c[0], let u = ref.value as? AVSpeechUtterance else {
                    throw c.fail("needs an AVSpeechUtterance")
                }
                guard isLive(c) else { return .void }
                KAudioRun.of(c.context).willPlay()
                s.speak(u)
                return .void
            }
            t.method("stopSpeaking", "at:any") { c in .bool(synth(c)?.stopSpeaking(at: boundary(c)) ?? false) }
            t.method("pauseSpeaking", "at:any") { c in .bool(synth(c)?.pauseSpeaking(at: boundary(c)) ?? false) }
            t.method("continueSpeaking", "") { c in .bool(synth(c)?.continueSpeaking() ?? false) }
            t.property("isSpeaking") { c in .bool(synth(c)?.isSpeaking ?? false) }
            t.property("isPaused") { c in .bool(synth(c)?.isPaused ?? false) }
            // Always the host's session.
            t.property("usesApplicationAudioSession", { _ in .bool(true) }, set: { _ in })
            t.property("delegate", { _ in .nilValue }, set: { c in
                guard let s = synth(c) else { return }
                if c.args[0].isNil { s.delegate = nil; KDelegates.retain(nil, by: s); return }
                guard let proxy = KDelegates.proxy(for: c.args[0], c.interp) else {
                    throw c.fail("the delegate should be a class that adopts AVSpeechSynthesizerDelegate")
                }
                s.delegate = unsafeBitCast(proxy, to: AVSpeechSynthesizerDelegate.self)
                KDelegates.retain(proxy, by: s)
            })
        }
        r.type("AVSpeechBoundary", .audio, support: .full) { t in t.anyStatic { _, member in .native(.implicit(member, [])) } }

        r.type("AVSpeechUtterance", .audio, support: .full) { t in
            t.initializer("string:string") { c in
                .native(.object("AVSpeechUtterance", KRef(AVSpeechUtterance(string: c.string("string") ?? ""))))
            }
            t.initializer("ssmlRepresentation:string") { c in
                guard let u = AVSpeechUtterance(ssmlRepresentation: c.string("ssmlRepresentation") ?? "") else { return .nilValue }
                return .native(.object("AVSpeechUtterance", KRef(u)))
            }
            @MainActor func u(_ c: KCall) -> AVSpeechUtterance? { c.object(AVSpeechUtterance.self) }
            t.property("speechString") { c in .string(u(c)?.speechString ?? "") }
            for (name, path) in [("rate", \AVSpeechUtterance.rate), ("pitchMultiplier", \.pitchMultiplier), ("volume", \.volume)] {
                t.property(name, { c in .double(Double(u(c)?[keyPath: path] ?? 0)) },
                           set: { c in u(c)?[keyPath: path] = Float(c.double(0) ?? 0) })
            }
            for (name, path) in [("preUtteranceDelay", \AVSpeechUtterance.preUtteranceDelay), ("postUtteranceDelay", \.postUtteranceDelay)] {
                t.property(name, { c in .double(u(c)?[keyPath: path] ?? 0) },
                           set: { c in u(c)?[keyPath: path] = c.double(0) ?? 0 })
            }
            t.property("prefersAssistiveTechnologySettings", { c in .bool(u(c)?.prefersAssistiveTechnologySettings ?? false) },
                       set: { c in u(c)?.prefersAssistiveTechnologySettings = c.bool(0, default: false) })
            t.property("voice", { c in u(c)?.voice.map(voice) ?? .nilValue }, set: { c in
                if case .native(.object(_, let ref))? = c[0] { u(c)?.voice = ref.value as? AVSpeechSynthesisVoice } else { u(c)?.voice = nil }
            })
        }
        r.nativeClass(AVSpeechUtterance.self, "AVSpeechUtterance")
        r.nativeClass(AVSpeechSynthesizer.self, "AVSpeechSynthesizer")
        r.addConstant("AVSpeechUtteranceDefaultSpeechRate") { _ in .double(Double(AVSpeechUtteranceDefaultSpeechRate)) }
        r.addConstant("AVSpeechUtteranceMinimumSpeechRate") { _ in .double(Double(AVSpeechUtteranceMinimumSpeechRate)) }
        r.addConstant("AVSpeechUtteranceMaximumSpeechRate") { _ in .double(Double(AVSpeechUtteranceMaximumSpeechRate)) }

        r.type("AVSpeechSynthesisVoice", .audio, support: .full) { t in
            t.initializer("language:string?") { c in
                AVSpeechSynthesisVoice(language: c.string("language")).map(voice) ?? .nilValue
            }
            t.initializer("identifier:string") { c in
                AVSpeechSynthesisVoice(identifier: c.string("identifier") ?? "").map(voice) ?? .nilValue
            }
            t.staticMethod("speechVoices", "") { _ in .array(AVSpeechSynthesisVoice.speechVoices().map(voice)) }
            t.staticMethod("currentLanguageCode", "") { _ in .string(AVSpeechSynthesisVoice.currentLanguageCode()) }
            @MainActor func v(_ c: KCall) -> AVSpeechSynthesisVoice? { c.object(AVSpeechSynthesisVoice.self) }
            t.property("name") { c in .string(v(c)?.name ?? "") }
            t.property("language") { c in .string(v(c)?.language ?? "") }
            t.property("identifier") { c in .string(v(c)?.identifier ?? "") }
            t.property("quality") { c in
                switch v(c)?.quality {
                case .enhanced?: return .native(.implicit("enhanced", []))
                case .premium?: return .native(.implicit("premium", []))
                default: return .native(.implicit("default", []))
                }
            }
            t.property("gender") { c in
                switch v(c)?.gender {
                case .male?: return .native(.implicit("male", []))
                case .female?: return .native(.implicit("female", []))
                default: return .native(.implicit("unspecified", []))
                }
            }
        }
        r.nativeClass(AVSpeechSynthesisVoice.self, "AVSpeechSynthesisVoice")

        // Swift names these after the utterance; their selectors say "SpeechUtterance".
        let callbacks = ["didStart", "didFinish", "didPause", "didContinue", "didCancel"]
        r.delegateProtocol("AVSpeechSynthesizerDelegate", .audio,
                           requirements: callbacks.map { "speechSynthesizer(_:\($0):)?" }
                               + ["speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)?"],
) { spec in
            for name in callbacks { spec.selectors["speechSynthesizer(_:\(name):)"] = "speechSynthesizer:\(name)SpeechUtterance:" }
            spec.arguments("speechSynthesizer(_:willSpeakRangeOfSpeechString:utterance:)") { args, _ in
                let range = (args.count > 1 ? args[1] as? NSValue : nil)?.rangeValue ?? NSRange(location: 0, length: 0)
                return [KNativeValues.kv(from: args.first), .native(.boxed(KBoxed("NSRange", range))),
                        KNativeValues.kv(from: args.count > 2 ? args[2] : nil)]
            }
        }
        r.type("NSRange", .audio, support: .full) { t in
            t.property("location") { c in .int((c.receiver.boxedValue(NSRange.self))?.location ?? 0) }
            t.property("length") { c in .int((c.receiver.boxedValue(NSRange.self))?.length ?? 0) }
        }
    }

    static func voice(_ v: AVSpeechSynthesisVoice) -> KV { .native(.object("AVSpeechSynthesisVoice", KRef(v))) }
}

extension KV {
    /// The native value type a `.boxed` value holds.
    func boxedValue<T>(_: T.Type) -> T? {
        if case .native(.boxed(let b)) = self { return b.get(T.self) }
        return nil
    }
}
