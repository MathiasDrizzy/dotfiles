import DotbarCore
import Foundation
import Observation
import SwiftUI

/// The AeroSpace workspaces: one `aerospace subscribe` stream for the life of the bar, and a fresh look at the workspaces
/// after each event (one at a time; an event that arrives meanwhile asks for one more). A workspace switch is painted at
/// once from the event itself, and a look that started before it is dropped (WorkspaceState), so an old focus never comes
/// back after a new one.
@MainActor
@Observable
final class WorkspacesModel {
    private(set) var bar = WorkspaceBar()
    /// How many workspaces would show without a cap (the fit reads it).
    private(set) var natural = 0
    /// How many slots fit beside the moon box (the fit sets it); nil: all.
    var cap: Int? {
        didSet { if cap != oldValue { redraw() } }
    }

    @ObservationIgnored private var state = WorkspaceState()
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private let aerospace: String
    @ObservationIgnored private var stream: LineStream?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var fallback: Timer?
    @ObservationIgnored private var gate = SwapGate()
    /// A workspace dragged onto another (DragItem).
    let drag = WorkspaceDragModel()

    /// AeroSpace's answers come in milliseconds; past this one it is not answering, and the bar keeps what it has.
    private static let queryTimeout: TimeInterval = 3
    /// Windows that close on another workspace send no event: a slow look now and then catches them.
    private static let fallbackSeconds: TimeInterval = 5

    init(runner: CommandRunner, aerospace: String) {
        self.runner = runner
        self.aerospace = aerospace
    }

    func start() {
        let stream = LineStream(
            aerospace, ["subscribe", "--no-send-initial", "focused-workspace-changed", "focus-changed", "focused-monitor-changed"]
        ) { [weak self] line in
            Task { @MainActor in self?.handle(line) }
        }
        stream.start()
        self.stream = stream
        refresh()
        fallback = Timer.scheduledTimer(withTimeInterval: Self.fallbackSeconds, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Ends the stream and the fallback timer: the bar is quitting.
    func stop() {
        fallback?.invalidate()
        stream?.stop()
    }

    private func redraw() {
        let all = state.bar
        natural = all.mac.count + all.external.count
        bar = cap == nil ? all : Workspaces.layout(rows: state.rows, occupied: state.occupied, cap: cap)
    }

    /// A click on a pill asked for this switch (stay must not undo it).
    @ObservationIgnored var onAsked: (() -> Void)?
    /// A swap is moving windows (stay must not take an emptied workspace for a closed window).
    @ObservationIgnored var onSwapping: ((Bool) -> Void)?

    func focus(_ id: String) {
        onAsked?()
        Task { _ = await runner.run(aerospace, ["workspace", id], timeout: Self.queryTimeout, key: "focus \(id)") }
    }

    /// Swaps the windows of two workspaces. The pills keep what they show meanwhile (the focus parks on an empty
    /// workspace and the windows move one by one); at the end the focus is painted where the swap left it, and the
    /// workspaces are read once.
    func swap(from: String, to: String) async {
        gate.begin()
        onSwapping?(true)
        let outcome = await WorkspaceSwap.run(
            runner: runner, aerospace: aerospace, from: from, to: to, timeout: Self.queryTimeout)
        onSwapping?(false)
        guard gate.end() else { return }
        if case .swapped(let focus?) = outcome {
            state.focus(focus)
            redraw()
        }
        refresh()
    }

    private func handle(_ line: String) {
        guard gate.allowRefresh(), let event = AeroSpaceEvent.parse(line) else { return }
        if case .focusedWorkspace(let id) = event, !id.isEmpty {
            state.focus(id)
            redraw()
        }
        refresh()
    }

    private func refresh() {
        guard gate.allowRefresh() else { return }
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        let look = state.beginLook()
        Task {
            let format = "%{workspace}|%{monitor-appkit-nsscreen-screens-id}|%{workspace-is-visible}|%{workspace-is-focused}"
            async let workspaces = runner.run(
                aerospace, ["list-workspaces", "--all", "--format", format], timeout: Self.queryTimeout)
            async let windows = runner.run(
                aerospace, ["list-windows", "--all", "--format", "%{workspace}"], timeout: Self.queryTimeout)
            let (rowsAnswer, windowsAnswer) = await (workspaces, windows)
            // A swap started meanwhile: what was read is half done, and the swap reads it all again at its end.
            if gate.swapping {
                refreshing = false
                return
            }
            let taken = state.apply(
                rows: rowsAnswer.status == 0 ? Workspaces.parseRows(rowsAnswer.stdout) : nil,
                occupied: windowsAnswer.status == 0 ? Workspaces.parseOccupied(windowsAnswer.stdout) : nil,
                look: look)
            if taken { redraw() } else { refreshAgain = true }
            refreshing = false
            if refreshAgain {
                refreshAgain = false
                refresh()
            }
        }
    }
}

/// The pills: the Mac's workspaces in one box, another monitor's in a second one marked with a monitor glyph.
struct WorkspacesView: View {
    let model: WorkspacesModel

    /// The Mac's pill: its coordinates are the ones a drag follows.
    nonisolated private static let macSpace = "macPill"

    var body: some View {
        let mac = model.bar.mac
        HStack(spacing: Theme.pillGap) {
            // A workspace of the Mac's pill can be dragged onto another (as drag.sh, which followed only those): a press
            // that moves less than 4 points is the click.
            group(mac, hidden: model.bar.hiddenMac, block: Theme.mauve, draggable: true)
                .coordinateSpace(name: Self.macSpace)
                .overlay(alignment: .leading) { DragGhost(drag: model.drag) }
                .gesture(
                    DragGesture(minimumDistance: 0, coordinateSpace: .named(Self.macSpace))
                        .onChanged { model.drag.changed($0, pills: mac) }
                        .onEnded { _ in model.drag.ended(pills: mac, workspaces: model) }
                )
            if !model.bar.external.isEmpty {
                group(model.bar.external, hidden: model.bar.hiddenExternal, block: Theme.blue, mark: true)
            }
        }
        // The ghost travels over the boxes beside the pills: it is drawn above them.
        .zIndex(1)
    }

    @ViewBuilder
    private func group(_ pills: [Pill], hidden: Int, block: Color, mark: Bool = false, draggable: Bool = false)
        -> some View
    {
        // Each slot is 26 points plus 1 of padding on each side, side by side: SketchyBar's items in their bracket.
        HStack(spacing: 0) {
            if mark {
                // Its ink is wider than its advance (13.8 points against 9): laid out as plain text it was cut.
                InkCenteredIcon(glyph: "\u{F0379}", color: Theme.blue).frame(width: Theme.slot)
                    .padding(.horizontal, 1)
            }
            ForEach(pills, id: \.id) { pill in
                let tint = draggable ? model.drag.tint(pill.id) : nil
                let slot = Text(pill.label)
                    .font(Theme.textFont)
                    .foregroundStyle(tint?.text ?? (pill.state == .focused ? Theme.base : Theme.text))
                    .frame(width: Theme.slot, height: Theme.pillHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.pillRadius).fill(
                            tint?.background
                                ?? (pill.state == .focused ? block : (pill.state == .visible ? Theme.surface1 : .clear)))
                    )
                if draggable {
                    slot
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.macSpace)) } action: {
                            model.drag.frames[pill.id] = $0
                        }
                        .padding(.horizontal, 1)
                        .contentShape(Rectangle())
                } else {
                    slot
                        .padding(.horizontal, 1)
                        .contentShape(Rectangle())
                        .onTapGesture { model.focus(pill.id) }
                }
            }
            if hidden > 0 {
                Text("+\(hidden)").font(Theme.textFont).foregroundStyle(Theme.overlay0).padding(.horizontal, 4)
            }
        }
        .frame(height: Theme.pillHeight)
        .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.barColor))
    }
}
