import DotbarCore
import Foundation

/// stay.sh as part of the bar: one `aerospace subscribe` stream for the session, StayRule decides, and a workspace whose
/// last window closed gets the focus back once AeroSpace confirms it holds no window.
@MainActor
final class StayModel {
    private let runner: CommandRunner
    private let aerospace: String
    private var rule = StayRule()
    private var stream: LineStream?

    private static let queryTimeout: TimeInterval = 3

    init(runner: CommandRunner, aerospace: String) {
        self.runner = runner
        self.aerospace = aerospace
    }

    func start() {
        let stream = LineStream(
            aerospace, ["subscribe", "--no-send-initial", "binding-triggered", "focus-changed", "focused-workspace-changed"]
        ) { [weak self] line in
            Task { @MainActor in self?.handle(line) }
        }
        stream.start()
        self.stream = stream
    }

    func stop() {
        stream?.stop()
    }

    /// The bar asked for a switch (a click on a pill): not a window closing.
    func asked() {
        rule.asked(at: Date())
    }

    /// A drag swap moves windows between workspaces while this is true.
    func setSwapping(_ swapping: Bool) {
        rule.swapping = swapping
    }

    private func handle(_ line: String) {
        guard let event = StayEvent.parse(line),
            case .returnIfEmpty(let workspace) = rule.handle(event, at: Date())
        else { return }
        Task {
            let count = await runner.run(
                aerospace, ["list-windows", "--workspace", workspace, "--count"], timeout: Self.queryTimeout)
            guard count.status == 0, count.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "0" else { return }
            _ = await runner.run(aerospace, ["workspace", workspace], timeout: Self.queryTimeout, key: "stay \(workspace)")
        }
    }
}
