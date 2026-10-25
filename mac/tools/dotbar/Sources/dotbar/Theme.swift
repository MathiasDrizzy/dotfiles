import SwiftUI

/// The bar's look, taken from mac/config/sketchybar/colors.sh (Catppuccin Macchiato) so both bars match while they live
/// side by side.
enum Theme {
    static let base = Color(hex: 0x24273a)
    static let text = Color(hex: 0xcad3f5)
    static let mauve = Color(hex: 0xc6a0f6)
    static let blue = Color(hex: 0x8aadf4)
    static let surface1 = Color(hex: 0x494d64)
    static let overlay0 = Color(hex: 0x6e738d)
    static let surface0 = Color(hex: 0x363a4f)
    static let red = Color(hex: 0xed8796)
    static let yellow = Color(hex: 0xeed49f)
    static let pink = Color(hex: 0xf5bde6)
    /// A box at rest: solid, the color the boxes show on screen.
    static let barColor = Color(hex: 0x242639)

    static let pillHeight: CGFloat = 26
    static let pillRadius: CGFloat = 5
    static let pillGap: CGFloat = 5
    /// A workspace slot: 26 points (the icon width of the SketchyBar items).
    static let slot: CGFloat = 26
    /// The room a Nerd Font icon at ICON_SIZE takes.
    static let iconWidth: CGFloat = 17

    static let fontName = "JetBrainsMono Nerd Font"
    /// TEXT_SIZE and ICON_SIZE of icons.sh.
    static let textFont = Font.custom(fontName, size: 12).bold()
    static let iconFont = Font.custom(fontName, size: 15)
    /// The label font of the items by default (Medium), the clock's is the bold textFont.
    static let mediumFont = Font.custom("JetBrainsMono NF Medium", size: 12)
    /// sketchybar-app-font: app icons and ligatures like ":widget:".
    static let appIconFont = Font.custom("sketchybar-app-font", size: 15)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }
}
