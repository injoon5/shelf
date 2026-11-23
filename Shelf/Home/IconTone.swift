import SwiftUI
import UIKit

/// Whether icons are drawn light or dark. It is its own trait, apart from
/// the system's light and dark, so every icon (the grid, the dock, the card's
/// face, the previews in sheets) reads one value, and Icon Appearance (PLAN.md
/// §0.5) can hold icons light or dark whatever the system does.
enum IconTone: Int, Sendable {
    case light, dark

    init(_ style: UIUserInterfaceStyle) {
        self = style == .dark ? .dark : .light
    }

    var colorScheme: ColorScheme { self == .dark ? .dark : .light }
}

/// The icon tone set on a window or a view. Unset, icons follow the
/// system's light and dark where they are.
struct IconToneTrait: UITraitDefinition {
    static let defaultValue: IconTone? = nil
    static let name = "IconTone"
    static let identifier = "dev.ij5.shelf.iconTone"
}

extension UITraitCollection {
    /// The tone icons here are drawn in.
    var iconTone: IconTone {
        self[IconToneTrait.self] ?? IconTone(userInterfaceStyle)
    }
}

extension UIMutableTraits {
    /// Set only: reading an override that was never set throws, so read
    /// `UITraitCollection.iconTone` instead.
    var iconTone: IconTone? {
        @available(*, unavailable) get { fatalError() }
        set { self[IconToneTrait.self] = newValue }
    }
}

/// The same value in SwiftUI, so a sheet's embedded icon (`IconImage`) and
/// anything around it agree.
private struct IconToneKey: EnvironmentKey {
    static let defaultValue: IconTone? = nil
}

extension IconToneKey: UITraitBridgedEnvironmentKey {
    static func read(from traitCollection: UITraitCollection) -> IconTone? {
        traitCollection[IconToneTrait.self]
    }

    static func write(to mutableTraits: inout any UIMutableTraits, value: IconTone?) {
        mutableTraits[IconToneTrait.self] = value
    }
}

extension EnvironmentValues {
    var iconTone: IconTone? {
        get { self[IconToneKey.self] }
        set { self[IconToneKey.self] = newValue }
    }
}
