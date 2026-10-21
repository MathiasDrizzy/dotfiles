// ctlcenter: open macOS Control Center from a script and tell whether its panel is on screen.
//   ctlcenter open     presses fn+C, the system shortcut that opens Control Center (and closes it when it is open)
//   ctlcenter top      exits 0 while the pointer is in the top strip where the system menu bar reveals itself
//   ctlcenter watch [maxY]  prints "down X Y open|closed" (whether the Control Center panel was open at the press), "move X Y" and
//                      "up X Y" lines (points, origin top-left) for every left-button press that starts within maxY points of
//                      the top of the screen, until the output is closed; it needs no permissions
//   ctlcenter visible  exits 0 while a Control Center window is on screen, 1 otherwise
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
    // Sampled before every press near the top: macOS starts closing the panel on the press itself, which this loop may see a
    // poll late.
    var panelWasOpen = false
    while true {
        let pressed = CGEventSource.buttonState(.combinedSessionState, button: .left)
        let location = pointerLocation()
        if !pressed {
            if tracking { print("up \(Int(location.x)) \(Int(location.y))") }
            tracking = false
            ignoring = false
            panelWasOpen = location.y < maxY && panelIsVisible()
        } else if !tracking && !ignoring {
            if location.y < maxY {
                tracking = true
                last = location
                print("down \(Int(location.x)) \(Int(location.y)) \(panelWasOpen || panelIsVisible() ? "open" : "closed")")
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
    // The owner is matched by pid (looked up once per call): the watcher runs this every poll near the top of the screen.
    let owners = Set(NSRunningApplication.runningApplications(withBundleIdentifier: controlCenterBundleID).map(\.processIdentifier))
    guard !owners.isEmpty else { return false }
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.contains { window in
        guard let pid = window[kCGWindowOwnerPID as String] as? pid_t, owners.contains(pid),
            let bounds = window[kCGWindowBounds as String] as? [String: CGFloat]
        else { return false }
        return (bounds["Height"] ?? 0) > panelMinHeight
    }
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
    watchPointer(maxY: CommandLine.arguments.dropFirst(2).first.flatMap { Double($0) }.map { CGFloat($0) } ?? menuBarStripHeight)
case "visible":
    exit(panelIsVisible() ? 0 : 1)
case "backdrop":
    printBackdrop(arguments: Array(CommandLine.arguments.dropFirst(2)))
default:
    FileHandle.standardError.write(Data("usage: ctlcenter open|top|watch|visible|backdrop\n".utf8))
    exit(2)
}
