import AppKit
import DotbarCore
import Observation
import SwiftUI

/// The moon box's phase, worked out here (moon.sh's arithmetic in MoonPhase) and redrawn when it changes, about every
/// 3.7 days, and on wake (a timer is late after a sleep). No tick, no process.
@MainActor
@Observable
final class MoonModel {
    private(set) var phase = MoonPhase.index(at: Date())

    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wake: NSObjectProtocol?

    func start() {
        update()
        wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
    }

    func stop() {
        timer?.invalidate()
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
    }

    private func update() {
        let now = Date()
        phase = MoonPhase.index(at: now)
        timer?.invalidate()
        // A second past the boundary, so the phase read then is the new one.
        let timer = Timer(fire: MoonPhase.nextChange(after: now).addingTimeInterval(1), interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.update() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

extension Theme {
    /// MOON_SIZE of icons.sh, Bold.
    static let moonFont = Font.custom(fontName, size: 22).bold()
}

/// The moon box (sketchybarrc's weather.moon): the phase's glyph in the light ink, 4 points from the box's left edge,
/// in a box 25 points wide.
struct MoonView: View {
    let model: MoonModel

    var body: some View {
        BarBox(id: "weather.moon", width: 25) {
            Text(MoonPhase.glyphs[model.phase] + " ").font(Theme.moonFont).foregroundStyle(Theme.text).fixedSize()
                .padding(.leading, 4)
                .frame(width: 25, alignment: .leading)
        }
    }
}
