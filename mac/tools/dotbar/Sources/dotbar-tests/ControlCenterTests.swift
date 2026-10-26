// The Control Center button (controlcenter.sh) and the cover (cover.sh): what a click asks for, how the driver presses fn+C
// as few times as it can and never mid-animation, when the cover may come off, and which part of the wallpaper it shows.
import CoreGraphics
import DotbarCore
import Foundation

/// Runs the driver against a panel that follows the keys after `delay` polls, as Control Center does, and returns how
/// many keys went out, whether the panel ended open and how many polls it took.
private func drive(
    clicks: [Int: PanelIntent] = [:], opensAfter delay: Int = 3, opens: Bool = true, closeElsewhereAt: Int? = nil,
    pointerAtTop: (Int) -> Bool = { _ in false }
) -> (keys: Int, open: Bool, polls: Int, finished: Bool) {
    var intent = ControlCenterIntent()
    intent.set(.open)
    var driver = ControlCenterDriver(handled: intent.serial)
    var visible = false
    var pending: Int?  // the poll at which the last key takes effect
    var keys = 0
    for poll in 0..<ControlCenterDriver.Timing().maxPolls + 5 {
        if let want = clicks[poll] { intent.set(want) }
        if let due = pending, poll >= due {
            visible.toggle()
            pending = nil
        }
        if poll == closeElsewhereAt { visible = false }
        var step = driver.step(want: intent.want, serial: intent.serial, visible: visible, pointerAtTop: pointerAtTop(poll))
        while step == .wantClosed {
            intent.set(.closed)
            step = driver.step(want: intent.want, serial: intent.serial, visible: visible, pointerAtTop: pointerAtTop(poll))
        }
        switch step {
        case .pressKey:
            keys += 1
            if opens || visible { pending = poll + delay }
        case .finish: return (keys, visible, poll, true)
        default: break
        }
    }
    return (keys, visible, -1, false)
}

func controlCenterTests() async {
    // A click while no driver runs.
    check(
        "a click with the panel closed starts the driver",
        ControlCenterClick.decide(driving: false, pressClosedPanel: false, wanted: .closed, visible: false) == .drive)
    check(
        "a click on a panel opened with fn+C closes it with one key",
        ControlCenterClick.decide(driving: false, pressClosedPanel: false, wanted: .closed, visible: true) == .pressOnce)
    check(
        "a click whose press already closed the panel does nothing more",
        ControlCenterClick.decide(driving: false, pressClosedPanel: true, wanted: .closed, visible: true) == .nothing)
    // A click while the driver runs only changes what is wanted.
    check(
        "a click during an opening asks for it closed",
        ControlCenterClick.decide(driving: true, pressClosedPanel: false, wanted: .open, visible: false) == .want(.closed))
    check(
        "a click during a closing asks for it open again",
        ControlCenterClick.decide(driving: true, pressClosedPanel: false, wanted: .closed, visible: false) == .want(.open))
    check(
        "a click whose press closed the panel asks for it closed",
        ControlCenterClick.decide(driving: true, pressClosedPanel: true, wanted: .closed, visible: false) == .want(.closed))

    // The panel's state at the press counts for two seconds, once.
    let now = Date()
    var press: PanelPress? = PanelPress(open: true, at: now)
    check("an open panel at the press closed it", PanelPress.take(&press, now: now.addingTimeInterval(1)))
    check("and counts once", !PanelPress.take(&press, now: now.addingTimeInterval(1)))
    press = PanelPress(open: true, at: now)
    check("a press older than two seconds does not count", !PanelPress.take(&press, now: now.addingTimeInterval(2.5)))
    press = PanelPress(open: false, at: now)
    check("a closed panel at the press does not count", !PanelPress.take(&press, now: now))

    var intent = ControlCenterIntent()
    let first = intent.serial
    intent.set(.open)
    intent.set(.open)
    check("every change of intent gets a new serial", intent.want == .open && intent.serial == first + 2)

    // The driver.
    let single = drive()
    check("one click opens the panel with one key and lets go once it settles", single == (1, true, single.polls, true), "\(single)")
    check("it lets go only after the panel looked the same for four polls", single.polls >= 3 + 4, "\(single)")
    let double = drive(clicks: [1: .closed])
    check("a fast second click closes it with one more key, sent once the panel settled", double.keys == 2 && !double.open && double.finished, "\(double)")
    let triple = drive(clicks: [1: .closed, 2: .open])
    check("three fast clicks end open with a single key", triple.keys == 1 && triple.open, "\(triple)")
    let never = drive(opens: false)
    check("a panel that never opens gets two keys, then the driver gives up", never.keys == 2 && !never.open && never.finished, "\(never)")
    let elsewhere = drive(opensAfter: 1, closeElsewhereAt: 2)
    check("a panel closed elsewhere before it settled ends the driver without a key", elsewhere.keys == 1 && !elsewhere.open && elsewhere.finished, "\(elsewhere)")
    let held = drive(clicks: [1: .closed], pointerAtTop: { $0 < 40 })
    check("closed, it waits for the pointer to leave the top before letting go", held.finished && held.polls >= 40 + 5, "\(held)")
    var stuck = ControlCenterDriver(handled: 0)
    var last = ControlCenterDriver.Step.wait
    for _ in 0...ControlCenterDriver.Timing().maxPolls {
        last = stuck.step(want: .closed, serial: 0, visible: false, pointerAtTop: true)
        if last == .finish { break }
    }
    check("it gives up after two minutes", last == .finish)

    // Which windows are an open panel or menu.
    let windows = [
        PopupWindows.Window(pid: 10, layer: 0, height: 900),  // a normal window
        PopupWindows.Window(pid: 11, layer: 25, height: 24),  // its menu bar item
        PopupWindows.Window(pid: 12, layer: 101, height: 400),  // another app's menu
    ]
    check("a normal window is not a panel", !PopupWindows.isOpen(windows, owners: [10]))
    check("a menu bar item is not a panel", !PopupWindows.isOpen(windows, owners: [11]))
    check("a window above the normal level, taller than the menu bar, is", PopupWindows.isOpen(windows, owners: [12]))

    // The top strip is on the Mac's own screen, even with a monitor above it.
    let main = CGRect(x: 0, y: 0, width: 1470, height: 956)
    check("the pointer at y 0 is at the top", TopStrip.contains(CGPoint(x: 700, y: 0), mainDisplay: main))
    check("39 points down too", TopStrip.contains(CGPoint(x: 700, y: 39), mainDisplay: main))
    check("40 points down is not", !TopStrip.contains(CGPoint(x: 700, y: 40), mainDisplay: main))
    check(
        "the cover waits for the pointer to stay at the top, less than the quarter second macOS waits to reveal its bar",
        TopStrip.coverDelay > 0 && TopStrip.coverDelay < 0.25)
    check("a monitor above is not", !TopStrip.contains(CGPoint(x: 700, y: -10), mainDisplay: main))

    // The cover comes off once nothing has needed it for three checks.
    var settle = CoverSettle()
    check("needed: it stays", !settle.check(needed: true))
    check("one idle check: it stays", !settle.check(needed: false))
    check("needed again starts over", !settle.check(needed: true) && !settle.check(needed: false) && !settle.check(needed: false))
    check("the third idle check in a row lets it go", settle.check(needed: false))
    var endless = CoverSettle()
    var ended = false
    for _ in 0..<CoverSettle.maxChecks { ended = endless.check(needed: true) }
    check("it stops waiting after two minutes", ended)

    // The wallpaper strip: the part of the picture the desktop shows behind the bar.
    let screen = CGSize(width: 1470, height: 956)
    let fill = WallpaperStrip.placement(image: CGSize(width: 3840, height: 2160), screen: screen, scaling: .fill)
    check(
        "fill: a wide picture covers the height and is cut at the sides",
        abs(fill.height - 956) < 0.01 && abs(fill.width - 1699.56) < 0.01 && abs(fill.minX + 114.78) < 0.01 && fill.minY == 0,
        "\(fill)")
    let fit = WallpaperStrip.placement(image: CGSize(width: 3840, height: 2160), screen: screen, scaling: .fit)
    check(
        "fit: it covers the width, centered with bands above and below",
        abs(fit.width - 1470) < 0.01 && abs(fit.minY - (956 - 826.875) / 2) < 0.01, "\(fit)")
    check(
        "stretch: the whole screen",
        WallpaperStrip.placement(image: CGSize(width: 100, height: 100), screen: screen, scaling: .stretch)
            == CGRect(origin: .zero, size: screen))
    check(
        "center: at its own size",
        WallpaperStrip.placement(image: CGSize(width: 470, height: 56), screen: screen, scaling: .center)
            == CGRect(x: 500, y: 450, width: 470, height: 56))
    check("NSImageScaling 3 with clipping is fill", WallpaperScaling(scaling: 3, allowClipping: true) == .fill)
    check("without clipping it is fit", WallpaperScaling(scaling: 3, allowClipping: false) == .fit)
    check("1 is stretch, 2 is center", WallpaperScaling(scaling: 1, allowClipping: true) == .stretch && WallpaperScaling(scaling: 2, allowClipping: true) == .center)

    let strip = CGRect(x: 0, y: 0, width: 1470, height: 40)
    let piece = WallpaperStrip.crop(placement: fill, pixels: CGSize(width: 3840, height: 2160), strip: strip)
    check(
        "the bar's strip of a filled picture is its top 90 pixels, without the cut sides",
        piece.map { abs($0.source.minX - 259.31) < 0.1 && $0.source.minY == 0 && abs($0.source.height - 90.38) < 0.1 && $0.destination == strip } ?? false,
        "\(String(describing: piece))")
    let banded = WallpaperStrip.crop(placement: fit, pixels: CGSize(width: 3840, height: 2160), strip: strip)
    check("a fitted picture leaves the strip to the fill color", banded == nil, "\(String(describing: banded))")
    let bottom = WallpaperStrip.crop(
        placement: fill, pixels: CGSize(width: 3840, height: 2160), strip: CGRect(x: 0, y: 916, width: 1470, height: 40))
    check(
        "at the bottom it is the picture's last 90 pixels",
        bottom.map { abs($0.source.maxY - 2160) < 0.1 && $0.destination.minY == 0 } ?? false, "\(String(describing: bottom))")

    // The shade macOS draws over the top of the desktop, measured against the wallpaper file: the cover draws it too.
    check("the shade is darkest at the screen's top edge", abs(MenuBarShade.darkening(at: 0) - 0.22) < 0.005)
    check("...a twentieth at 10 points down", abs(MenuBarShade.darkening(at: 10) - 0.046) < 0.005, "\(MenuBarShade.darkening(at: 10))")
    check("...and nothing from 18 points down", MenuBarShade.darkening(at: 18) == 0 && MenuBarShade.darkening(at: 39.5) == 0)
    check(
        "it only lightens going down",
        stride(from: 0.0, to: 18, by: 0.25).allSatisfy { MenuBarShade.darkening(at: $0) >= MenuBarShade.darkening(at: $0 + 0.25) })
    check("a bar at the bottom of the screen gets none", MenuBarShade.darkening(at: 916) == 0)
}
