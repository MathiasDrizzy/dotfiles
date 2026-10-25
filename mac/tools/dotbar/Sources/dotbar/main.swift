// dotbar: the top bar as one native app (odd/tasks/swift-bar.md). For now (T1) the bar's window with one box, to prove
// it sits above the menu bar on every Space without taking the focus.
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

/// The bar's content. T1 draws one box in the bar's colors; the items come in the next tasks.
struct BarView: View {
    var body: some View {
        HStack {
            Text("dotbar")
                .font(.custom("JetBrainsMono Nerd Font", size: 12).bold())
                .foregroundStyle(Color(red: 0xca / 255, green: 0xd3 / 255, blue: 0xf5 / 255))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 5).fill(Color(red: 0x24 / 255, green: 0x26 / 255, blue: 0x39 / 255)))
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: BarPanel?
    private let edge: BarEdge = CommandLine.arguments.contains("--bottom") ? .bottom : .top

    func applicationDidFinishLaunching(_ notification: Notification) {
        place()
        // Screens come and go (a monitor plugged in, the lid closed): the bar follows the main display.
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.place() }
        }
    }

    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = BarGeometry.frame(on: screen.frame, edge: edge)
        if let panel {
            panel.setFrame(frame, display: true)
            return
        }
        let panel = BarPanel(frame: frame)
        panel.contentView = NSHostingView(rootView: BarView())
        panel.orderFrontRegardless()
        self.panel = panel
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon, no menu bar of its own
let delegate = AppDelegate()
app.delegate = delegate
app.run()
