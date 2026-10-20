// ctlcenter: open macOS Control Center from a script and tell whether its panel is on screen.
//   ctlcenter open     presses fn+C, the system shortcut that opens Control Center (and closes it when it is open)
//   ctlcenter top      exits 0 while the pointer is in the top strip where the system menu bar reveals itself
//   ctlcenter pressed  exits 0 while the left mouse button is held down
//   ctlcenter visible  exits 0 while a Control Center window is on screen, 1 otherwise
import AppKit
import CoreGraphics
import Foundation

let fnKey: CGKeyCode = 63
let cKey: CGKeyCode = 8
let keyDelayMicroseconds: UInt32 = 8000
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

func pointerIsAtTop() -> Bool {
    (CGEvent(source: nil)?.location.y ?? .infinity) < menuBarStripHeight
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
case "top":
    exit(pointerIsAtTop() ? 0 : 1)
case "pressed":
    exit(CGEventSource.buttonState(.combinedSessionState, button: .left) ? 0 : 1)
case "visible":
    exit(panelIsVisible() ? 0 : 1)
default:
    FileHandle.standardError.write(Data("usage: ctlcenter open|top|pressed|visible\n".utf8))
    exit(2)
}
