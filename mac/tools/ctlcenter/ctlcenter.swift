// ctlcenter: open macOS Control Center from a script and tell whether its panel is on screen.
//   ctlcenter open     presses fn+C, the system shortcut that opens Control Center
//   ctlcenter close    presses Escape, which closes the panel
//   ctlcenter top      exits 0 while the pointer is in the top strip where the system menu bar reveals itself
//   ctlcenter indicator exits 0 while macOS shows its orange (microphone), green or purple privacy dot
//   ctlcenter visible  exits 0 while a Control Center window is on screen, 1 otherwise
import AppKit
import CoreGraphics
import Foundation

let fnKey: CGKeyCode = 63
let cKey: CGKeyCode = 8
let escapeKey: CGKeyCode = 53
let keyDelayMicroseconds: UInt32 = 30000
let controlCenterBundleID = "com.apple.controlcenter"
let panelMinHeight: CGFloat = 100
let menuBarStripHeight: CGFloat = 40

func post(_ key: CGKeyCode, down: Bool, flags: CGEventFlags) {
    let source = CGEventSource(stateID: .hidSystemState)
    guard let event = CGEvent(keyboardEventSource: source, virtualKey: key, keyDown: down) else { return }
    event.flags = flags
    event.post(tap: .cghidEventTap)
    usleep(keyDelayMicroseconds)
}

func openControlCenter() {
    post(fnKey, down: true, flags: .maskSecondaryFn)
    post(cKey, down: true, flags: .maskSecondaryFn)
    post(cKey, down: false, flags: .maskSecondaryFn)
    post(fnKey, down: false, flags: [])
}

func closeControlCenter() {
    post(escapeKey, down: true, flags: [])
    post(escapeKey, down: false, flags: [])
}

func pointerIsAtTop() -> Bool {
    (CGEvent(source: nil)?.location.y ?? .infinity) < menuBarStripHeight
}

func privacyIndicatorIsShown() -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { ($0[kCGWindowName as String] as? String) == "StatusIndicator" }
}

func panelIsVisible() -> Bool {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t,
            NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == controlCenterBundleID,
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
        else { return false }
        return (bounds["Height"] ?? 0) > panelMinHeight
    }
}

switch CommandLine.arguments.dropFirst().first {
case "open":
    openControlCenter()
case "close":
    closeControlCenter()
case "top":
    exit(pointerIsAtTop() ? 0 : 1)
case "indicator":
    exit(privacyIndicatorIsShown() ? 0 : 1)
case "visible":
    exit(panelIsVisible() ? 0 : 1)
default:
    FileHandle.standardError.write(Data("usage: ctlcenter open|close|top|indicator|visible\n".utf8))
    exit(2)
}
