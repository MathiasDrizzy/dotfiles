// dotbar: the top bar as one native app (odd/tasks/swift-bar.md): a panel above the menu bar on every Space that never
// takes the focus, with the items built task by task.
//   dotbar            the bar at the top of the main display
//   dotbar --bottom   at the bottom, next to SketchyBar while dotbar is being built
import AppKit
import DotbarCore
import SwiftUI

/// A borderless panel that never becomes the active window (a click on it must not take the focus from the app in front,
/// nor pull a full screen app off its Space), above the menu bar, on every Space.
final class BarPanel: NSPanel {
    init(frame: CGRect) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 1)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// The bar's content: the items arrive task by task (odd/tasks/swift-bar.md); for now the workspaces.
struct BarView: View {
    let workspaces: WorkspacesModel

    var body: some View {
        HStack(spacing: Theme.pillGap) {
            WorkspacesView(model: workspaces)
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Where AeroSpace's command line is: a login agent starts the bar with a bare PATH.
func aerospacePath() -> String {
    let candidates = ["/opt/homebrew/bin/aerospace", "/usr/local/bin/aerospace"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BarPanel?
    private let edge: BarEdge = CommandLine.arguments.contains("--bottom") ? .bottom : .top
    private let runner = CommandRunner()
    private lazy var workspaces = WorkspacesModel(runner: runner, aerospace: aerospacePath())

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspaces.start()
        place()
        // Screens come and go (a monitor plugged in, the lid closed): the bar follows the main display.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    /// The long-lived commands end with the bar; left alone, a stream would only notice at its next event.
    func shutdown() {
        workspaces.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = BarGeometry.frame(on: screen.frame, edge: edge)
        if let panel {
            panel.setFrame(frame, display: true)
            return
        }
        let panel = BarPanel(frame: frame)
        panel.contentView = NSHostingView(rootView: BarView(workspaces: workspaces))
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar of its own
let delegate = AppDelegate()
app.delegate = delegate
// `kill`, a login agent stopping it, Ctrl-C: stop the streams, then quit.
let signalSources = [SIGTERM, SIGINT].map { number -> DispatchSourceSignal in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
    source.setEventHandler {
        MainActor.assumeIsolated { delegate.shutdown() }
        exit(0)
    }
    source.resume()
    return source
}
app.run()
