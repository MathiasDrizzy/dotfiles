// ctlcenter: open macOS Control Center from a script and tell whether its panel is on screen.
//   ctlcenter open     presses fn+C, the system shortcut that opens Control Center (and closes it when it is open)
//   ctlcenter top      exits 0 while the pointer is in the top strip where the system menu bar reveals itself
//   ctlcenter watch [maxY]  prints "down X Y open|closed" (whether the Control Center panel was open at the press), "move X Y" and
//                      "up X Y" lines (points, origin top-left) for every left-button press that starts within maxY points of
//                      the top of the screen, until the output is closed; it needs no permissions
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
let idlePollMicroseconds: UInt32 = 25000
let dragPollMicroseconds: UInt32 = 12000

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
    pointerLocation().y < menuBarStripHeight
}

func pointerLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

func watchPointer(maxY: CGFloat) -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)
    var tracking = false
    var ignoring = false
    var last = CGPoint(x: -1, y: -1)
    while true {
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let location = pointerLocation()
        if !pressed {
            if tracking { print("up \(Int(location.x)) \(Int(location.y))") }
            tracking = false
            ignoring = false
        } else if !tracking && !ignoring {
            if location.y < maxY {
                tracking = true
                last = location
                print("down \(Int(location.x)) \(Int(location.y)) \(panelIsVisible() ? "open" : "closed")")
            } else {
                ignoring = true
            }
        } else if tracking && location.x != last.x {
            last = location
            print("move \(Int(location.x)) \(Int(location.y))")
        }
        usleep(tracking ? dragPollMicroseconds : idlePollMicroseconds)
    }
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
case "watch":
    watchPointer(maxY: CommandLine.arguments.dropFirst(2).first.flatMap { Double($0) }.map { CGFloat($0) } ?? menuBarStripHeight)
case "visible":
    exit(panelIsVisible() ? 0 : 1)
default:
    FileHandle.standardError.write(Data("usage: ctlcenter open|top|watch|visible\n".utf8))
    exit(2)
}
