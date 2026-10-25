import DotbarCore
import Foundation
import Observation
import SwiftUI

extension Theme {
    /// TINT_FRAMES and GLIDE_FRAMES of drag.sh: SketchyBar's frames at 60 a second, on its tanh curve.
    static let dragTint = Animation.easeOut(duration: 4.0 / 60)
    static let dragGlide = Animation.easeOut(duration: 6.0 / 60)
    /// RELEASE_GRACE: a ghost dropped off every pill rests this long on its source before it leaves.
    static let dragReleaseGrace: Duration = .milliseconds(400)
    /// The dragged workspace's own pill dims, the one under the pointer lights up.
    static let dragSourceBackground = surface0
    static let dragSourceText = overlay0
    static let dragTargetBackground = surface1
    static let dragTargetText = base
}

/// Dragging a workspace of the Mac's pill onto another swaps their windows (drag.sh). A ghost pill with the workspace's
/// number follows the pointer from the fourth point on, the source dims and the target lights up; on release the ghost
/// glides onto the target and takes its number while the windows move, or back to the source when nothing was hit. A
/// press that never moves 4 points is a click.
@MainActor
@Observable
final class WorkspaceDragModel {
    /// The slots' frames in the Mac's pill, by workspace id (the 26 point box, without the gap around it).
    @ObservationIgnored var frames: [String: CGRect] = [:]
    private(set) var ghostLeft: CGFloat?
    private(set) var ghostLabel = ""
    private(set) var sourceID: String?
    private(set) var targetID: String?

    @ObservationIgnored private var drag = WorkspaceDrag()
    @ObservationIgnored private var pressStart: CGPoint?
    /// The ghost is gliding or the windows are moving: a new press waits until it is over.
    @ObservationIgnored private var busy = false

    func changed(_ value: DragGesture.Value, pills: [Pill]) {
        guard !busy else { return }
        // A gesture the system cancelled never ended: a new start point is a new press.
        if pressStart != value.startLocation {
            pressStart = value.startLocation
            let slots = pills.compactMap { pill in
                frames[pill.id].map { DragSlot(id: pill.id, left: Double($0.minX), right: Double($0.maxX)) }
            }
            drag.press(at: Double(value.startLocation.x), slots: slots)
        }
        let started = drag.move(to: Double(value.location.x))
        guard drag.phase == .dragging else { return }
        if started {
            ghostLabel = pills.first { $0.id == drag.source?.id }?.label ?? ""
            withAnimation(Theme.dragTint) { sourceID = drag.source?.id }
        }
        if targetID != drag.target?.id {
            withAnimation(Theme.dragTint) { targetID = drag.target?.id }
        }
        ghostLeft = drag.ghostLeft.map { CGFloat($0) }
    }

    func ended(pills: [Pill], workspaces: WorkspacesModel) {
        guard !busy else { return }
        pressStart = nil
        switch drag.release() {
        case .none:
            break
        case .click(let id):
            workspaces.focus(id)
        case .swap(let from, let to, let landing):
            busy = true
            // The ghost lands on the target slot and takes its number: that is where the dragged content lives now.
            withAnimation(Theme.dragGlide) {
                ghostLeft = CGFloat(landing)
                ghostLabel = pills.first { $0.id == to }?.label ?? to
            }
            Task {
                await workspaces.swap(from: from, to: to)
                finish()
            }
        case .cancel(let back):
            busy = true
            withAnimation(Theme.dragGlide) { ghostLeft = CGFloat(back) }
            Task {
                try? await Task.sleep(for: Theme.dragReleaseGrace)
                finish()
            }
        }
    }

    /// The ghost leaves and the slots take the look the workspaces give them.
    private func finish() {
        ghostLeft = nil
        sourceID = nil
        targetID = nil
        busy = false
    }

    /// The tint a slot takes while dragging, or nil for its own.
    func tint(_ id: String) -> (background: Color, text: Color)? {
        if id == sourceID { return (Theme.dragSourceBackground, Theme.dragSourceText) }
        if id == targetID { return (Theme.dragTargetBackground, Theme.dragTargetText) }
        return nil
    }
}

/// The ghost: a slot drawn as the focused one (mauve block, the number in the bar's color), the drag_ghost item.
struct DragGhost: View {
    let drag: WorkspaceDragModel

    var body: some View {
        if let left = drag.ghostLeft {
            Text(drag.ghostLabel)
                .font(Theme.textFont)
                .foregroundStyle(Theme.base)
                .frame(width: Theme.slot, height: Theme.pillHeight)
                .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.mauve))
                .offset(x: left)
                .allowsHitTesting(false)
        }
    }
}
