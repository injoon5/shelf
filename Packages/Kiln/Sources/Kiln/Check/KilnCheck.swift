//
//  KilnCheck.swift
//  Kiln's checker (PLAN.md §1.8): the public half
//
//  `Kiln.check(source)` reads an app without running any of it and reports
//  what Kiln can tell before running: an API Kiln doesn't have, labels no
//  overload takes, an `await` where nothing can wait, an `async` call with
//  no `await`, a protocol requirement left out. Each issue has its line, a
//  column when the name is on that line, a message and, where there is one,
//  a suggestion ("did you mean …", or the overloads Kiln does have).
//
//  The checker is conservative. A false error stops an app from being
//  installed, so where it can't be sure (a value whose type it can't tell,
//  a type that inherits from something it doesn't know) it says nothing,
//  and `Kiln.validate` finds the rest by running the code headlessly.
//
//  It knows only what the registry knows (`Registry/`, `Bridges/`) and what
//  the app declares, so a bridge added in a later round is checked the day
//  it's registered: its overloads, its `support` (a stub is a warning), and
//  whether it's `async` (`async: true`) or its closures can wait
//  (`closuresCanWait`). `Docs/bridges.md` says what a bridge declares.
//

import Foundation

/// One thing `Kiln.check` found.
public struct KilnIssue: Sendable, Equatable, CustomStringConvertible {
    public enum Severity: String, Sendable {
        /// The app can't run as written: Shelf won't install it.
        case error
        /// It runs, but something in it does less than it says (a stub).
        case warning
    }

    /// What kind of problem it is. The error classes of PLAN.md §1.8.
    public enum Kind: String, Sendable, CaseIterable {
        /// The code doesn't parse.
        case syntax
        /// There's no view to show (no `ContentView`).
        case noView
        /// A type, function or value that Kiln doesn't have and the app doesn't declare.
        case unknownName
        /// A member a type doesn't have: `Color.mintGreen`, `habit.nmae`.
        case unknownMember
        /// A modifier Kiln doesn't have: `.stepValue(0.1)`.
        case unknownModifier
        /// Arguments no overload takes: `.blur(10)` for `.blur(radius: 10)`.
        case arguments
        /// A form that needs a later iOS than the phone has.
        case unavailable
        /// `await` where nothing can wait: `body`, a computed property, an
        /// `init`, a function that isn't `async`, a closure that isn't run as a task.
        case awaitNotAllowed
        /// A call to an `async` function with no `await`.
        case missingAwait
        /// A type adopts a protocol and leaves out what it requires (`View` without `body`).
        case missingRequirement
        /// An argument written as the wrong kind of thing: a value where a binding (`$value`) goes.
        case argumentType
        /// Accepted, but it has no effect yet (a stub bridge). Always a warning.
        case stub
    }

    public let severity: Severity
    public let kind: Kind
    /// 1-based. 0 when Kiln couldn't tell.
    public let line: Int
    /// 1-based, when the name the issue is about is on its line.
    public let column: Int?
    public let message: String
    /// What to write instead: "did you mean `.padding`?", or the forms Kiln has.
    public let suggestion: String?

    public init(severity: Severity, kind: Kind, line: Int, column: Int? = nil, message: String, suggestion: String? = nil) {
        self.severity = severity
        self.kind = kind
        self.line = line
        self.column = column
        self.message = message
        self.suggestion = suggestion
    }

    public var isError: Bool { severity == .error }

    /// The message and suggestion as one sentence, without the line.
    public var text: String { suggestion.map { message + ". " + $0 } ?? message }

    /// `Line 12: Kiln has no .blur(_:). It has .blur(radius:opaque:)`, the
    /// shape every Kiln error has (Shelf's error screen reads the line).
    public var description: String { (line > 0 ? "Line \(line): " : "") + text }
}

/// What `Kiln.check` found, errors first, each list in line order.
public struct KilnCheck: Sendable {
    public let issues: [KilnIssue]

    public var errors: [KilnIssue] { issues.filter(\.isError) }
    public var warnings: [KilnIssue] { issues.filter { !$0.isError } }
    /// No errors: the app may be installed (warnings don't block).
    public var passed: Bool { !issues.contains(where: \.isError) }
    /// What a person sees first.
    public var firstError: KilnIssue? { errors.first }

    public init(issues: [KilnIssue]) {
        let errors = issues.filter(\.isError).sorted { ($0.line, $0.column ?? 0) < ($1.line, $1.column ?? 0) }
        let warnings = issues.filter { !$0.isError }.sorted { ($0.line, $0.column ?? 0) < ($1.line, $1.column ?? 0) }
        self.issues = errors + warnings
    }
}

extension Kiln {
    /// Checks `source` without running it (PLAN.md §1.8): every type, member,
    /// modifier and call against the registry and the app's own declarations,
    /// `await` and `async`, and the requirements of the protocols the app's
    /// types adopt. Fast: one pass over the syntax tree, no evaluation.
    ///
    /// An error means the app can't run as written; a warning means something
    /// in it does nothing yet (a stub). `Kiln.validate` is the other half: it
    /// runs every view and action headlessly.
    @MainActor
    public static func check(_ source: String) -> KilnCheck {
        check(KilnParsedSource(source))
    }

    /// Checks source already parsed (`Kiln.parse`).
    @MainActor
    public static func check(_ parsed: KilnParsedSource) -> KilnCheck {
        switch parsed.program {
        case .failure(let e):
            return KilnCheck(issues: [KilnIssue(severity: .error, kind: .syntax, line: e.line, column: e.col > 0 ? e.col : nil,
                                                message: e.message)])
        case .success(let program):
            return KilnCheck(issues: KChecker(program: program, source: parsed.source).run())
        }
    }
}
