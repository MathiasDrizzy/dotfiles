import AppKit
import DotbarCore
import IOKit.ps
import Network
import Observation
import SwiftUI

/// The right side's data, all from the system as it changes: the clock redraws when the minute does, the battery when
/// IOKit says the power source changed, the network when its path changes. Nothing is polled and no process is started.
@MainActor
@Observable
final class StatusModel {
    private(set) var now = Date()
    private(set) var battery: (percent: Int, style: BatteryStyle)?
    private(set) var online = true

    @ObservationIgnored private var minuteTimer: Timer?
    @ObservationIgnored private var powerSource: CFRunLoopSource?
    @ObservationIgnored private let path = NWPathMonitor()

    func start() {
        tick()
        readBattery()
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource(
            { context in
                guard let context else { return }
                let model = Unmanaged<StatusModel>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { model.readBattery() }
            }, context)?.takeRetainedValue()
        {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        path.pathUpdateHandler = { [weak self] update in
            let satisfied = update.status == .satisfied
            Task { @MainActor in self?.online = satisfied }
        }
        path.start(queue: .main)
        // The Mac slept: the clock may be minutes behind and the timer late.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.tick()
                self?.readBattery()
            }
        }
    }

    func stop() {
        minuteTimer?.invalidate()
        path.cancel()
        if let powerSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode) }
    }

    /// Redraws the clock and waits for the next minute exactly.
    private func tick() {
        now = Date()
        minuteTimer?.invalidate()
        let timer = Timer(fire: ClockText.nextMinute(after: now), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
    }

    private func readBattery() {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
            let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                let current = description[kIOPSCurrentCapacityKey] as? Int,
                let maximum = description[kIOPSMaxCapacityKey] as? Int, maximum > 0
            else { continue }
            let percent = Int((Double(current) / Double(maximum) * 100).rounded())
            let onPower = (description[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            battery = (percent, BatteryStyle(percent: percent, onPower: onPower))
            return
        }
    }
}

/// Which box is under the pointer. SwiftUI's @State is a macro whose plugin only ships with Xcode, so the bar keeps view
/// state in observable models instead.
@MainActor
@Observable
final class Hover {
    static let shared = Hover()
    var box: String?
}

/// A box of the bar: solid, 26 points tall with rounded corners, the hover tint under the pointer when it can be clicked
/// (hover.sh).
struct BarBox<Content: View>: View {
    let id: String
    var width: CGFloat?
    var action: (() -> Void)?
    @ViewBuilder var content: Content

    var body: some View {
        let hovered = Hover.shared.box == id && action != nil
        content
            .frame(width: width, height: Theme.pillHeight)
            .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(hovered ? Theme.surface0 : Theme.barColor))
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    Hover.shared.box = id
                } else if Hover.shared.box == id {
                    Hover.shared.box = nil
                }
            }
            .onTapGesture { action?() }
    }
}

/// An icon and a centered label in a box of fixed width, as SketchyBar laid out the clock, date and battery: the icon
/// with 5 points on each side, the label centered in the rest, 5 points before the box's edge.
struct IconLabelBox: View {
    let id: String
    let icon: String
    let iconColor: Color
    let label: String
    var labelFont = Theme.mediumFont
    let width: CGFloat
    var action: (() -> Void)?

    var body: some View {
        BarBox(id: id, width: width, action: action) {
            HStack(spacing: 0) {
                NerdIcon(icon, color: iconColor).padding(.horizontal, 5)
                Text(label).font(labelFont).foregroundStyle(Theme.text).frame(maxWidth: .infinity)
                    .padding(.trailing, 5)
            }
        }
    }
}

/// The right side, left to right: battery, date, time and the Control Center button.
struct StatusView: View {
    let model: StatusModel
    let controlCenter: ControlCenterModel

    var body: some View {
        HStack(spacing: Theme.pillGap) {
            if let battery = model.battery {
                IconLabelBox(
                    id: "battery", icon: battery.style.glyph, iconColor: Color(hex: battery.style.color), label: "\(battery.percent)%",
                    width: 65,
                    action: { open("x-apple.systempreferences:com.apple.Battery-Settings.extension") })
            }
            IconLabelBox(
                id: "date", icon: "\u{F00F0}", iconColor: Theme.red, label: ClockText.date(model.now), width: 108,
                action: { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app")) })
            IconLabelBox(
                id: "clock", icon: "\u{F0954}", iconColor: Theme.yellow, label: ClockText.time(model.now), labelFont: Theme.textFont,
                width: 71)
            // Red while there is no network: what control.sh showed for a Wi-Fi without an address. AppGlyph centers the
            // ligature's ink as SketchyBar did (a Text centers its advance, 3.5 points off).
            BarBox(id: "control", width: 28, action: { controlCenter.click() }) {
                AppGlyph(glyph: ":widget:", color: model.online ? Theme.mauve : Theme.red)
            }
        }
    }

    private func open(_ url: String) {
        if let url = URL(string: url) { NSWorkspace.shared.open(url) }
    }
}

/// A Nerd Font glyph is wider than its character, and SwiftUI cuts a text at its character's edge: a space after the
/// glyph, in the same text, gives it the room to be drawn whole. Centered in the width an icon takes.
struct NerdIcon: View {
    let glyph: String
    let color: Color
    var font = Theme.iconFont

    init(_ glyph: String, color: Color, font: Font = Theme.iconFont) {
        self.glyph = glyph
        self.color = color
        self.font = font
    }

    var body: some View {
        Text(glyph + " ").font(font).foregroundStyle(color).fixedSize()
            .offset(x: Theme.iconWidth / 4)
            .frame(width: Theme.iconWidth)
    }
}
