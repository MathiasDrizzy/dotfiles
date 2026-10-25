import CoreGraphics

/// Where the Vorssaint box goes (vorssaint.sh align). macOS opens Vorssaint's popover under its menu bar extra, wherever the
/// hidden menu bar has it, so the boxes right of Vorssaint's (battery, date, time) widen evenly from their least widths
/// until the box's center sits over the extra's: the boxes grow a little instead of leaving a gap. An extra right of where
/// the box naturally goes leaves them at their least widths.
public enum VorssaintAlign {
    public static let boxWidth: CGFloat = 28
    /// The boxes that widen: battery, date, time.
    public static let spreadCount = 3
    /// An extra far to the left (many other extras) would push the boxes into the track; past this the box stays left of
    /// it instead.
    public static let maxSpread: CGFloat = 120

    /// The total width the boxes right of Vorssaint's take above their least widths. `boxLeft` is the box's left edge now,
    /// with `currentSpread` already added; the extra's frame is in screen points, origin top-left, as Accessibility gives it.
    public static func spread(extra: CGRect, boxLeft: CGFloat, currentSpread: CGFloat) -> CGFloat {
        let wanted = (extra.minX + (extra.width / 2).rounded(.down) - boxWidth / 2).rounded(.down)
        let total = currentSpread + boxLeft.rounded(.down) - wanted
        return min(maxSpread, max(0, total))
    }

    /// The spread shared by the boxes, left to right; the first (the battery) takes what does not divide.
    public static func shares(_ total: CGFloat) -> [CGFloat] {
        let whole = Int(total)
        let share = whole / spreadCount
        return (0..<spreadCount).map { CGFloat(share + ($0 == 0 ? whole % spreadCount : 0)) }
    }
}

/// Makes Vorssaint's popover match the clicks on its box (vorssaint.sh). One driver at a time: a click while it runs only
/// flips what is wanted. Pressing the extra once per click toggled a popover still opening or closing, and fast clicks
/// ended in the wrong state. The caller polls it every `pollSeconds` (the first poll after `firstWaitSeconds`, so the
/// clicks of a burst land before anything is sent) with whether the popover is on screen, and does what it answers.
///
/// A press goes out once the clicks have stopped for `quietPolls` and the popover has looked the same for `steadyPolls`,
/// and gets `keyWaitPolls` to show (`maxKeys` per change). Closing is a click outside the popover, never a press nor
/// Escape: a popover closed either way left Vorssaint so that the next one shut at a click inside it (a tab switch). A
/// popover that does not close is taken as open; one that does not open, or closed elsewhere, as closed.
public struct VorssaintDriver: Sendable {
    public enum Intent: Sendable { case open, closed }
    public enum Action: Equatable, Sendable {
        case none
        /// Press the extra (opens the popover).
        case press
        /// Click outside the popover (closes it).
        case dismiss
        /// Done: the popover is the user's now, or the driver gave up.
        case finish
    }

    public static let pollSeconds = 0.1
    public static let firstWaitSeconds = 0.35
    public static let maxPolls = 1200 // two minutes
    static let quietPolls = 3
    static let steadyPolls = 3
    static let keyWaitPolls = 5
    static let maxKeys = 2
    static let gracePolls = 3

    public private(set) var intent: Intent
    private var serial = 0
    private var handled = 0
    private var polls = 0
    private var since = -quietPolls
    private var changedAt = -steadyPolls
    private var pressedAt = -keyWaitPolls
    private var keys = 0
    private var seen = false
    private var was: Bool
    private var away = 0

    /// `visible`: the popover is on screen now; `sawMenuAtPress`: it was at the press (macOS starts closing a popover on a
    /// click outside it, the one on the box included, before the box hears of it).
    public init(visible: Bool, sawMenuAtPress: Bool) {
        intent = visible || sawMenuAtPress ? .closed : .open
        was = visible
    }

    /// Another click on the box while the driver runs.
    public mutating func click() {
        intent = intent == .open ? .closed : .open
        serial += 1
    }

    public mutating func poll(visible: Bool) -> Action {
        guard polls < Self.maxPolls else { return .finish }
        if visible != was {
            was = visible
            changedAt = polls
        }
        while true {
            if serial != handled {
                handled = serial
                since = polls
                keys = 0
                seen = false
            }
            if intent == .open && visible { seen = true }
            // Open and settled: the popover is the user's now. A click inside it can redraw its window, and a driver still
            // watching took the blink for a close elsewhere and shut it under the pointer.
            if seen && quiet && steady { return .finish }
            var action = Action.none
            if (intent == .open) != visible {
                if intent == .open && (seen || keys >= Self.maxKeys) {
                    click() // closed by a click elsewhere, or it does not open
                    continue
                }
                if intent == .closed && keys >= Self.maxKeys && polls - pressedAt >= Self.keyWaitPolls {
                    click() // it stayed open
                    continue
                }
                if quiet && steady && polls - pressedAt >= Self.keyWaitPolls && keys < Self.maxKeys {
                    action = intent == .closed ? .dismiss : .press
                    pressedAt = polls
                    keys += 1
                }
            }
            if intent == .closed && !visible {
                away += 1
                if away >= Self.gracePolls { return .finish }
            } else {
                away = 0
            }
            polls += 1
            return action
        }
    }

    private var quiet: Bool { polls - since >= Self.quietPolls }
    private var steady: Bool { polls - changedAt >= Self.steadyPolls }
}
