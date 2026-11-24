//
//  KilnErrorScreen.swift
//  Kiln's run context: who draws an error in place of a view
//
//  When part of an app's view fails while it runs (its `body`, a row's
//  content, a custom style's `makeBody`), Kiln draws an error in its place.
//  The host draws it, if it provides a screen for the run:
//
//      context.provide(KilnErrorScreen { error in
//          MyErrorScreen(line: error.line, message: error.message)
//      })
//
//  The view is given the error, with its line, wherever Kiln would have
//  drawn its own. A host that would rather show one screen for the whole
//  app (Shelf does) can draw nothing in place and take over from the view's
//  `onAppear`: every error Kiln draws reaches the host this way, whichever
//  phase `onError` reported it in.
//
//  Without a screen (Kiln Lab, tests), Kiln draws its own: a red label with
//  the line and the message.
//

import SwiftUI

@MainActor
public final class KilnErrorScreen {
    let content: @MainActor (KilnError) -> AnyView

    public init<Content: View>(@ViewBuilder content: @escaping @MainActor (KilnError) -> Content) {
        self.content = { AnyView(content($0)) }
    }
}

/// Shown in place of a part of the view that failed to evaluate: the host's
/// screen for the run, or Kiln's red label.
struct KErrorView: View {
    let message: String
    @SwiftUI.Environment(\.kilnRunContext) private var context

    var body: some View {
        if let screen = context?.provided(KilnErrorScreen.self) {
            screen.content(KilnError(phase: .body, reported: message))
        } else {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.red)
                .padding(8)
                .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

private struct KRunContextKey: EnvironmentKey {
    static let defaultValue: KilnContext? = nil
}

extension EnvironmentValues {
    /// The run whose views these are (`KRunEnvironment` sets it at the root).
    var kilnRunContext: KilnContext? {
        get { self[KRunContextKey.self] }
        set { self[KRunContextKey.self] = newValue }
    }
}
