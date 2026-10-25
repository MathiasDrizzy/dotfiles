import Foundation

/// Keeps the focus on a workspace whose last window just closed (stay.sh). macOS hands the focus to another app when a
/// window closes, and AeroSpace follows that app to its own workspace (AeroSpace issue 325); the user meant to stay where
/// they were. A switch the user asked for (a key binding, a click on the bar, a drag swap) is left alone.
public struct StayRule: Sendable {
    /// The workspace a drag swap parks the focus on.
    public static let park = "swap-park"
    /// macOS hands the focus over within this long after the last window closes.
    public static let emptiedSeconds: TimeInterval = 3
    /// A switch this soon after a key binding or a click was asked for.
    public static let askedSeconds: TimeInterval = 1

    private var bindingAt: Date = .distantPast
    private var askedAt: Date = .distantPast
    private var emptied: String?
    private var emptiedAt: Date = .distantPast
    /// Workspaces whose last focus event had no window: a click on their bare desktop is not a window closing.
    private var emptySeen: Set<String> = []
    /// A drag swap is moving windows: nothing it does is a window closing.
    public var swapping = false

    public init() {}

    /// The bar asked for a switch (a click on a pill).
    public mutating func asked(at now: Date) { askedAt = now }

    private func userAsked(at now: Date) -> Bool {
        swapping || now.timeIntervalSince(bindingAt) <= Self.askedSeconds
            || now.timeIntervalSince(askedAt) <= Self.askedSeconds
    }

    /// What to do after an event: nothing, or go back to a workspace once it is confirmed to hold no window.
    public enum Action: Equatable, Sendable {
        case none
        case returnIfEmpty(String)
    }

    public mutating func handle(_ event: StayEvent, at now: Date) -> Action {
        switch event {
        case .binding:
            bindingAt = now
        case .focus(let workspace, let hasWindow):
            if hasWindow {
                emptySeen.remove(workspace)
            } else if !emptySeen.contains(workspace) {
                if !userAsked(at: now) {
                    emptied = workspace
                    emptiedAt = now
                }
                emptySeen.insert(workspace)
            }
        case .workspace(let previous):
            if previous == emptied, previous != Self.park, now.timeIntervalSince(emptiedAt) <= Self.emptiedSeconds,
                !userAsked(at: now)
            {
                emptied = nil
                return .returnIfEmpty(previous)
            }
        }
        return .none
    }
}

/// The `aerospace subscribe` events stay.sh read.
public enum StayEvent: Equatable, Sendable {
    case binding
    case focus(workspace: String, hasWindow: Bool)
    case workspace(previous: String)

    public static func parse(_ line: String) -> StayEvent? {
        guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = object["_event"] as? String
        else { return nil }
        switch event {
        case "binding-triggered":
            return .binding
        case "focus-changed":
            guard let workspace = object["workspace"] as? String else { return nil }
            return .focus(workspace: workspace, hasWindow: object["windowId"] != nil)
        case "focused-workspace-changed":
            guard let previous = object["prevWorkspace"] as? String else { return nil }
            return .workspace(previous: previous)
        default:
            return nil
        }
    }
}
