// The Vorssaint box (vorssaint.sh): where the box goes so its center sits over Vorssaint's menu bar extra, and the driver
// that makes the extra's popover match the clicks.
import CoreGraphics
import DotbarCore

func vorssaintTests() async {
    alignTests()
    driverTests()
}

private func alignTests() {
    // Live on the MacBook: the extra at 1100, 44 wide; the box at its least spread starts at 1150.
    let extra = CGRect(x: 1100, y: 4, width: 44, height: 24)
    check(
        "the labels right of the box widen so its center sits over the extra's",
        VorssaintAlign.spread(extra: extra, boxLeft: 1150, currentSpread: 0) == 42)
    check(
        "the spread they already have counts: the same extra asks for the same spread",
        VorssaintAlign.spread(extra: extra, boxLeft: 1113, currentSpread: 37) == 42)
    check(
        "an extra right of where the box naturally goes leaves them at their least widths",
        VorssaintAlign.spread(extra: CGRect(x: 1200, y: 4, width: 44, height: 24), boxLeft: 1150, currentSpread: 0) == 0)
    check(
        "an extra far to the left never widens them past the cap",
        VorssaintAlign.spread(extra: CGRect(x: 200, y: 4, width: 44, height: 24), boxLeft: 1150, currentSpread: 0)
            == VorssaintAlign.maxSpread)
    check("the spread is shared evenly", VorssaintAlign.shares(42) == [14, 14, 14])
    check("the battery takes what does not divide", VorssaintAlign.shares(37) == [13, 12, 12], "\(VorssaintAlign.shares(37))")
    check("no spread, no widening", VorssaintAlign.shares(0) == [0, 0, 0])
}

/// Runs the driver against a menu whose visibility the closure decides from the poll number; returns every action taken
/// with its poll, the last being `finish`.
private func drive(
    _ driver: inout VorssaintDriver, clicks: Set<Int> = [], limit: Int = 100, visible: (Int) -> Bool
) -> [(poll: Int, action: VorssaintDriver.Action)] {
    var actions: [(Int, VorssaintDriver.Action)] = []
    for poll in 0..<limit {
        if clicks.contains(poll) { driver.click() }
        let action = driver.poll(visible: visible(poll))
        if action != .none { actions.append((poll, action)) }
        if action == .finish { break }
    }
    return actions
}

private func driverTests() {
    // A closed menu and one click: one press, then it is the user's once it shows and stays still.
    var opening = VorssaintDriver(visible: false, sawMenuAtPress: false)
    let opened = drive(&opening) { $0 >= 2 }
    check(
        "a click on a closed menu presses the extra once and lets go once it shows",
        opened.map(\.action) == [.press, .finish] && opened[0].poll == 0 && opened[1].poll == 5, "\(opened)")
    check("its intent is open", opening.intent == .open)

    // An open menu: closed with a click outside, never with a press.
    var closing = VorssaintDriver(visible: true, sawMenuAtPress: false)
    let closed = drive(&closing) { $0 < 2 }
    check(
        "a click on an open menu closes it with a click outside and ends once it stays closed",
        closed.map(\.action) == [.dismiss, .finish], "\(closed)")

    // The click on the bar already started closing it: the menu reads closed, but it was open at the press.
    var already = VorssaintDriver(visible: false, sawMenuAtPress: true)
    let left = drive(&already) { _ in false }
    check("a menu open at the press is not opened again", left.map(\.action) == [.finish], "\(left)")

    // Two fast clicks: open then closed again before the first press goes out.
    var twice = VorssaintDriver(visible: false, sawMenuAtPress: false)
    let none = drive(&twice, clicks: [0]) { _ in false }
    check("a double click on a closed menu ends with it closed and nothing pressed", none.map(\.action) == [.finish], "\(none)")

    // A click while the menu is opening flips what is wanted: the press is not repeated, it is closed once it shows.
    var flipped = VorssaintDriver(visible: false, sawMenuAtPress: false)
    let back = drive(&flipped, clicks: [1]) { $0 >= 3 && $0 < 9 }
    check(
        "a click while it opens closes it once it has shown",
        back.map(\.action) == [.press, .dismiss, .finish] && flipped.intent == .closed, "\(back)")

    // A menu that never shows: two presses, then it gives up.
    var stuck = VorssaintDriver(visible: false, sawMenuAtPress: false)
    let gaveUp = drive(&stuck) { _ in false }
    check(
        "a menu that does not open gets two presses and no more",
        gaveUp.map(\.action) == [.press, .press, .finish] && stuck.intent == .closed, "\(gaveUp)")

    // A menu that does not close: two clicks outside, then it is taken as open.
    var sticky = VorssaintDriver(visible: true, sawMenuAtPress: false)
    let kept = drive(&sticky) { _ in true }
    check(
        "a menu that does not close gets two clicks outside and is taken as open",
        kept.map(\.action) == [.dismiss, .dismiss, .finish] && sticky.intent == .open, "\(kept)")

    // Closed elsewhere while it was still settling: taken as closed, nothing pressed again.
    var elsewhere = VorssaintDriver(visible: false, sawMenuAtPress: false)
    let gone = drive(&elsewhere) { $0 == 2 }
    check(
        "a menu closed elsewhere is not opened again",
        gone.map(\.action) == [.press, .finish] && elsewhere.intent == .closed, "\(gone)")

    // A menu that blinks forever never settles: the driver still ends.
    var blinking = VorssaintDriver(visible: false, sawMenuAtPress: false)
    let ended = drive(&blinking, clicks: Set(stride(from: 0, to: 2000, by: 2)), limit: 2000) { $0 % 2 == 0 }
    let last = ended.last
    check(
        "the driver always ends", last?.action == .finish && (last?.poll ?? .max) <= VorssaintDriver.maxPolls,
        "\(last.map { "\($0)" } ?? "none")")
}
