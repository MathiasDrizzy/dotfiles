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

/// What the layout needs from the screen and from boxes whose width depends on their content.
@MainActor
@Observable
final class BarLayout {
    static let shared = BarLayout()
    var screenWidth: CGFloat = 1470
    var hasNotch = true
    var weatherWidth: CGFloat = 0
    /// The bar's frame in the event system's points (origin top-left of the main display).
    var barFrameTopLeft = CGRect(x: 0, y: 0, width: 1470, height: 40)
}

/// The bar's content, in two zones around the camera housing as SketchyBar laid it out: Apple, the front app and the
/// workspaces from the left edge, the moon and weather boxes ending at the housing; the track starting right after it,
/// the status boxes ending 37 points from the right edge. BarFit decides what narrows when it does not all fit.
struct BarView: View {
    let workspaces: WorkspacesModel
    let status: StatusModel
    let moon: MoonModel
    let weather: WeatherModel
    let media: MediaModel
    let frontApp: FrontAppModel
    let runner: CommandRunner
    let cover: CoverModel
    let controlCenter: ControlCenterModel

    // SketchyBar's measures: the left side starts 23 points in, the boxes before the name's box take 28 + 3 + 45, the
    // weather box ends 3 points before the housing, the right side ends 37 points before the edge, and the status boxes
    // (Vorssaint, battery, date, time, Control Center and their gaps) take 283 points before it, plus what the battery,
    // date and time boxes widen by to put Vorssaint's box over its menu bar extra.
    private static let leftInset: CGFloat = 23
    private static let leftFixed: CGFloat = 28 + 3 + 45
    private static let beforeNotch: CGFloat = 3
    private static let rightInset: CGFloat = 37

    var body: some View {
        let layout = BarLayout.shared
        let notch = BarFit.notch(screenWidth: layout.screenWidth, hasNotch: layout.hasNotch)
        let room = BarFit.leftRoom(
            notchLeft: notch.left, weatherWidth: layout.weatherWidth, leftInset: Self.leftInset,
            fixedBeforeName: Self.leftFixed, external: !workspaces.bar.external.isEmpty)
        let left = BarFit.left(room: room, natural: workspaces.natural)
        let chars = BarFit.mediaChars(
            notchRight: notch.right,
            vorssaintLeft: layout.screenWidth - Self.rightInset - Theme.leastStatusWidth - VorssaintModel.shared.spread)

        HStack(spacing: 0) {
            HStack(spacing: Theme.pillGap) {
                // SketchyBar's left edge: the Apple block 23 points in, the front app's pill 3 points after it.
                HStack(spacing: 3) {
                    AppleView(runner: runner)
                    FrontAppView(model: frontApp)
                }
                WorkspacesView(model: workspaces)
                Spacer(minLength: 0)
                MoonView(model: moon)
                WeatherView(model: weather)
            }
            .padding(.leading, Self.leftInset)
            .padding(.trailing, Self.beforeNotch)
            .frame(width: notch.left)
            Color.clear.frame(width: notch.right - notch.left)
            HStack(spacing: Theme.pillGap) {
                MediaView(model: media)
                Spacer(minLength: 0)
                StatusView(model: status, controlCenter: controlCenter)
            }
            .padding(.trailing, Self.rightInset)
            .frame(width: layout.screenWidth - notch.right)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The cover is behind every box (the rc's first bracket).
        .background { CoverView(model: cover) }
        .task(id: left) {
            frontApp.setNameWidth(left.nameWidth)
            workspaces.cap = left.cap
        }
        .task(id: chars) { media.maxLength = chars }
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
    private lazy var stay = StayModel(runner: runner, aerospace: aerospacePath())
    /// `ctlcenter stay` (mac/tools/ctlcenter): keeps AeroSpace from following macOS elsewhere when the app in front quits,
    /// by putting Finder right behind it. Long-lived, started again if it ends; SketchyBar's rc used to start it.
    private let finderBehind = LineStream(
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/ctlcenter").path, ["stay"],
        restartDelay: 5
    ) { _ in }
    private let status = StatusModel()
    private let moon = MoonModel()
    private let weather = WeatherModel()
    private lazy var media = MediaModel(runner: runner, mediaControl: mediaControlPath())
    private let frontApp = FrontAppModel()
    private lazy var cover = CoverModel(edge: edge)
    private lazy var controlCenter = ControlCenterModel(runner: runner, cover: cover)

    func applicationDidFinishLaunching(_ notification: Notification) {
        workspaces.onAsked = { [weak self] in self?.stay.asked() }
        workspaces.onSwapping = { [weak self] swapping in self?.stay.setSwapping(swapping) }
        VorssaintModel.shared.onMenu = { [weak self] open in
            // The user may close the popover without the bar: the hold ends as soon as it is gone.
            if open {
                self?.cover.hold("vorssaint", while: { VorssaintModel.popoverShown() })
            } else {
                self?.cover.release("vorssaint")
            }
        }
        workspaces.start()
        // `defaults write dev.dotfiles.dotbar stay -bool false` turns both stay helpers off, for an AeroSpace that keeps
        // the workspace itself (`stay-on-workspace-when-app-quits`): no extra subscribe stream and no Finder brought
        // forward at each switch (an app in front blinks).
        if UserDefaults.standard.object(forKey: "stay") as? Bool ?? true {
            stay.start()
            finderBehind.start()
        }
        status.start()
        moon.start()
        weather.start()
        media.start()
        frontApp.start()
        VorssaintModel.shared.start()
        cover.start()
        controlCenter.start()
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
        stay.stop()
        finderBehind.stop()
        status.stop()
        moon.stop()
        weather.stop()
        media.stop()
        frontApp.stop()
        VorssaintModel.shared.stop()
        controlCenter.stop()
        cover.stop()
    }

    func applicationWillTerminate(_ notification: Notification) {
        shutdown()
    }

    private func place() {
        guard let screen = NSScreen.screens.first else { return }
        let frame = BarGeometry.frame(on: screen.frame, edge: edge)
        BarLayout.shared.screenWidth = screen.frame.width
        BarLayout.shared.hasNotch = screen.safeAreaInsets.top > 0
        let mainHeight = NSScreen.screens.first?.frame.height ?? screen.frame.height
        BarLayout.shared.barFrameTopLeft = CGRect(
            x: frame.minX, y: mainHeight - frame.maxY, width: frame.width, height: frame.height)
        if let panel {
            panel.setFrame(frame, display: true)
            return
        }
        let panel = BarPanel(frame: frame)
        panel.contentView = NSHostingView(
            rootView: BarView(
                workspaces: workspaces, status: status, moon: moon, weather: weather, media: media,
                frontApp: frontApp, runner: runner, cover: cover, controlCenter: controlCenter))
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
