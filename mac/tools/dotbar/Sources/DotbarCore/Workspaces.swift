import Foundation

/// One AeroSpace workspace as `list-workspaces --all` reports it.
public struct WorkspaceRow: Equatable, Sendable {
    public let id: String
    /// The AppKit screen id of its monitor (1 is the Mac's own screen).
    public let monitor: Int
    public let visible: Bool
    public let focused: Bool

    public init(id: String, monitor: Int, visible: Bool, focused: Bool) {
        self.id = id
        self.monitor = monitor
        self.visible = visible
        self.focused = focused
    }
}

/// How a pill is drawn: the focused workspace is a solid block, the one another monitor shows without the focus a lighter
/// box, the rest plain.
public enum PillState: Equatable, Sendable {
    case focused, visible, plain
}

public struct Pill: Equatable, Sendable {
    public let id: String
    /// The text drawn: the external monitor's workspaces are named eN in AeroSpace and drawn as N.
    public let label: String
    public let state: PillState
}

/// The two groups of pills: the Mac's screen and any other monitor, and how many each hid for lack of room ("+N").
public struct WorkspaceBar: Equatable, Sendable {
    public var mac: [Pill] = []
    public var external: [Pill] = []
    public var hiddenMac = 0
    public var hiddenExternal = 0

    public init() {}
}

public enum Workspaces {
    public static let mainScreen = 1

    /// Parses `aerospace list-workspaces --all --format
    /// '%{workspace}|%{monitor-appkit-nsscreen-screens-id}|%{workspace-is-visible}|%{workspace-is-focused}'`.
    public static func parseRows(_ text: String) -> [WorkspaceRow] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            guard fields.count == 4, !fields[0].isEmpty, let monitor = Int(fields[1]) else { return nil }
            return WorkspaceRow(id: fields[0], monitor: monitor, visible: fields[2] == "true", focused: fields[3] == "true")
        }
    }

    /// Parses `aerospace list-windows --all --format %{workspace}`: the workspaces that hold a window.
    public static func parseOccupied(_ text: String) -> Set<String> {
        Set(text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
    }

    /// The pills, as the SketchyBar plugin drew them (aerospace.sh). A workspace shows when it is focused, visible on its
    /// monitor (even empty) or holds windows. Once the external monitor is unplugged, AeroSpace keeps its workspaces (eN)
    /// on the Mac: they leave the bar with it, unless one has the focus. Over `cap`, the last workspace that is neither
    /// focused nor visible leaves, from the group with more of them (the Mac's on a tie).
    public static func layout(rows: [WorkspaceRow], occupied: Set<String>, cap: Int? = nil) -> WorkspaceBar {
        let focusedID = rows.first(where: \.focused)?.id
        let externalPresent = rows.contains { $0.monitor != mainScreen }
        var mac: [(row: WorkspaceRow, must: Bool)] = []
        var external: [(row: WorkspaceRow, must: Bool)] = []
        for row in rows {
            let must = row.focused || row.visible
            guard must || occupied.contains(row.id) else { continue }
            if !externalPresent && row.id != focusedID && row.id.hasPrefix("e") && row.id.dropFirst().allSatisfy(\.isNumber) {
                continue
            }
            if row.monitor == mainScreen { mac.append((row, must)) } else { external.append((row, must)) }
        }

        var bar = WorkspaceBar()
        if let cap {
            func lastOptional(_ group: [(row: WorkspaceRow, must: Bool)]) -> Int? { group.lastIndex { !$0.must } }
            while mac.count + external.count > cap {
                let macOptional = mac.filter { !$0.must }.count
                let externalOptional = external.filter { !$0.must }.count
                if let index = lastOptional(mac), macOptional >= externalOptional || lastOptional(external) == nil {
                    mac.remove(at: index)
                    bar.hiddenMac += 1
                } else if let index = lastOptional(external) {
                    external.remove(at: index)
                    bar.hiddenExternal += 1
                } else {
                    break
                }
            }
        }
        func pill(_ row: WorkspaceRow) -> Pill {
            let label = row.id.hasPrefix("e") && row.id.count > 1 ? String(row.id.dropFirst()) : row.id
            let state: PillState = row.focused ? .focused : (row.visible ? .visible : .plain)
            return Pill(id: row.id, label: label, state: state)
        }
        bar.mac = mac.map { pill($0.row) }
        bar.external = external.map { pill($0.row) }
        return bar
    }
}

/// One line of `aerospace subscribe`: the events that change what the pills show.
public enum AeroSpaceEvent: Equatable, Sendable {
    case focusedWorkspace(String)
    case focusChanged
    case monitorChanged
    case other

    public static func parse(_ line: String) -> AeroSpaceEvent? {
        guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let event = object["_event"] as? String
        else { return nil }
        switch event {
        case "focused-workspace-changed": return .focusedWorkspace(object["workspace"] as? String ?? "")
        case "focus-changed": return .focusChanged
        case "focused-monitor-changed": return .monitorChanged
        default: return .other
        }
    }
}
