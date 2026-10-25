// stay.sh's rule: back to a workspace whose last window closed, unless the user asked for the switch.
import DotbarCore
import Foundation

func stayTests() async {
    let start = Date(timeIntervalSince1970: 1_000_000)
    func at(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }

    var rule = StayRule()
    _ = rule.handle(.focus(workspace: "2", hasWindow: true), at: at(0))
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(1))
    check(
        "the last window closed and macOS took the focus elsewhere: back to the workspace",
        rule.handle(.workspace(previous: "2"), at: at(1.5)) == .returnIfEmpty("2"))

    rule = StayRule()
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(1))
    check("too late: not taken back", rule.handle(.workspace(previous: "2"), at: at(5)) == .none)

    rule = StayRule()
    _ = rule.handle(.binding, at: at(1))
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(1.2))
    check("a key binding asked for the switch: left alone", rule.handle(.workspace(previous: "2"), at: at(1.4)) == .none)

    rule = StayRule()
    rule.asked(at: at(1))
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(1.1))
    check("a click on the bar asked for it: left alone", rule.handle(.workspace(previous: "2"), at: at(1.3)) == .none)

    rule = StayRule()
    rule.swapping = true
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(1))
    check("a drag swap is moving windows: left alone", rule.handle(.workspace(previous: "2"), at: at(1.2)) == .none)

    rule = StayRule()
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(0))
    _ = rule.handle(.workspace(previous: "9"), at: at(0.5))
    _ = rule.handle(.focus(workspace: "2", hasWindow: false), at: at(10))
    check("a workspace already empty (its bare desktop clicked) is not a window closing",
        rule.handle(.workspace(previous: "2"), at: at(10.5)) == .none)

    rule = StayRule()
    _ = rule.handle(.focus(workspace: StayRule.park, hasWindow: false), at: at(1))
    check("the swap's parking workspace is never returned to", rule.handle(.workspace(previous: StayRule.park), at: at(1.2)) == .none)

    check("a key binding event is read", StayEvent.parse(#"{"_event":"binding-triggered","binding":"alt-1"}"#) == .binding)
    check(
        "a focus event without a window is read",
        StayEvent.parse(#"{"_event":"focus-changed","workspace":"3"}"#) == .focus(workspace: "3", hasWindow: false))
    check(
        "a workspace change names the one left",
        StayEvent.parse(#"{"_event":"focused-workspace-changed","prevWorkspace":"3","workspace":"2"}"#)
            == .workspace(previous: "3"))
}
