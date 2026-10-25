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

    @ObservationIgnored private var state = WorkspaceState()
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private let aerospace: String
    @ObservationIgnored private var stream: LineStream?
    @ObservationIgnored private var refreshing = false
    @ObservationIgnored private var refreshAgain = false
    @ObservationIgnored private var fallback: Timer?

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

    func focus(_ id: String) {
        Task { _ = await runner.run(aerospace, ["workspace", id], timeout: Self.queryTimeout, key: "focus \(id)") }
    }

    private func handle(_ line: String) {
        guard let event = AeroSpaceEvent.parse(line) else { return }
        if case .focusedWorkspace(let id) = event, !id.isEmpty {
            state.focus(id)
            bar = state.bar
        }
        refresh()
    }

    private func refresh() {
        if refreshing {
            refreshAgain = true
            return
        }
        refreshing = true
        let startedAt = state.generation
        Task {
            let format = "%{workspace}|%{monitor-appkit-nsscreen-screens-id}|%{workspace-is-visible}|%{workspace-is-focused}"
            async let workspaces = runner.run(
                aerospace, ["list-workspaces", "--all", "--format", format], timeout: Self.queryTimeout)
            async let windows = runner.run(
                aerospace, ["list-windows", "--all", "--format", "%{workspace}"], timeout: Self.queryTimeout)
            let (rowsAnswer, windowsAnswer) = await (workspaces, windows)
            let taken = state.apply(
                rows: rowsAnswer.status == 0 ? Workspaces.parseRows(rowsAnswer.stdout) : nil,
                occupied: windowsAnswer.status == 0 ? Workspaces.parseOccupied(windowsAnswer.stdout) : nil,
                startedAt: startedAt)
            if taken { bar = state.bar } else { refreshAgain = true }
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

    var body: some View {
        HStack(spacing: Theme.pillGap) {
            group(model.bar.mac, hidden: model.bar.hiddenMac, block: Theme.mauve)
            if !model.bar.external.isEmpty {
                group(model.bar.external, hidden: model.bar.hiddenExternal, block: Theme.blue, mark: true)
            }
        }
    }

    private func group(_ pills: [Pill], hidden: Int, block: Color, mark: Bool = false) -> some View {
        // Each slot is 26 points plus 1 of padding on each side, side by side: SketchyBar's items in their bracket.
        HStack(spacing: 0) {
            if mark {
                Text("\u{F0379}").font(Theme.iconFont).foregroundStyle(Theme.blue).frame(width: Theme.slot)
                    .padding(.horizontal, 1)
            }
            ForEach(pills, id: \.id) { pill in
                Text(pill.label)
                    .font(Theme.textFont)
                    .foregroundStyle(pill.state == .focused ? Theme.base : Theme.text)
                    .frame(width: Theme.slot, height: Theme.pillHeight)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.pillRadius).fill(
                            pill.state == .focused ? block : (pill.state == .visible ? Theme.surface1 : .clear))
                    )
                    .padding(.horizontal, 1)
                    .contentShape(Rectangle())
                    .onTapGesture { model.focus(pill.id) }
            }
            if hidden > 0 {
                Text("+\(hidden)").font(Theme.textFont).foregroundStyle(Theme.overlay0).padding(.horizontal, 4)
            }
        }
        .frame(height: Theme.pillHeight)
        .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.barColor))
    }
}
