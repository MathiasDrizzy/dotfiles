import Foundation

/// The front app's name in its box of fixed width (app_name.sh): a name that fits sits centered; a longer one holds, slides
/// left until its end shows, holds again and slides back, once per app switch.
public enum NameSlide {
    /// How long the name rests before each way.
    public static let hold: TimeInterval = 1.2
    /// SketchyBar moved it 3 frames a point at 60 frames a second.
    public static let pointsPerSecond: Double = 20
    /// The slide goes this much further, or the last letter stayed half cut.
    public static let endMargin: Double = 6

    public enum Plan: Equatable, Sendable {
        case centered
        /// Moves the name `span` points left, in `seconds` each way.
        case slide(span: Double, seconds: Double)
    }

    /// One move of the name: `at` seconds after it was shown, go to `offset` (points from its resting place) in `seconds`.
    public struct Step: Equatable, Sendable {
        public let at: TimeInterval
        public let offset: Double
        public let seconds: TimeInterval

        public init(at: TimeInterval, offset: Double, seconds: TimeInterval) {
            self.at = at
            self.offset = offset
            self.seconds = seconds
        }
    }

    /// SketchyBar measured the name in whole points and compared it with the whole box (paddings included).
    public static func plan(textWidth: Double, boxWidth: Double) -> Plan {
        let overflow = textWidth.rounded(.down) - boxWidth
        guard overflow > 0 else { return .centered }
        let span = overflow + endMargin
        return .slide(span: span, seconds: span / pointsPerSecond)
    }

    public static func steps(span: Double, seconds: TimeInterval) -> [Step] {
        [Step(at: hold, offset: -span, seconds: seconds), Step(at: hold + seconds + hold, offset: 0, seconds: seconds)]
    }

    /// SketchyBar's `sin` animation curve: fast at first, slowing down at the end.
    public static func ease(_ progress: Double) -> Double {
        sin(min(max(progress, 0), 1) * .pi / 2)
    }
}

/// The front app's menus, shown in a popup since the native menu bar stays hidden (appmenu.sh): the menu bar's titles, then
/// one menu's items.
public enum AppMenus {
    /// A menu lists this many items at most: the popup must fit under the bar.
    public static let maxItems = 30

    /// The menu bar's titles in order, without the Apple menu (the bar has its own) and items with no title.
    public static func top(_ titles: [String?]) -> [String] {
        titles.compactMap { $0 }.filter { !$0.isEmpty && $0 != "Apple" }
    }

    /// A menu's item titles in order, without its separators (no title; System Events called them "missing value").
    public static func items(_ titles: [String?]) -> [String] {
        Array(titles.compactMap { $0 }.filter { !$0.isEmpty && $0 != "missing value" }.prefix(maxItems))
    }
}
