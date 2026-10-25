/// The Apple menu's entries, as sketchybarrc's apple_entry lines made them: glyph (JetBrains Mono Nerd Font, Material
/// Design), label, icon color (Catppuccin Macchiato) and what a click does.
public enum AppleMenu {
    public enum Action: Equatable, Sendable {
        case about, settings, sleep, lock, logout, restart, shutdown
    }

    public struct Entry: Equatable, Sendable {
        public let action: Action
        public let glyph: String
        public let label: String
        public let color: UInt32
    }

    public static let entries: [Entry] = [
        Entry(action: .about, glyph: "\u{F02FD}", label: "Acerca de este Mac", color: 0x8aadf4),  // md-information_outline, blue
        Entry(action: .settings, glyph: "\u{F08BB}", label: "Ajustes del Sistema", color: 0x8bd5ca),  // md-cog_outline, teal
        Entry(action: .sleep, glyph: "\u{F0594}", label: "Suspender", color: 0xc6a0f6),  // md-weather_night, mauve
        Entry(action: .lock, glyph: "\u{F0341}", label: "Bloquear pantalla", color: 0xeed49f),  // md-lock_outline, yellow
        Entry(action: .logout, glyph: "\u{F0343}", label: "Cerrar sesión", color: 0xf5a97f),  // md-logout, peach
        Entry(action: .restart, glyph: "\u{F0709}", label: "Reiniciar", color: 0xa6da95),  // md-restart, green
        Entry(action: .shutdown, glyph: "\u{F0425}", label: "Apagar", color: 0xed8796),  // md-power, red
    ]
}
