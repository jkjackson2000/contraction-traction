import SwiftUI
import UIKit

/// Two phase colors and a warm neutral background. Defined in code so the
/// app and the widget extension share them without duplicate asset catalogs.
enum Theme {
    /// Warm coral: a contraction is being timed.
    static let contracting = Color(light: 0xD9533E, dark: 0xFF7A63)
    /// Calm teal: resting between contractions.
    static let resting = Color(light: 0x1C8077, dark: 0x4FC7B8)
    /// Fill behind white labels; stays dark enough for contrast in both modes.
    static let contractingFill = Color(light: 0xD9533E, dark: 0xE0573F)
    static let restingFill = Color(light: 0x1C8077, dark: 0x1F8F84)

    static let background = Color(light: 0xFAF6F1, dark: 0x0F0E0D)
    static let card = Color(light: 0xFFFFFF, dark: 0x1D1B19)

    static func color(contracting: Bool) -> Color { contracting ? Self.contracting : resting }
    static func fill(contracting: Bool) -> Color { contracting ? contractingFill : restingFill }
}

extension Color {
    init(light: UInt32, dark: UInt32) {
        self.init(uiColor: UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: 1)
    }
}
