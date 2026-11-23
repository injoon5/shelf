import SwiftUI

/// Sizes for the connect screen and Settings.
enum SettingsMetrics {
    static let glyphSize: CGFloat = 96
    static let formSpacing: CGFloat = 12
    static let formWidth: CGFloat = 340
    static let formPadding: CGFloat = 24
    static let fieldHeight: CGFloat = 50
    static let buttonHeight: CGFloat = 36
    static let fieldInset: CGFloat = 18
    static let fieldRadius: CGFloat = 25
    static let glyphGap: CGFloat = 36

    // Icon Appearance's row of icons: the dock's four, at a size that fits
    // four across a form row on the narrowest iPhone (Shelf's own choice;
    // Springboard shows its Customize panel over the Home Screen instead).
    static let appearanceIconCount = 4
    static let appearanceIconSize: CGFloat = 54
    static let appearanceIconGap: CGFloat = 22
    static let appearanceSpacing: CGFloat = 14
    static let appearancePadding: CGFloat = 6
}
