import CoreGraphics
import Foundation

/// What the clicks on the Control Center button ask of the panel.
public enum PanelIntent: Sendable, Equatable {
    case open
    case closed
}

/// What the clicks asked for, with a serial that changes on every click, so the driver acts once per change even when two
/// clicks ask for the same thing (controlcenter.sh's cc_intent file).
public struct ControlCenterIntent: Sendable, Equatable {
    public private(set) var want: PanelIntent = .closed
    public private(set) var serial = 0

    public init() {}

    public mutating func set(_ want: PanelIntent) {
        self.want = want
        serial += 1
    }
}

/// Whether the Control Center panel was open when the button was pressed. macOS closes the panel with the very press that
/// lands on the button, and the window is still fading out when the click arrives: without this, the click would see an
/// open panel and press fn+C again, opening it under the pointer that just closed it.
public struct PanelPress: Sendable, Equatable {
    /// A press older than this belongs to some earlier click.
    public static let maxAge: TimeInterval = 2

    public let open: Bool
    public let at: Date

    public init(open: Bool, at: Date) {
        self.open = open
        self.at = at
    }

    /// Whether the press that started this click closed the panel; the press counts once.
    public static func take(_ press: inout PanelPress?, now: Date) -> Bool {
        guard let taken = press else { return false }
        press = nil
        return taken.open && now.timeIntervalSince(taken.at) < maxAge
    }
}

/// What a click on the button does. One driver at a time presses the keys: fast clicks used to start one script each, every
/// one pressing fn+C on its own, and the panel ended empty or in the wrong state.
public enum ControlCenterClick {
    public enum Decision: Sendable, Equatable {
        /// A driver runs: the click only changes what is wanted.
        case want(PanelIntent)
        /// The press already closed the panel.
        case nothing
        /// The panel was opened some other way (fn+C): one key closes it.
        case pressOnce
        /// Start a driver that opens the panel.
        case drive
    }

    public static func decide(driving: Bool, pressClosedPanel: Bool, wanted: PanelIntent, visible: Bool) -> Decision {
        if driving { return .want(pressClosedPanel || wanted == .open ? .closed : .open) }
        if pressClosedPanel { return .nothing }
        return visible ? .pressOnce : .drive
    }
}

/// Makes the panel match the intent with as few fn+C as possible, and never while Control Center is changing: a key that
/// landed mid-animation, or among fast clicks, left an empty panel window on screen that no key or click would close. A key
/// goes out once the clicks have stopped for `quietPolls` and the panel has looked the same for `steadyPolls`, and gets
/// `keyWaitPolls` to take effect (`maxKeys` per change). Once open and settled the panel is the user's and the driver lets
/// go: a click inside it can redraw its window, and a driver still watching took the blink for a close elsewhere. Closed,
/// it lets go once the pointer has been away from the top for `gracePolls` (the native bar needs a moment to slide away).
/// The caller polls it every `poll` seconds, only while a click is being handled, and at most `maxPolls` times.
public struct ControlCenterDriver: Sendable {
    public struct Timing: Sendable {
        public var poll: TimeInterval = 0.1
        /// The first key waits only for the clicks: the panel starts closed and still. Sent at once, the clicks after it
        /// landed on a panel still opening (a click on the bar closes it) and left it empty.
        public var firstWait: TimeInterval = 0.35
        public var quietPolls = 3
        public var steadyPolls = 4
        public var keyWaitPolls = 8
        public var maxKeys = 2
        public var gracePolls = 6
        public var maxPolls = 1200

        public init() {}
    }

    public enum Step: Sendable, Equatable {
        case wait
        case pressKey
        /// The panel was closed by a click elsewhere, or does not open: the caller sets the intent to closed and steps again
        /// in the same poll.
        case wantClosed
        case finish
    }

    private let timing: Timing
    private var polls = 0
    private var away = 0
    private var since: Int
    private var changedAt: Int
    private var pressedAt: Int
    private var keys = 0
    private var seen = false
    private var was = false
    private var handled: Int

    public init(handled: Int, timing: Timing = Timing()) {
        self.timing = timing
        self.handled = handled
        since = -timing.quietPolls
        changedAt = -timing.steadyPolls
        pressedAt = -timing.keyWaitPolls
    }

    public mutating func step(want: PanelIntent, serial: Int, visible: Bool, pointerAtTop: Bool) -> Step {
        guard polls < timing.maxPolls else { return .finish }
        if visible != was {
            was = visible
            changedAt = polls
        }
        if serial != handled {
            handled = serial
            since = polls
            keys = 0
            seen = false
        }
        if want == .open && visible { seen = true }
        let quiet = polls - since >= timing.quietPolls
        let steady = polls - changedAt >= timing.steadyPolls
        if seen && quiet && steady { return .finish }
        var result = Step.wait
        if (want == .open) != visible {
            if want == .open && (seen || keys >= timing.maxKeys) { return .wantClosed }
            if quiet && steady && polls - pressedAt >= timing.keyWaitPolls && keys < timing.maxKeys {
                pressedAt = polls
                keys += 1
                result = .pressKey
            }
        }
        if want == .closed && !visible && !pointerAtTop {
            away += 1
            if away >= timing.gracePolls { return .finish }
        } else {
            away = 0
        }
        polls += 1
        return result
    }
}

/// Which on-screen windows are an open panel, menu or popover: above the normal level and taller than the menu bar (the
/// app's own menu bar item is a short window on a raised level too).
public enum PopupWindows {
    public static let minHeight: CGFloat = 100

    public struct Window: Sendable, Equatable {
        public let pid: Int32
        public let layer: Int
        public let height: CGFloat

        public init(pid: Int32, layer: Int, height: CGFloat) {
            self.pid = pid
            self.layer = layer
            self.height = height
        }
    }

    public static func isOpen(_ windows: [Window], owners: Set<Int32>) -> Bool {
        windows.contains { owners.contains($0.pid) && $0.layer > 0 && $0.height > minHeight }
    }
}

/// The strip at the top of the Mac's own screen where the system menu bar reveals itself, in Core Graphics coordinates
/// (origin at the top left of the main display). A monitor above it sits at negative y, and counted as the strip while
/// the pointer was anywhere on that monitor.
public enum TopStrip {
    public static let height: CGFloat = 40

    public static func contains(_ point: CGPoint, mainDisplay: CGRect, height: CGFloat = TopStrip.height) -> Bool {
        point.y >= mainDisplay.minY && point.y < mainDisplay.minY + height && point.x >= mainDisplay.minX
            && point.x < mainDisplay.maxX
    }
}
