// ctlcenter: open macOS Control Center from a script and tell whether its panel is on screen.
//   ctlcenter open     presses fn+C, the system shortcut that opens Control Center (and closes it when it is open)
//   ctlcenter top      exits 0 while the pointer is in the top strip where the system menu bar reveals itself
//   ctlcenter watch [maxY [BUNDLE]]  prints "down X Y open|closed open|closed" (whether the Control Center panel and the menu
//                      of the app BUNDLE were open at the press), "move X Y" and "up X Y" lines (points, origin top-left) for
//                      every left-button press that starts within maxY points of the top of the screen, and "top" / "away"
//                      when the pointer enters or leaves that strip, until the output is closed; it needs no permissions
//   ctlcenter visible  exits 0 while a Control Center window is on screen, 1 otherwise
//   ctlcenter menu BUNDLE   opens (or closes) the menu bar extra of the app BUNDLE, as a click on it would; needs Accessibility
//   ctlcenter shown BUNDLE  exits 0 while the app BUNDLE has a menu or popover on screen, 1 otherwise
//   ctlcenter dismiss X Y   clicks at X Y (points, origin top-left) and puts the pointer back 25 ms later, which closes a
//                      popover the way a click outside it does; does nothing (exit 1) while a mouse button is held; needs
//                      Accessibility
//   ctlcenter backdrop OUT HEIGHT  saves to OUT (PNG) the top HEIGHT points of the main display as they look without
//                      SketchyBar and JankyBorders (wallpaper, the system's own dimming and anything else behind the bar) and
//                      prints the scale to show it at (points per pixel); needs the Screen Recording permission
import AppKit
import CoreGraphics
import Foundation
import ScreenCaptureKit
import UniformTypeIdentifiers

let fnKey: CGKeyCode = 63
let cKey: CGKeyCode = 8
let keyDelayMicroseconds: UInt32 = 8000
let controlCenterBundleID = "com.apple.controlcenter"
let panelMinHeight: CGFloat = 100
let menuBarStripHeight: CGFloat = 40
let idlePollMicroseconds: UInt32 = 25000
let dragPollMicroseconds: UInt32 = 8000
var dismissHoldMicroseconds: UInt32 = 25000 // a popover reads the pointer when it handles the click, not the click's own spot

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

// A popover closed through its menu bar extra hands activation back to the app before it, and Vorssaint's next popover then
// shut at a click inside it; a click elsewhere closes it as the user would. The pointer stays there a moment: the popover
// asks where the pointer is when it handles the click, and one already back over its extra is not a click outside.
func dismiss(at point: CGPoint) -> Bool {
    guard !CGEventSource.buttonState(.combinedSessionState, button: .left) else { return false }
    let back = pointerLocation()
    for type in [CGEventType.leftMouseDown, .leftMouseUp] {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cghidEventTap)
    }
    usleep(dismissHoldMicroseconds)
    CGWarpMouseCursorPosition(back)
    CGAssociateMouseAndMouseCursorPosition(1)
    return true
}

func pointerIsAtTop() -> Bool {
    pointerLocation().y < menuBarStripHeight
}

func pointerLocation() -> CGPoint {
    CGEvent(source: nil)?.location ?? .zero
}

func watchPointer(maxY: CGFloat, menuBundleID: String?) -> Never {
    setvbuf(stdout, nil, _IOLBF, 0)
    let bundleIDs = [controlCenterBundleID] + (menuBundleID.map { [$0] } ?? [])
    var tracking = false
    var ignoring = false
    var atTop = false
    var last = CGPoint(x: -1, y: -1)
    // Sampled before every press near the top: macOS starts closing a panel or a menu on the press itself, which this loop may
    // see a poll late.
    var wasOpen = [false, false]
    while true {
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let location = pointerLocation()
        if !pressed {
            if tracking { print("up \(Int(location.x)) \(Int(location.y))") }
            tracking = false
            ignoring = false
            if (location.y < maxY) != atTop {
                atTop = location.y < maxY
                print(atTop ? "top" : "away")
            }
            wasOpen = atTop ? openPopups(of: bundleIDs) + [false] : [false, false]
        } else if !tracking && !ignoring {
            if location.y < maxY {
                tracking = true
                last = location
                let open = zip(wasOpen, openPopups(of: bundleIDs) + [false]).map { ($0 || $1) ? "open" : "closed" }
                print("down \(Int(location.x)) \(Int(location.y)) \(open[0]) \(open[1])")
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

// Whether each app has a panel, menu or popover on screen: a window above the normal level, taller than the menu bar. One
// window list for all of them, matched by pid (looked up on every call): the watcher runs this every poll near the top.
func openPopups(of bundleIDs: [String]) -> [Bool] {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return bundleIDs.map { bundleID in
        let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).map(\.processIdentifier))
        return windows.contains { window in
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
                let layer = window[kCGWindowLayer as String] as? Int, layer > 0,
                let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
            else { return false }
            return (bounds["Height"] ?? 0) > panelMinHeight
        }
    }
}

func panelIsVisible() -> Bool {
    openPopups(of: [controlCenterBundleID])[0]
}

// Presses the app's menu bar extra through Accessibility, which works while the system menu bar is hidden.
func pressMenuExtra(of bundleID: String) -> Bool {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else { return false }
    var menuBar: CFTypeRef?
    var items: CFTypeRef?
    let element = AXUIElementCreateApplication(app.processIdentifier)
    guard AXUIElementCopyAttributeValue(element, "AXExtrasMenuBar" as CFString, &menuBar) == .success, let menuBar,
        AXUIElementCopyAttributeValue(menuBar as! AXUIElement, kAXChildrenAttribute as CFString, &items) == .success,
        let item = (items as? [AXUIElement])?.first
    else { return false }
    return AXUIElementPerformAction(item, kAXPressAction as CFString) == .success
}

let hiddenFromBackdrop: Set<String> = ["sketchybar", "borders"]

// What the screen shows behind the bar: the bar's own windows (and the focus border) are left out of the capture.
func saveBackdrop(to path: String, height: CGFloat) async throws -> CGFloat {
    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first(where: { $0.displayID == CGMainDisplayID() }) else {
        throw CocoaError(.fileNoSuchFile)
    }
    let hidden = content.windows.filter { hiddenFromBackdrop.contains($0.owningApplication?.applicationName ?? "") }
    let filter = SCContentFilter(display: display, excludingWindows: hidden)
    let scale = CGFloat(filter.pointPixelScale)
    let configuration = SCStreamConfiguration()
    configuration.sourceRect = CGRect(x: 0, y: 0, width: CGFloat(display.width), height: height)
    configuration.width = Int(CGFloat(display.width) * scale)
    configuration.height = Int(height * scale)
    configuration.showsCursor = false
    let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    guard let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
    return 1 / scale
}

func printBackdrop(arguments: [String]) -> Never {
    guard arguments.count == 2, let height = Double(arguments[1]) else {
        FileHandle.standardError.write(Data("usage: ctlcenter backdrop OUT HEIGHT\n".utf8))
        exit(2)
    }
    let done = DispatchSemaphore(value: 0)
    var status: Int32 = 1
    Task {
        do {
            print(try await saveBackdrop(to: arguments[0], height: CGFloat(height)))
            status = 0
        } catch {
            FileHandle.standardError.write(Data("ctlcenter backdrop: \(error.localizedDescription)\n".utf8))
        }
        done.signal()
    }
    done.wait()
    exit(status)
}

switch CommandLine.arguments.dropFirst().first {
case "open":
    openControlCenter()
case "top":
    exit(pointerIsAtTop() ? 0 : 1)
case "watch":
    let arguments = Array(CommandLine.arguments.dropFirst(2))
    watchPointer(maxY: arguments.first.flatMap { Double($0) }.map { CGFloat($0) } ?? menuBarStripHeight, menuBundleID: arguments.dropFirst().first)
case "visible":
    exit(panelIsVisible() ? 0 : 1)
case "menu", "shown":
    guard let bundleID = CommandLine.arguments.dropFirst(2).first else {
        FileHandle.standardError.write(Data("usage: ctlcenter menu|shown BUNDLE\n".utf8))
        exit(2)
    }
    exit((CommandLine.arguments[1] == "menu" ? pressMenuExtra(of: bundleID) : openPopups(of: [bundleID])[0]) ? 0 : 1)
case "dismiss":
    let numbers = CommandLine.arguments.dropFirst(2).compactMap { Double($0) }
    guard numbers.count == 2 else {
        FileHandle.standardError.write(Data("usage: ctlcenter dismiss X Y\n".utf8))
        exit(2)
    }
    exit(dismiss(at: CGPoint(x: numbers[0], y: numbers[1])) ? 0 : 1)
case "backdrop":
    printBackdrop(arguments: Array(CommandLine.arguments.dropFirst(2)))
default:
    FileHandle.standardError.write(Data("usage: ctlcenter open|top|watch|visible|menu|shown|dismiss|backdrop\n".utf8))
    exit(2)
}
