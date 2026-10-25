import Foundation

/// The battery box, as battery.sh drew it (neutonfoo/dotfiles's): five levels, each with its own Macchiato color, and a
/// bolt while on power.
public enum BatteryStyle: Equatable, Sendable {
    case full, threeQuarters, half, quarter, empty, charging

    public init(percent: Int, onPower: Bool) {
        if onPower {
            self = .charging
        } else if percent >= 80 {
            self = .full
        } else if percent >= 70 {
            self = .threeQuarters
        } else if percent >= 40 {
            self = .half
        } else if percent >= 10 {
            self = .quarter
        } else {
            self = .empty
        }
    }

    /// The Font Awesome glyph of icons.sh (BAT_FULL ... BAT_CHARGING).
    public var glyph: String {
        switch self {
        case .full: "\u{F240}"
        case .threeQuarters: "\u{F241}"
        case .half: "\u{F242}"
        case .quarter: "\u{F243}"
        case .empty: "\u{F244}"
        case .charging: "\u{F0E7}"
        }
    }

    /// Its color, as a Catppuccin Macchiato hex.
    public var color: UInt32 {
        switch self {
        case .full: 0xa6da95  // green
        case .threeQuarters, .charging: 0xeed49f  // yellow
        case .half: 0xf5a97f  // peach
        case .quarter: 0xee99a0  // maroon
        case .empty: 0xed8796  // red
        }
    }
}

/// The date and the time boxes: "25-10-2026" and "15:06", in the Mac's own time zone.
public enum ClockText {
    public static func time(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, "HH:mm", timeZone)
    }

    public static func date(_ date: Date, timeZone: TimeZone = .current) -> String {
        format(date, "dd-MM-yyyy", timeZone)
    }

    /// When the minute shown changes next: the boxes are redrawn then, not on a tick.
    public static func nextMinute(after date: Date) -> Date {
        let seconds = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: (seconds / 60).rounded(.down) * 60 + 60)
    }

    private static func format(_ date: Date, _ pattern: String, _ timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}

/// The moon box (moon.sh): the days since a known new moon (2000-01-06 18:14 UTC), modulo one synodic month, give one of
/// eight phases.
public enum MoonPhase {
    static let knownNewMoon = Date(timeIntervalSince1970: 947_182_440)
    static let synodicMonth = 29.530588853  // days

    /// 0 new, 2 first quarter, 4 full, 6 last quarter.
    public static func index(at date: Date) -> Int {
        let days = date.timeIntervalSince(knownNewMoon) / 86_400
        let age = days.truncatingRemainder(dividingBy: synodicMonth)
        let positive = age < 0 ? age + synodicMonth : age
        return Int((positive / synodicMonth * 8).rounded()) % 8
    }

    /// The weather-icons glyphs of icons.sh's MOON_PHASES, drawn in the light ink (the lit side shows, the dark side is
    /// the box). Copied as they are, for parity: icons.sh has the same glyph at 5 and 7.
    public static let glyphs = [
        "\u{E38D}", "\u{E3D8}", "\u{E3DC}", "\u{E3DF}", "\u{E39B}", "\u{E3D1}", "\u{E3CE}", "\u{E3D1}",
    ]
}
