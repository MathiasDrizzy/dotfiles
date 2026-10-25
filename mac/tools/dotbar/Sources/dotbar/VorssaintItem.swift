import AppKit
import DotbarCore
import Observation
import SwiftUI

extension Theme {
    /// The planet of Vorssaint's own icon (Nerd Font fae-planet).
    static let vorssaintGlyph = "\u{E22E}"
    static let vorssaintBundle = "com.vorssaint.utils"
    /// The least widths of the boxes right of Vorssaint's (battery, date, time): an icon and its label at the least
    /// label widths of colors.sh (30, 72, 36). They widen by VorssaintAlign's shares.
    static let leastSpreadWidths: [CGFloat] = [52, 96, 59]
    /// The status boxes and their gaps at those least widths: Vorssaint, battery, date, time, Control Center.
    static let leastStatusWidth: CGFloat = 28 + 52 + 96 + 59 + 28 + 4 * 5
}

/// The Vorssaint box (vorssaint.sh): a click opens Vorssaint's menu bar extra popover, or closes it when it is open. The
/// system menu bar is hidden, so the extra is pressed through Accessibility; the popover is closed with a click outside it,
/// as the user would. macOS opens the popover under the extra wherever the hidden menu bar has it, so at start, when
/// Vorssaint launches and at every click the box moves right above it (VorssaintAlign). Starts Vorssaint when it is not
/// running. Nothing here starts a process.
@MainActor
@Observable
final class VorssaintModel {
    static let shared = VorssaintModel()

    /// What the battery, date and time boxes take above their least widths.
    private(set) var spread: CGFloat = 0
    var shares: [CGFloat] { VorssaintAlign.shares(spread) }

    /// The box's frame in the bar's window (SwiftUI's global space), as it is laid out.
    @ObservationIgnored var anchor: CGRect?
    @ObservationIgnored private var driver: VorssaintDriver?
    @ObservationIgnored private var driving: Task<Void, Never>?
    @ObservationIgnored private var aligning = false
    /// The popover was on screen when the pointer came over the box, or when the last drive ended.
    @ObservationIgnored private var sawOpen = false
    /// When a press on the box found the popover open.
    @ObservationIgnored private var pressSawOpen: Date?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var launched: NSObjectProtocol?

    /// A popover open this long before the click counts for it (drag.sh's PRESS_MAX_SECONDS).
    private static let pressMaxSeconds: TimeInterval = 2
    /// An empty spot of the bar, left of the Apple logo (points, origin top-left): the click outside that closes it.
    private nonisolated static let dismissPoint = CGPoint(x: 8, y: 20)
    /// A popover reads the pointer when it handles the click, not the click's own spot (ctlcenter dismiss).
    private nonisolated static let dismissHoldMicroseconds: UInt32 = 25_000
    /// A popover is a window above the normal level, taller than the menu bar.
    private nonisolated static let popoverMinHeight: CGFloat = 100
    /// The extra shows a moment after Vorssaint launches.
    private nonisolated static let launchSettleSeconds = 2.0
    /// The Accessibility calls wait on Vorssaint, never on the main thread.
    private nonisolated static let queue = DispatchQueue(label: "dotbar.vorssaint")

    func start() {
        // macOS starts closing the popover on the press itself, before the box hears the click.
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, Hover.shared.box == "vorssaint" else { return }
                if self.sawOpen || Self.popoverShown() { self.pressSawOpen = Date() }
            }
            return event
        }
        launched = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == Theme.vorssaintBundle else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.launchSettleSeconds) {
                MainActor.assumeIsolated { self?.align() }
            }
        }
        // The rc's "vorssaint.sh align" once the bar is up: the box has its place by then.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            MainActor.assumeIsolated { self?.align() }
        }
    }

    func stop() {
        driving?.cancel()
        driving = nil
        driver = nil
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let launched { NSWorkspace.shared.notificationCenter.removeObserver(launched) }
        launched = nil
    }

    /// The pointer came over the box.
    func sample() {
        sawOpen = Self.popoverShown()
    }

    func click() {
        if driver != nil {
            driver?.click() // a click while the driver runs only flips what is wanted
            return
        }
        Popups.shared.close()
        align() // the extra moves only when other extras come or go: the next click finds the box in place
        let saw = pressSawOpen.map { Date().timeIntervalSince($0) < Self.pressMaxSeconds } ?? false
        pressSawOpen = nil
        driver = VorssaintDriver(visible: Self.popoverShown(), sawMenuAtPress: saw)
        driving = Task { [weak self] in await self?.drive() }
    }

    private func drive() async {
        try? await Task.sleep(for: .seconds(VorssaintDriver.firstWaitSeconds))
        while !Task.isCancelled, var current = driver {
            let visible = Self.popoverShown()
            let action = current.poll(visible: visible)
            driver = current
            switch action {
            case .finish:
                end(visible: visible)
                return
            case .press:
                guard Self.running() else {
                    Self.launch() // not running: start it instead
                    end(visible: false)
                    return
                }
                guard AXMenuBar.trusted(), await Self.offMain({ Self.pressExtra() }) else {
                    end(visible: visible)
                    return
                }
            case .dismiss:
                _ = await Self.offMain { Self.dismiss(at: Self.dismissPoint) }
            case .none:
                break
            }
            try? await Task.sleep(for: .seconds(VorssaintDriver.pollSeconds))
        }
    }

    private func end(visible: Bool) {
        driver = nil
        driving = nil
        sawOpen = visible
    }

    /// Moves the box over the extra: the battery, date and time boxes widen evenly so its center sits over the extra's.
    func align() {
        guard !aligning, AXIsProcessTrusted(), let anchor,
            let bar = NSApp.windows.first(where: { $0 is BarPanel })
        else { return }
        aligning = true
        let boxLeft = bar.frame.minX + anchor.minX
        Task {
            let extra = await Self.offMain { Self.extraFrame() }
            aligning = false
            guard let extra else { return }
            let wanted = VorssaintAlign.spread(extra: extra, boxLeft: boxLeft, currentSpread: spread)
            if wanted != spread { spread = wanted }
        }
    }

    // MARK: The system, off the main thread where it may wait

    private static func offMain<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { done in queue.async { done.resume(returning: work()) } }
    }

    private static func running() -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: Theme.vorssaintBundle).isEmpty
    }

    private static func launch() {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: Theme.vorssaintBundle) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Whether Vorssaint has a popover on screen (ctlcenter shown): one window list, matched by pid. Needs no permission.
    static func popoverShown() -> Bool {
        let owners = Set(
            NSRunningApplication.runningApplications(withBundleIdentifier: Theme.vorssaintBundle).map(\.processIdentifier))
        guard !owners.isEmpty else { return false }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return (bounds["Height"] ?? 0) > popoverMinHeight
        }
    }

    /// Vorssaint's menu bar extra, through Accessibility (it answers while the system menu bar is hidden). Waits on
    /// Vorssaint 2 seconds at most.
    private nonisolated static func extraItem() -> AXUIElement? {
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: Theme.vorssaintBundle).first
        else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 2)
        var bar: CFTypeRef?
        var items: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &bar) == .success, let bar,
            CFGetTypeID(bar) == AXUIElementGetTypeID(),
            AXUIElementCopyAttributeValue(bar as! AXUIElement, kAXChildrenAttribute as CFString, &items) == .success
        else { return nil }
        return (items as? [AXUIElement])?.first
    }

    private nonisolated static func pressExtra() -> Bool {
        guard let item = extraItem() else { return false }
        return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
    }

    /// The extra's frame in screen points, origin top-left.
    private nonisolated static func extraFrame() -> CGRect? {
        guard let item = extraItem() else { return nil }
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &position) == .success,
            AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size, CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &origin), AXValueGetValue(size as! AXValue, .cgSize, &extent)
        else { return nil }
        return CGRect(origin: origin, size: extent)
    }

    /// A click at `point` and the pointer back 25 ms later, which closes a popover the way a click outside it does
    /// (ctlcenter dismiss). Nothing while a mouse button is held: the user is dragging.
    private nonisolated static func dismiss(at point: CGPoint) -> Bool {
        guard !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return false }
        let back = CGEvent(source: nil)?.location ?? point
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        usleep(dismissHoldMicroseconds)
        // Back with a posted move, as the mouse itself would: after a warp macOS ignores the mouse for a moment.
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: back, mouseButton: .left)?
            .post(tap: .cghidEventTap)
        return true
    }
}

/// The planet in mauve on a box 28 points wide, the hover tint under the pointer (the vorssaint item of sketchybarrc).
struct VorssaintView: View {
    let model: VorssaintModel

    var body: some View {
        BarBox(id: "vorssaint", width: VorssaintAlign.boxWidth, action: { model.click() }) {
            NerdIcon(Theme.vorssaintGlyph, color: Theme.mauve)
        }
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { model.anchor = $0 }
        .onChange(of: Hover.shared.box == "vorssaint") { _, inside in
            if inside { model.sample() }
        }
    }
}
