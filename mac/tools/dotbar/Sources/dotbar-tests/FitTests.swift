// The fit (fit.sh's rules): the gap around the camera housing, what narrows on the left, the track's budget on the right.
import CoreGraphics
import DotbarCore

func fitTests() async {
    let built = BarFit.notch(screenWidth: 1470, hasNotch: true)
    check("on the MacBook's screen the gap is SketchyBar's: 623 to 847", built.left == 623 && built.right == 847, "\(built)")
    let flat = BarFit.notch(screenWidth: 2560, hasNotch: false)
    check("a screen without a housing has no gap", flat.left == 1280 && flat.right == 1280)

    check("with room to spare nothing narrows", BarFit.left(room: 300, natural: 3) == .init(nameWidth: 72, cap: nil))
    let narrower = BarFit.left(room: 72 + 84 - 30, natural: 3)
    check("short of room the name narrows first", narrower == .init(nameWidth: 42, cap: nil), "\(narrower)")
    let capped = BarFit.left(room: 40 + 28 + 2 * 28 + 5, natural: 6)
    check("past the name's minimum the workspaces leave and the pill says +N", capped == .init(nameWidth: 40, cap: 2), "\(capped)")
    check("at least one workspace always shows", BarFit.left(room: 10, natural: 4).cap == 1)
    check("with no workspace to show there is no cap", BarFit.left(room: 10, natural: 0).cap == nil)
    check("exactly enough room: nothing narrows", BarFit.left(room: 72 + 3 * 28, natural: 3) == .init(nameWidth: 72, cap: nil))
    // SketchyBar's bar on the MacBook: weather box 131 wide, its moon box left edge at 459.
    let room = BarFit.leftRoom(notchLeft: 623, weatherWidth: 131, leftInset: 23, fixedBeforeName: 76, external: false)
    check("the left room is the strip to the moon box less the fixed boxes", room == 459 - 5 - 23 - 76 - 5, "\(room)")
    let withMonitor = BarFit.leftRoom(notchLeft: 623, weatherWidth: 131, leftInset: 23, fixedBeforeName: 76, external: true)
    check("another monitor's pill takes its gap and mark, not a slot per workspace", room - withMonitor == 5 + 28)

    check("between the housing and Vorssaint the track gets 26 characters", BarFit.mediaChars(notchRight: 847, vorssaintLeft: 1113) == 26)
    check("never more than 35", BarFit.mediaChars(notchRight: 847, vorssaintLeft: 2000) == 35)
    check("never fewer than 8", BarFit.mediaChars(notchRight: 847, vorssaintLeft: 900) == 8)
}
