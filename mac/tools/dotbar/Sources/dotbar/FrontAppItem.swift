import AppKit
import ApplicationServices
import DotbarCore
import Observation
import SwiftUI

extension Theme {
    /// The front app's block and its arrow (colors.sh APP_BLOCK).
    static let appBlock = Color(hex: 0xa6da95)
    /// APP_NAME_WIDTH: "Google Chrome" fits; a longer name slides inside it.
    static let appNameWidth: CGFloat = 94
    /// The arrow after the block (pl-right_hard_divider) at ARROW_BLOCK_SIZE: as tall as the block.
    static let arrowFont = Font.custom(fontName, size: 19.5).bold()
    /// The label paddings of front_app.name.
    static let appNamePadLeft: CGFloat = 4
    static let appNamePadRight: CGFloat = 8
}

/// The app in front, from NSWorkspace's activation notification (no polling, no lsappinfo), and its name's slide.
@MainActor
@Observable
final class FrontAppModel {
    private(set) var name = ""
    private(set) var glyph = ":default:"
    /// The name sits at its box's left padding while it slides, centered otherwise.
    private(set) var sliding = false
    private(set) var offset: CGFloat = 0
    /// The name's box: APP_NAME_WIDTH, narrower when the fit needs the room.
    private(set) var nameWidth: CGFloat = Theme.appNameWidth

    func setNameWidth(_ width: CGFloat) {
        guard width != nameWidth else { return }
        nameWidth = width
        generation += 1
        name = ""
        update()  // a name that no longer fits slides inside the new width
    }
    /// The app menus' popup is being filled: a second click meanwhile asks nothing more.
    @ObservationIgnored private var loading = false
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var observer: NSObjectProtocol?
    @ObservationIgnored private let menus = DispatchQueue(label: "dotbar.appmenus")

    private static let nameFont: NSFont = {
        let regular = NSFont(name: Theme.fontName, size: 12) ?? .monospacedSystemFont(ofSize: 12, weight: .regular)
        return NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
    }()

    func start() {
        update()
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        generation += 1
    }

    /// The app in front now, not the one the notification names: a helper that brings Finder forward for a few milliseconds
    /// (stay.sh) sends two notifications, and the last one handled must show the real front app.
    private func update() {
        let front = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
        guard front != name || generation == 0 else { return }
        generation += 1
        name = front
        glyph = IconMap.glyph(for: front)
        offset = 0
        let width = (front as NSString).size(withAttributes: [.font: Self.nameFont]).width
        guard case .slide(let span, let seconds) = NameSlide.plan(textWidth: width, boxWidth: nameWidth) else {
            sliding = false
            return
        }
        sliding = true
        let mine = generation
        Task {
            let started = Date()
            for step in NameSlide.steps(span: span, seconds: seconds) {
                try? await Task.sleep(for: .seconds(max(0, step.at - Date().timeIntervalSince(started))))
                guard mine == generation else { return }  // a newer app came: its own slide runs
                // SketchyBar's sin curve (ease out) as a cubic Bézier.
                withAnimation(.timingCurve(0.61, 1, 0.88, 1, duration: step.seconds)) { offset = step.offset }
            }
        }
    }

    /// A click on the pill: its menus, or closes them (appmenu.sh).
    func toggleMenus() {
        if Popups.shared.open == .front {
            Popups.shared.close()
        } else {
            showTop()
        }
    }

    private func showTop() {
        load({ AXMenuBar.topTitles(pid: $0) }) { [weak self] titles in
            AppMenus.top(titles).enumerated().map { index, title in
                MenuRow(id: "top.\(index)", glyph: "\u{F0142}", color: Theme.blue, label: title) { self?.showMenu(title) }
            }
        }
    }

    private func showMenu(_ menu: String) {
        load({ AXMenuBar.itemTitles(pid: $0, menu: menu) }) { [weak self] titles in
            [MenuRow(id: "back", glyph: "\u{F0141}", color: Theme.blue, label: "Menús") { self?.showTop() }]
                + AppMenus.items(titles).enumerated().map { index, title in
                    MenuRow(id: "item.\(index)", glyph: "", color: Theme.blue, label: title) {
                        Popups.shared.close()
                        self?.press(menu, title)
                    }
                }
        }
    }

    /// Reads the front app's menus off the main thread (the accessibility calls wait on the app, up to their time limit),
    /// then opens the popup with them; the entries replace the old ones in one step.
    private func load(_ read: @escaping @Sendable (pid_t) -> [String?], rows: @escaping ([String?]) -> [MenuRow]) {
        guard !loading, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        guard AXMenuBar.trusted() else { return }
        loading = true
        let queue = menus
        Task {
            let titles = await withCheckedContinuation { done in queue.async { done.resume(returning: read(pid)) } }
            loading = false
            Popups.shared.show(.front, rows: rows(titles), layout: .app, align: .center)
        }
    }

    private func press(_ menu: String, _ item: String) {
        guard let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier else { return }
        menus.async { AXMenuBar.press(pid: pid, menu: menu, item: item) }
    }
}

/// The front app's menu bar through the accessibility API, what appmenu.sh asked System Events for. Every call waits on the
/// app for 2 seconds at most.
enum AXMenuBar {
    @MainActor private static var asked = false

    /// Without the Accessibility permission the menus cannot be read: macOS is asked to offer it, once per run.
    @MainActor static func trusted() -> Bool {
        defer { asked = true }
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": !asked] as CFDictionary)
    }

    private static func application(_ pid: pid_t) -> AXUIElement {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 2)
        return app
    }

    private static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    private static func children(_ element: AXUIElement) -> [AXUIElement] {
        value(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
    }

    private static func title(_ element: AXUIElement) -> String? {
        value(element, kAXTitleAttribute) as? String
    }

    private static func barItems(_ pid: pid_t) -> [AXUIElement] {
        guard let bar = value(application(pid), kAXMenuBarAttribute) else { return [] }
        // The menu bar attribute is always an element: the cast cannot fail.
        return children(bar as! AXUIElement)
    }

    /// The menu's items: the bar item's only child is the menu, whose children are the items.
    private static func items(_ pid: pid_t, _ menu: String) -> [AXUIElement] {
        guard let bar = barItems(pid).first(where: { title($0) == menu }), let list = children(bar).first else { return [] }
        return children(list)
    }

    /// A whole read of titles is over in 3 seconds, each title at most half a second: an app that hangs answers no call,
    /// and one wait per menu made a popup take 20 seconds while every click on the pill was ignored.
    private static let readSeconds: TimeInterval = 3
    private static let titleSeconds: Float = 0.5

    private static func titles(_ elements: [AXUIElement]) -> [String?] {
        let deadline = Date().addingTimeInterval(readSeconds)
        var result: [String?] = []
        for element in elements {
            guard Date() < deadline else { break }
            AXUIElementSetMessagingTimeout(element, titleSeconds)
            result.append(title(element))
        }
        return result
    }

    static func topTitles(pid: pid_t) -> [String?] {
        // The first item is the Apple menu whatever its title says; the bar draws its own.
        titles(Array(barItems(pid).dropFirst()))
    }

    static func itemTitles(pid: pid_t, menu: String) -> [String?] {
        titles(items(pid, menu))
    }

    static func press(pid: pid_t, menu: String, item: String) {
        guard let target = items(pid, menu).first(where: { title($0) == item }) else { return }
        AXUIElementPerformAction(target, kAXPressAction as CFString)
    }
}

/// The front app's pill: the green block with the app's icon and its arrow, then the name in a box of fixed width. Click
/// for the app's menus.
struct FrontAppView: View {
    let model: FrontAppModel

    var body: some View {
        let open = Popups.shared.open == .front
        let hovered = Hover.shared.box == "front_pill"
        // SketchyBar's items, measured on its bar: the block 4 points in, the arrow from 29, the name's box from 42 to 136,
        // 3 points before the pill's end.
        ZStack(alignment: .leading) {
            Text("\u{E0B0} ").font(Theme.arrowFont).foregroundStyle(Theme.appBlock).fixedSize()
                .offset(x: 28.5)
            AppGlyph(glyph: model.glyph, color: Theme.base)
                .frame(width: 28, height: Theme.pillHeight)
                .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.appBlock))
                .offset(x: 4)
            name.frame(width: model.nameWidth, alignment: .leading).clipped().offset(x: 42)
        }
        // 45 points of block and arrow before the name's box.
        .frame(width: 45 + model.nameWidth, height: Theme.pillHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.pillRadius).fill(
                open ? Theme.surface1 : (hovered ? Theme.surface0 : Theme.barColor))
        )
        .contentShape(Rectangle())
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { Popups.shared.anchors[.front] = $0 }
        .onHover { inside in
            if inside {
                Hover.shared.box = "front_pill"
            } else if Hover.shared.box == "front_pill" {
                Hover.shared.box = nil
            }
        }
        .onTapGesture { model.toggleMenus() }
    }

    /// Centered between the paddings while it fits; at the left padding, moved by the slide, while it does not.
    @ViewBuilder private var name: some View {
        // SketchyBar set its labels a point lower than SwiftUI centers them.
        let text = Text(model.name).font(Theme.textFont).foregroundStyle(Theme.text).fixedSize().offset(y: 1)
        if model.sliding {
            text.padding(.leading, Theme.appNamePadLeft).offset(x: model.offset)
        } else {
            text.frame(width: model.nameWidth - Theme.appNamePadLeft - Theme.appNamePadRight)
                .padding(.leading, Theme.appNamePadLeft)
        }
    }
}

/// An app glyph of sketchybar-app-font, centered by its ink as SketchyBar centered it: the ligature's advance is wider than
/// its drawing and starts with it, so centering the text drew every icon a few points left.
struct AppGlyph: View {
    let glyph: String
    let color: Color

    @MainActor private static var shifts: [String: CGFloat] = [:]

    var body: some View {
        Text(glyph).font(Theme.appIconFont).foregroundStyle(color).fixedSize().offset(x: Self.shift(glyph))
    }

    /// From the text's center to its ink's center.
    @MainActor private static func shift(_ glyph: String) -> CGFloat {
        if let known = shifts[glyph] { return known }
        guard let font = NSFont(name: "sketchybar-app-font", size: 15) else { return 0 }
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: glyph, attributes: [.font: font]))
        let shift = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil)) / 2 - CTLineGetImageBounds(line, nil).midX
        shifts[glyph] = shift
        return shift
    }
}
