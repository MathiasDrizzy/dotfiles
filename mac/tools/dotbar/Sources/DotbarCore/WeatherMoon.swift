import Foundation

extension MoonPhase {
    /// When the phase shown changes next, so the moon box is redrawn then instead of every hour. A phase is the age
    /// rounded to an eighth of the month, so it changes halfway between two eighths: at (k + 0.5) / 8 of the month.
    public static func nextChange(after date: Date) -> Date {
        let eighth = synodicMonth / 8 * 86_400
        let seconds = date.timeIntervalSince(knownNewMoon)
        let steps = ((seconds - eighth / 2) / eighth).rounded(.down) + 1
        return knownNewMoon.addingTimeInterval(steps * eighth + eighth / 2)
    }
}
