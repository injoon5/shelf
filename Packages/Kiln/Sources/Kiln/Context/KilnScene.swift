//
//  KilnScene.swift
//  Kiln's run context: the app's scene phase and opening URLs
//

import SwiftUI
import Observation

/// Where the app's screen is (`@Environment(\.scenePhase)`), as the host
/// sets it on the run's context.
public enum KilnScenePhase: Int, Sendable, Comparable {
    case background, inactive, active

    public static func < (a: KilnScenePhase, b: KilnScenePhase) -> Bool { a.rawValue < b.rawValue }

    init(_ p: ScenePhase) {
        switch p {
        case .active: self = .active
        case .inactive: self = .inactive
        default: self = .background
        }
    }

    var name: String {
        switch self {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        }
    }
}

/// The host's phase, observed: a view that read it redraws when it changes.
@Observable @MainActor
final class KilnSceneState {
    var phase: KilnScenePhase = .active
}

/// What a run's root view gets from its context: the host's `openURL`.
struct KRunEnvironment: ViewModifier {
    let context: KilnContext

    func body(content: Content) -> some View {
        if let open = context.openURL {
            content.environment(\.openURL, OpenURLAction { url in open(url) ? .handled : .discarded })
        } else {
            content
        }
    }
}
