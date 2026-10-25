import Foundation

/// A workspace slot's horizontal span on the bar, in the pill's own coordinates.
public struct DragSlot: Equatable, Sendable {
    public let id: String
    public let left: Double
    public let right: Double

    public init(id: String, left: Double, right: Double) {
        self.id = id
        self.left = left
        self.right = right
    }
}

/// Dragging a workspace onto another, as drag.sh followed it: a press on a pill arms it, the pointer moving 4 points
/// starts it (less is a click), a ghost pill centered on the pointer follows it from then on, and the slot under the
/// pointer (never the source itself) is the drop target. On release the ghost lands on the target, or glides back to the
/// source when there is none.
public struct WorkspaceDrag: Sendable {
    public static let threshold: Double = 4
    /// The gap between two slots belongs to both.
    public static let slotMargin: Double = 1
    /// Half a slot: the ghost is centered on the pointer.
    public static let ghostHalfWidth: Double = 13

    public enum Phase: Equatable, Sendable {
        case idle, armed, dragging
    }

    /// What a release means.
    public enum Release: Equatable, Sendable {
        /// Nothing was pressed on a pill.
        case none
        /// The pointer never went 4 points: switch to that workspace.
        case click(String)
        /// Swap the windows of `from` and `to`; the ghost lands at `landing`.
        case swap(from: String, to: String, landing: Double)
        /// No target: the ghost glides back to `back`.
        case cancel(back: Double)
    }

    public private(set) var phase = Phase.idle
    public private(set) var source: DragSlot?
    public private(set) var target: DragSlot?
    /// Where the ghost's left edge is while dragging.
    public private(set) var ghostLeft: Double?
    private var downX: Double = 0

    public init() {}

    /// The slot under `x`, or nil.
    public static func slot(at x: Double, in slots: [DragSlot]) -> DragSlot? {
        slots.first { x >= $0.left - slotMargin && x < $0.right + slotMargin }
    }

    private var slots: [DragSlot] = []

    public mutating func press(at x: Double, slots: [DragSlot]) {
        self.slots = slots
        target = nil
        ghostLeft = nil
        downX = x
        source = Self.slot(at: x, in: slots)
        phase = source == nil ? .idle : .armed
    }

    /// The pointer is at `x`. Returns true when this move started the drag.
    @discardableResult
    public mutating func move(to x: Double) -> Bool {
        var started = false
        if phase == .armed, abs(x - downX) >= Self.threshold {
            phase = .dragging
            started = true
        }
        guard phase == .dragging else { return false }
        let hit = Self.slot(at: x, in: slots)
        target = hit?.id == source?.id ? nil : hit
        ghostLeft = x - Self.ghostHalfWidth
        return started
    }

    public mutating func release() -> Release {
        defer {
            phase = .idle
            target = nil
            ghostLeft = nil
            source = nil
        }
        guard let source else { return .none }
        switch phase {
        case .idle: return .none
        case .armed: return .click(source.id)
        case .dragging:
            if let target { return .swap(from: source.id, to: target.id, landing: target.left) }
            return .cancel(back: source.left)
        }
    }
}
