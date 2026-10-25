import Foundation

/// Swapping the windows of two workspaces (swap_workspaces in aerospace.sh). Windows move only while both workspaces are
/// hidden: with the focus on one of them it parks on an empty scratch workspace first, so nothing on screen is re-tiled
/// one window at a time; afterwards the focus follows the content that was on screen.
public enum WorkspaceSwap {
    /// The empty workspace that holds the focus during a swap.
    public static let park = "swap-park"

    public struct Plan: Equatable, Sendable {
        /// The aerospace commands, in order.
        public let commands: [[String]]
        /// Where the focus ends; nil when the swap leaves it alone.
        public let focus: String?

        public init(commands: [[String]], focus: String?) {
            self.commands = commands
            self.focus = focus
        }
    }

    public enum Outcome: Equatable, Sendable {
        /// The windows were swapped; the focus ended on `focus` (nil: where it was).
        case swapped(focus: String?)
        /// A workspace dropped on itself: nothing to do.
        case nothing
        /// The windows of a workspace could not be read (no answer in time): nothing moved.
        case unread
        /// A command failed or timed out partway: it stopped there and left the parking workspace; the bar reads the
        /// workspaces again instead of painting a swap that did not happen.
        case failed
    }

    public static func plan(from: String, to: String, focused: String, fromWindows: [String], toWindows: [String]) -> Plan {
        guard from != to else { return Plan(commands: [], focus: nil) }
        var commands: [[String]] = []
        let onScreen = focused == from || focused == to
        if onScreen { commands.append(["workspace", park]) }
        commands += fromWindows.map { ["move-node-to-workspace", "--window-id", $0, to] }
        commands += toWindows.map { ["move-node-to-workspace", "--window-id", $0, from] }
        // The content that was on screen now lives in the other workspace: the focus goes with it.
        let focus = onScreen ? (focused == from ? to : from) : nil
        if let focus { commands.append(["workspace", focus]) }
        return Plan(commands: commands, focus: focus)
    }

    /// Parses `aerospace list-windows --workspace X --format %{window-id}`.
    public static func parseWindowIDs(_ text: String) -> [String] {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Reads the focus and both workspaces' windows, then runs the plan one command at a time, each ended past `timeout`.
    public static func run(runner: CommandRunner, aerospace: String, from: String, to: String, timeout: TimeInterval)
        async -> Outcome
    {
        guard from != to else { return .nothing }
        let format = ["--format", "%{window-id}"]
        async let focusedAnswer = runner.run(aerospace, ["list-workspaces", "--focused"], timeout: timeout)
        async let fromAnswer = runner.run(aerospace, ["list-windows", "--workspace", from] + format, timeout: timeout)
        async let toAnswer = runner.run(aerospace, ["list-windows", "--workspace", to] + format, timeout: timeout)
        let (focused, fromWindows, toWindows) = await (focusedAnswer, fromAnswer, toAnswer)
        guard fromWindows.status == 0, toWindows.status == 0 else { return .unread }
        // No answer about the focus: the windows still swap, only without parking it.
        let focus = focused.status == 0 ? focused.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : ""
        let plan = plan(
            from: from, to: to, focused: focus, fromWindows: parseWindowIDs(fromWindows.stdout),
            toWindows: parseWindowIDs(toWindows.stdout))
        for command in plan.commands {
            let answer = await runner.run(aerospace, command, timeout: timeout)
            guard answer.status == 0 else {
                // Moving more windows blind would only make it worse: stop, and do not leave the focus parked.
                if !focus.isEmpty, command != ["workspace", focus] {
                    _ = await runner.run(aerospace, ["workspace", focus], timeout: timeout)
                }
                return .failed
            }
        }
        return .swapped(focus: plan.focus)
    }
}

/// The bar skips its refreshes while a swap runs (they would paint the windows half moved and the focus parked) and
/// repaints once at the end.
public struct SwapGate: Sendable {
    public private(set) var swapping = false
    /// Refreshes asked for and skipped during this swap.
    public private(set) var skipped = 0

    public init() {}

    public mutating func begin() {
        swapping = true
        skipped = 0
    }

    /// Whether a refresh may run now; during a swap it is skipped (and counted).
    public mutating func allowRefresh() -> Bool {
        if swapping { skipped += 1 }
        return !swapping
    }

    /// The swap is over. Returns whether to repaint (once, whatever was skipped).
    public mutating func end() -> Bool {
        defer {
            swapping = false
            skipped = 0
        }
        return swapping
    }
}
