//
//  KEDiagnostics.swift
//  Kiln's engine
//
//  Errors about the app's own types (PLAN.md §1.6), worded like the
//  registry's errors about Kiln's (KResolve): what was written, then what
//  there is, with the line.
//
//      Line 9: 'Person' has no greet(nmae:); it has greet(name:)
//      Line 4: 'Pet' has no init(kind:); it has init(name:)
//      Line 7: There's no total(of:); there's total(for:)
//      Line 3: 'Shape' has no case circle(r:); it has circle(radius:)
//      Line 5: Value of type 'Person' has no member 'nmae' (did you mean 'name'?)
//
//  Missing conformances are where they're checked: KEProtocols (requirements),
//  KEEval (`==`, `<`, `allCases`), KERender (ForEach ids), Coding (JSON).
//

import SwiftUI

extension KInterpreter {

    /// `greet(name:)`.
    func written(_ name: String, _ labels: [String?]) -> String {
        name + "(" + labels.map { ($0 ?? "_") + ":" }.joined() + ")"
    }

    /// Throws when `chosen` doesn't take these labels: the overloads there are.
    /// `owner` names the type (nil for a global function).
    func requireLabels(_ chosen: KEFuncDecl?, among all: [KEFuncDecl], _ labels: [String?], closures: [Bool]? = nil, name: String, owner: String?,
                       isStatic: Bool = false, line: Int) throws {
        if let chosen, Self.labelsFit(chosen.params, labels, closures: closures) { return }
        if all.contains(where: { Self.labelsFit($0.params, labels, closures: closures) }) { return }
        let known = Self.list(all.map(\.signature))
        let what = written(name, labels)
        if let owner {
            throw fail("'\(owner)' has no \(isStatic ? "static " : "")\(what); it has \(known)", line)
        }
        throw fail("There's no \(what); there's \(known)", line)
    }

    /// The memberwise initializer's labels: `init(name:age:)`.
    func memberwiseSignature(_ t: KType) -> String {
        "init(" + memberwiseParams(t).map { $0.name + ":" }.joined() + ")"
    }

    /// Labels a memberwise initializer doesn't have.
    func requireMemberwiseLabels(_ t: KType, _ labels: [String?], line: Int) throws {
        let names = Set(memberwiseParams(t).map(\.name))
        guard labels.contains(where: { $0 != nil && !names.contains($0!) }) else { return }
        var known = [memberwiseSignature(t)]
        if !t.inits.isEmpty { known = t.inits.map(\.signature) }
        throw fail("'\(t.name)' has no \(written("init", labels)); it has \(Self.list(known))", line)
    }

    /// `.circle(r: 1)` for `case circle(radius: Double)`.
    func requireCaseLabels(_ t: KType, _ c: KEEnumCase, _ labels: [String?], line: Int) throws {
        let declared = c.associated.map(\.0)
        let fits = labels.count <= declared.count && zip(labels, declared).allSatisfy { $0 == $1 }
            && declared.dropFirst(labels.count).isEmpty
        guard !fits else { return }
        let has = c.name + (declared.isEmpty ? "" : "(" + declared.map { ($0 ?? "_") + ":" }.joined() + ")")
        throw fail("'\(t.name)' has no case \(written(c.name, labels)); it has \(has)", line)
    }

    /// `Value of type 'Person' has no member 'nmae' (did you mean 'name'?)`.
    func noMember(_ t: KType, _ name: String, line: Int, isStatic: Bool = false) -> KERuntimeError {
        var names: [String] = isStatic ? Array(t.staticDecls.keys) + Array(t.staticMethods.keys) + t.cases.map(\.name)
            : t.stored.map(\.name) + Array(t.computed.keys) + Array(t.methods.keys)
        names = Array(Set(names))
        let hint = Self.closest(name, names).map { " (did you mean '\($0)'?)" } ?? ""
        if isStatic { return fail("Type '\(t.name)' has no member '\(name)'\(hint)", line) }
        return fail("Value of type '\(t.name)' has no member '\(name)'\(hint)", line)
    }

    /// The name a typo most likely meant: within two edits, and unambiguous.
    nonisolated static func closest(_ name: String, _ candidates: [String]) -> String? {
        let scored = candidates.map { ($0, distance(name.lowercased(), $0.lowercased())) }.filter { $0.1 <= min(2, max(1, name.count / 3)) }
        guard let best = scored.min(by: { $0.1 < $1.1 }) else { return nil }
        return scored.filter { $0.1 == best.1 }.count == 1 ? best.0 : nil
    }

    /// Edits between two names, a swapped pair counting as one (`nmae` → `name`).
    nonisolated static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var d = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in 0...a.count { d[i][0] = i }
        for j in 0...b.count { d[0][j] = j }
        for i in 1...a.count {
            for j in 1...b.count {
                d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
                if i > 1, j > 1, a[i - 1] == b[j - 2], a[i - 2] == b[j - 1] { d[i][j] = min(d[i][j], d[i - 2][j - 2] + 1) }
            }
        }
        return d[a.count][b.count]
    }
}
