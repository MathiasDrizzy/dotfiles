import AppKit
import DotbarCore
import Observation

/// The Control Center button's click (controlcenter.sh): it opens macOS Control Center, or closes it when it is open, with
/// fn+C, the system's own shortcut (the panel cannot be opened any other way from outside, and it opens at the right edge,
/// right under the button). The rules of ControlCenterDriver decide when a key may go out; the cover keeps the native menu
/// bar, which the system draws while the panel is open, hidden under the bar until the panel has closed.
@MainActor
@Observable
final class ControlCenterModel {
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private let cover: CoverModel
    @ObservationIgnored private let timing = ControlCenterDriver.Timing()
    @ObservationIgnored private var intent = ControlCenterIntent()
    @ObservationIgnored private var driver: ControlCenterDriver?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var press: PanelPress?
    @ObservationIgnored private var monitor: Any?

    /// SketchyBar's helper, used only while the bar may not post keys itself (it has its own Accessibility grant).
    private static let helper = NSHomeDirectory() + "/.local/bin/ctlcenter"
    private static let coverReason = "controlcenter"

    init(runner: CommandRunner, cover: CoverModel) {
        self.runner = runner
        self.cover = cover
    }

    /// Notes at every press on the bar whether the panel was open: macOS closes it with that very press, and the click
    /// that follows on release must know (drag.sh's press_panel).
    func start() {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                self?.press = PanelPress(open: ScreenWindows.popupOpen(bundles: [ScreenWindows.controlCenter]), at: Date())
            }
            return event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        timer?.invalidate()
        timer = nil
        driver = nil
    }

    func click() {
        let pressClosed = PanelPress.take(&press, now: Date())
        let visible = driver == nil && !pressClosed && ScreenWindows.popupOpen(bundles: [ScreenWindows.controlCenter])
        switch ControlCenterClick.decide(
            driving: driver != nil, pressClosedPanel: pressClosed, wanted: intent.want, visible: visible)
        {
        case .want(let want): intent.set(want)
        case .nothing: break
        case .pressOnce: pressKey()
        case .drive: drive()
        }
    }

    private func drive() {
        intent.set(.open)
        driver = ControlCenterDriver(handled: intent.serial, timing: timing)
        Popups.shared.close()
        // The native bar comes down with the panel; the cover goes on before the first key.
        cover.hold(Self.coverReason)
        let timer = Timer(fire: Date().addingTimeInterval(timing.firstWait), interval: timing.poll, repeats: true) {
            [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// One poll of the driver: only while a click is being handled, two minutes at most.
    private func tick() {
        guard var driver else { return }
        let visible = ScreenWindows.popupOpen(bundles: [ScreenWindows.controlCenter])
        let top = CoverModel.pointerAtTop()
        var step = driver.step(want: intent.want, serial: intent.serial, visible: visible, pointerAtTop: top)
        if step == .wantClosed {
            intent.set(.closed)
            step = driver.step(want: intent.want, serial: intent.serial, visible: visible, pointerAtTop: top)
        }
        self.driver = driver
        switch step {
        case .pressKey: pressKey()
        case .finish: finish()
        case .wait, .wantClosed: break
        }
    }

    /// Let go first, then hand the cover back: it comes off once the panel is closed and the pointer has left the top.
    private func finish() {
        timer?.invalidate()
        timer = nil
        driver = nil
        cover.release(Self.coverReason)
    }

    /// fn+C, posted by the bar itself when macOS lets it (the Accessibility permission); else through SketchyBar's helper
    /// while it is installed; else the system is asked for the permission.
    private func pressKey() {
        if CGPreflightPostEventAccess() {
            FnC.post()
        } else if FileManager.default.isExecutableFile(atPath: Self.helper) {
            let runner = runner
            Task { _ = await runner.run(Self.helper, ["open"], timeout: 3, key: "ctlcenter open") }
        } else {
            _ = CGRequestPostEventAccess()
        }
    }
}

/// The keys of fn+C, a few milliseconds apart as a keyboard sends them (ctlcenter open), off the main thread.
enum FnC {
    private static let fnKey: CGKeyCode = 63
    private static let cKey: CGKeyCode = 8
    private static let gapMicroseconds: UInt32 = 8000
    private static let queue = DispatchQueue(label: "dotbar.fn-c")

    static func post() {
        queue.async {
            let keys: [(CGKeyCode, Bool, CGEventFlags)] = [
                (fnKey, true, .maskSecondaryFn), (cKey, true, .maskSecondaryFn), (cKey, false, .maskSecondaryFn),
                (fnKey, false, []),
            ]
            let source = CGEventSource(stateID: .hidSystemState)
            for (key, down, flags) in keys {
                guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { continue }
                event.flags = flags
                event.post(tap: .cghidEventTap)
                usleep(gapMicroseconds)
            }
        }
    }
}

/// What is on screen, from the window server's list (no permission needed for owners, levels and sizes).
enum ScreenWindows {
    static let controlCenter = "com.apple.controlcenter"

    /// Whether any of the apps has a panel, menu or popover on screen.
    static func popupOpen(bundles: [String]) -> Bool {
        let owners = Set(
            bundles.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0) }.map(\.processIdentifier))
        guard !owners.isEmpty else { return false }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        let windows = (list as? [[String: Any]] ?? []).compactMap { info -> PopupWindows.Window? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                let layer = info[kCGWindowLayer as String] as? Int,
                let bounds = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { return nil }
            return PopupWindows.Window(pid: pid, layer: layer, height: bounds["Height"] ?? 0)
        }
        return PopupWindows.isOpen(windows, owners: owners)
    }
}
