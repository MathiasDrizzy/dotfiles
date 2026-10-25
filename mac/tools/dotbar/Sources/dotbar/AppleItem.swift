import AppKit
import DotbarCore
import Observation
import SwiftUI

extension Theme {
    /// The Apple block (colors.sh APPLE_*): peach at rest, yellow under the pointer, red while its menu is open.
    static let appleRest = Color(hex: 0xf5a97f)
    static let appleHover = Color(hex: 0xeed49f)
    static let appleOpen = Color(hex: 0xed8796)
    /// The Apple logo is U+F8FF of the system font (the app font has none), at APPLE_SIZE.
    static let appleFont = Font.system(size: 18)
    /// A popup entry: SketchyBar gave each one the bar's height.
    static let menuRowHeight: CGFloat = 40
    static let menuRadius: CGFloat = 12
}

/// One entry of a popup menu: a glyph (none for an app's menu items), its color, a label and what a click does.
struct MenuRow: Identifiable {
    let id: String
    let glyph: String
    let color: Color
    let label: String
    let action: () -> Void
}

/// Where an entry's glyph and label sit, measured on SketchyBar's popups (from the popup's outer edge): the Apple menu's
/// icons are wider than the app menus' chevrons.
struct MenuLayout {
    let iconCenter: CGFloat
    let labelX: CGFloat
    static let apple = MenuLayout(iconCenter: 17, labelX: 32.5)
    static let app = MenuLayout(iconCenter: 16, labelX: 28)
    /// After the longest label, up to the popup's outer edge.
    static let trailing: CGFloat = 16
}

/// A popup's content: the entries stacked, on the base color with a thin outline and round corners (popup.background).
struct MenuList: View {
    let rows: [MenuRow]
    let layout: MenuLayout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                let hovered = Hover.shared.box == "menu." + row.id
                HStack(spacing: 0) {
                    NerdIcon(row.glyph, color: row.color)
                        .padding(.leading, layout.iconCenter - Theme.iconWidth / 2)
                    Text(row.label).font(Theme.mediumFont).foregroundStyle(Theme.text).fixedSize()
                        .padding(.leading, layout.labelX - layout.iconCenter - Theme.iconWidth / 2)
                    Spacer(minLength: MenuLayout.trailing)
                }
                .frame(height: Theme.menuRowHeight)
                // hover.sh: the entry under the pointer gets the hover tint, 24 points tall (the default background).
                .background(
                    RoundedRectangle(cornerRadius: 8).fill(hovered ? Theme.surface0 : .clear).frame(height: 24)
                        .padding(.leading, 3).padding(.trailing, 4)
                )
                .contentShape(Rectangle())
                .onHover { inside in
                    if inside {
                        Hover.shared.box = "menu." + row.id
                    } else if Hover.shared.box == "menu." + row.id {
                        Hover.shared.box = nil
                    }
                }
                .onTapGesture { row.action() }
            }
        }
        .fixedSize()
        .background(
            RoundedRectangle(cornerRadius: Theme.menuRadius).fill(Theme.base)
                .overlay(RoundedRectangle(cornerRadius: Theme.menuRadius).strokeBorder(Theme.surface1, lineWidth: 1))
        )
    }
}

/// A popup's window: like the bar's, it never takes the focus from the app in front.
final class PopupPanel: NSPanel {
    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
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

/// The bar's popups (the Apple menu and the app's menus): one open at a time, under the box that opened it. It closes when
/// the pointer leaves the box and the popup, or on a click anywhere else (apple.sh's mouse.exited.global, close_popups.sh).
@MainActor
@Observable
final class Popups {
    static let shared = Popups()

    enum Kind { case apple, front }
    enum Align { case left, center }

    private(set) var open: Kind?
    /// Each box's frame in the bar's window (SwiftUI's global space, top-left origin), as it is laid out.
    @ObservationIgnored var anchors: [Kind: CGRect] = [:]
    @ObservationIgnored private var panel: PopupPanel?
    @ObservationIgnored private var hosting: NSHostingView<MenuList>?
    @ObservationIgnored private var monitors: [Any] = []
    /// The box's column of the bar plus the popup: the pointer may move anywhere in it.
    @ObservationIgnored private var keepArea: [CGRect] = []

    func show(_ kind: Kind, rows: [MenuRow], layout: MenuLayout, align: Align) {
        guard let bar = NSApp.windows.first(where: { $0 is BarPanel }), let anchor = anchors[kind] else { return }
        let list = MenuList(rows: rows, layout: layout)
        let panel = panel ?? PopupPanel()
        let hosting = hosting ?? NSHostingView(rootView: list)
        hosting.rootView = list
        panel.contentView = hosting
        let size = hosting.fittingSize
        // The box in screen coordinates; SketchyBar's popup.align=left put the popup at the item's left padding (2).
        let box = CGRect(
            x: bar.frame.minX + anchor.minX, y: bar.frame.maxY - anchor.maxY, width: anchor.width, height: anchor.height)
        let x = align == .left ? box.minX - 2 : box.midX - size.width / 2
        // Under the bar; above it while the bar sits at the bottom for development.
        let atBottom = bar.screen.map { bar.frame.minY <= $0.frame.minY } ?? false
        let y = atBottom ? bar.frame.maxY : bar.frame.minY - size.height
        panel.setFrame(CGRect(x: x, y: y, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        self.hosting = hosting
        keepArea = [CGRect(x: box.minX, y: bar.frame.minY, width: box.width, height: bar.frame.height), panel.frame]
        open = kind
        watch()
    }

    func close() {
        guard open != nil else { return }
        open = nil
        panel?.orderOut(nil)
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        if Hover.shared.box?.hasPrefix("menu.") == true { Hover.shared.box = nil }
    }

    func toggle(_ kind: Kind, rows: () -> [MenuRow], layout: MenuLayout, align: Align) {
        if open == kind {
            close()
        } else {
            show(kind, rows: rows(), layout: layout, align: align)
        }
    }

    /// Only while a popup is open: the pointer's moves and clicks, in our windows and in the others.
    private func watch() {
        guard monitors.isEmpty else { return }
        let events: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .rightMouseDown]
        if let global = NSEvent.addGlobalMonitorForEvents(matching: events, handler: { [weak self] event in
            let click = event.type != .mouseMoved
            MainActor.assumeIsolated { self?.pointerMoved(click: click, ours: false) }
        }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: events, handler: { [weak self] event in
            let click = event.type != .mouseMoved
            MainActor.assumeIsolated { self?.pointerMoved(click: click, ours: true) }
            return event
        }) {
            monitors.append(local)
        }
    }

    private func pointerMoved(click: Bool, ours: Bool) {
        let inside = keepArea.contains { $0.contains(NSEvent.mouseLocation) }
        // A click in another app closes it; one of ours outside the box and the popup too (another box was clicked).
        if !inside || (click && !ours) { close() }
    }
}

/// The Apple block at the bar's left edge: the logo on peach, its menu of system actions on click (apple.sh).
struct AppleView: View {
    let runner: CommandRunner

    var body: some View {
        let open = Popups.shared.open == .apple
        let hovered = Hover.shared.box == "apple"
        Text("\u{F8FF}").font(Theme.appleFont).foregroundStyle(Theme.base).offset(y: 0.5)
            .frame(width: 28, height: Theme.pillHeight)
            .background(
                RoundedRectangle(cornerRadius: Theme.pillRadius).fill(
                    open ? Theme.appleOpen : (hovered ? Theme.appleHover : Theme.appleRest)))
            .contentShape(Rectangle())
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { Popups.shared.anchors[.apple] = $0 }
            .onHover { inside in
                if inside {
                    Hover.shared.box = "apple"
                } else if Hover.shared.box == "apple" {
                    Hover.shared.box = nil
                }
            }
            .onTapGesture {
                Popups.shared.toggle(.apple, rows: rows, layout: .apple, align: .left)
            }
    }

    private func rows() -> [MenuRow] {
        AppleMenu.entries.map { entry in
            MenuRow(id: "apple.\(entry.action)", glyph: entry.glyph, color: Color(hex: entry.color), label: entry.label) {
                Popups.shared.close()
                AppleActions.perform(entry.action, runner: runner)
            }
        }
    }
}

/// What the Apple menu's entries do, natively where macOS has an API for it.
enum AppleActions {
    static func perform(_ action: AppleMenu.Action, runner: CommandRunner) {
        switch action {
        case .about:
            // The panel the native Apple menu's first item opens is an app of its own.
            open(URL(fileURLWithPath: "/System/Library/CoreServices/Applications/About This Mac.app"))
        case .settings:
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.systempreferences") {
                open(url)
            }
        case .sleep:
            // No public API puts the Mac to sleep for a user process: pmset, as SketchyBar did, under a time limit.
            Task { _ = await runner.run("/usr/bin/pmset", ["sleepnow"], timeout: 5, key: "pmset") }
        case .lock:
            // The display sleeps and the password is asked when it wakes, as SketchyBar's entry did.
            Task { _ = await runner.run("/usr/bin/pmset", ["displaysleepnow"], timeout: 5, key: "pmset") }
        case .logout:
            loginWindow("rlgo")  // kAEReallyLogOut: logs out as System Events' "log out" did
        case .restart:
            loginWindow("rest")  // kAERestart
        case .shutdown:
            loginWindow("shut")  // kAEShutDown
        }
    }

    private static func open(_ app: URL) {
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// The Apple events loginwindow takes to log out, restart or shut down (Apple's QA1134): what System Events itself
    /// sends, without an osascript process. Sent off the main thread, with a time limit.
    private static func loginWindow(_ code: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let event = NSAppleEventDescriptor(
                eventClass: fourCharCode("aevt"), eventID: fourCharCode(code),
                targetDescriptor: NSAppleEventDescriptor(bundleIdentifier: "com.apple.loginwindow"),
                returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            do {
                _ = try event.sendEvent(options: [.noReply, .canInteract], timeout: 5)
            } catch {
                NSLog("dotbar: loginwindow did not take '%@': %@", code, "\(error)")
            }
        }
    }

    private static func fourCharCode(_ text: String) -> FourCharCode {
        text.utf8.reduce(0) { $0 << 8 | FourCharCode($1) }
    }
}
