// The core's checks: the bar's frame, the command runner, the workspaces, the stream, the status items.
import CoreGraphics
import DotbarCore
import Foundation

func coreTests() async {
    // The bar's frame.
    let screen = CGRect(x: 0, y: 0, width: 1470, height: 956)
    check(
        "the bar spans the top of the screen, 40 points tall",
        BarGeometry.frame(on: screen, edge: .top) == CGRect(x: 0, y: 916, width: 1470, height: 40))
    check(
        "in development it sits at the bottom",
        BarGeometry.frame(on: screen, edge: .bottom) == CGRect(x: 0, y: 0, width: 1470, height: 40))
    let second = CGRect(x: 1470, y: -200, width: 2560, height: 1440)
    check(
        "on another screen it follows that screen's frame",
        BarGeometry.frame(on: second, edge: .top) == CGRect(x: 1470, y: 1200, width: 2560, height: 40))

    // The command runner.
    let runner = CommandRunner()
    let echo = await runner.run("/bin/echo", ["hello"], timeout: 2)
    check("a command's output is read", echo.stdout == "hello\n" && echo.status == 0 && !echo.timedOut, "\(echo)")

    let missing = await runner.run("/nonexistent/command", timeout: 2)
    check("a command that does not exist fails at once", missing.status == 127, "\(missing)")

    // A hung command: a duration no other process has, so the check sees only this one.
    let hang = "3000\(getpid())"
    let started = Date()
    let hung = await runner.run("/bin/sleep", [hang], timeout: 0.5)
    let took = Date().timeIntervalSince(started)
    check("a hung command is ended by its time limit", hung.timedOut && took < 2, "took \(took) s, \(hung)")
    check("...and nothing of it is left running", running("sleep \(hang)") == 0, "\(running("sleep \(hang)")) left")

    // Five callers at once under one key while the command runs: one process, one shared answer.
    let shared = CommandRunner()
    let answers = await withTaskGroup(of: CommandRunner.Output.self) { group in
        for _ in 0..<5 {
            group.addTask { await shared.run("/bin/sh", ["-c", "sleep 0.3; echo once"], timeout: 2, key: "same") }
        }
        var all: [CommandRunner.Output] = []
        for await answer in group { all.append(answer) }
        return all
    }
    let launchesWhileRunning = await shared.launchCount
    check("callers that ask while it runs share one process", launchesWhileRunning == 1, "\(launchesWhileRunning)")
    check("...and all get its answer", answers.count == 5 && answers.allSatisfy { $0.stdout == "once\n" })

    let later = await shared.run("/bin/sh", ["-c", "echo again"], timeout: 2, key: "same")
    let launchesAfter = await shared.launchCount
    check("once it finished, the key runs again", later.stdout == "again\n" && launchesAfter == 2)

    // Workspaces: what AeroSpace reports, then which pills show and how.
    func row(_ id: String, _ monitor: Int = 1, visible: Bool = false, focused: Bool = false) -> WorkspaceRow {
        WorkspaceRow(id: id, monitor: monitor, visible: visible || focused, focused: focused)
    }
    func ids(_ pills: [Pill]) -> [String] { pills.map(\.id) }

    check(
        "AeroSpace's workspace list is read",
        Workspaces.parseRows("1|1|true|true\n2|1|false|false\ne1|2|true|false\n")
            == [row("1", focused: true), row("2"), row("e1", 2, visible: true)])
    check("lines that are not a workspace are skipped", Workspaces.parseRows("garbage\n|1|true|true\n").isEmpty)
    check("the occupied workspaces are read", Workspaces.parseOccupied("1\n2\n2\n\n") == ["1", "2"])

    var bar = Workspaces.layout(rows: [row("1", focused: true), row("2"), row("3")], occupied: ["1", "2"])
    check("the focused and occupied workspaces show, an empty one does not", ids(bar.mac) == ["1", "2"] && bar.external.isEmpty)
    check("the focused one is drawn as focused", bar.mac.first?.state == .focused && bar.mac.last?.state == .plain)

    bar = Workspaces.layout(rows: [row("1", focused: true), row("e1", 2, visible: true), row("e2", 2)], occupied: [])
    check(
        "the other monitor's visible workspace shows in its own pill, eN drawn as N",
        ids(bar.external) == ["e1"] && bar.external.first?.label == "1" && bar.external.first?.state == .visible)

    bar = Workspaces.layout(rows: [row("1", focused: true), row("e1")], occupied: ["e1"])
    check("once the monitor is unplugged its workspaces leave the bar, windows or not", ids(bar.mac) == ["1"])
    bar = Workspaces.layout(rows: [row("1"), row("e1", focused: true)], occupied: [])
    check("...unless one of them has the focus", ids(bar.mac) == ["e1"])

    let crowded = [row("1", focused: true), row("2"), row("5"), row("6"), row("e1", 2, visible: true), row("e2", 2)]
    bar = Workspaces.layout(rows: crowded, occupied: ["2", "5", "6", "e2"], cap: 3)
    check(
        "over the cap the group with more optional workspaces gives them up, the Mac's on a tie",
        ids(bar.mac) == ["1"] && ids(bar.external) == ["e1", "e2"] && bar.hiddenMac == 3 && bar.hiddenExternal == 0,
        "mac \(ids(bar.mac)) ext \(ids(bar.external)) hidden \(bar.hiddenMac)/\(bar.hiddenExternal)")
    bar = Workspaces.layout(rows: [row("1", focused: true), row("e1", 2, visible: true)], occupied: [], cap: 1)
    check("the focused and visible workspaces always stay", ids(bar.mac) == ["1"] && ids(bar.external) == ["e1"])

    check(
        "a workspace switch is read from the event stream",
        AeroSpaceEvent.parse(#"{"_event":"focused-workspace-changed","prevWorkspace":"3","workspace":"2"}"#)
            == .focusedWorkspace("2"))
    check("other events are told apart", AeroSpaceEvent.parse(#"{"_event":"mode-changed","mode":"main"}"#) == .other)
    check("a line that is not an event is ignored", AeroSpaceEvent.parse("not json") == nil)

    // A long-lived stream: lines arrive one by one, and it starts again when the command ends.
    final class Lines: @unchecked Sendable {
        let lock = NSLock()
        var all: [String] = []
    }
    let received = Lines()
    let stream = LineStream("/bin/sh", ["-c", "echo one; echo two"], restartDelay: 0.2) { line in
        received.lock.withLock { received.all.append(line) }
    }
    stream.start()
    try? await Task.sleep(for: .seconds(1))
    stream.stop()
    let got = received.lock.withLock { received.all }
    check("a stream's lines are read one by one", Array(got.prefix(2)) == ["one", "two"], "\(got)")
    check("a stream that ends is started again", stream.starts >= 2, "\(stream.starts) starts")
    let startsAtStop = stream.starts
    try? await Task.sleep(for: .seconds(0.6))
    check("a stopped stream stays stopped", stream.starts == startsAtStop)

    // A look at the workspaces that started before a switch must not paint the old focus back.
    var state = WorkspaceState()
    state.apply(rows: [row("1", focused: true), row("2")], occupied: ["1", "2"], startedAt: state.generation)
    let lookStartedAt = state.generation
    state.focus("2")
    let staleTaken = state.apply(rows: [row("1", focused: true), row("2")], occupied: ["1", "2"], startedAt: lookStartedAt)
    check("a look that started before a switch is dropped", !staleTaken && state.bar.mac.first(where: { $0.state == .focused })?.id == "2")
    let burstStartedAt = state.generation
    state.focus("1")
    state.apply(rows: [row("1", focused: true), row("2")], occupied: ["1", "2", "3"], startedAt: burstStartedAt)
    check("...but which workspaces hold windows is taken even then", state.occupied == ["1", "2", "3"])
    state.focus("2")
    let freshTaken = state.apply(rows: [row("1"), row("2", focused: true), row("3")], occupied: ["1", "2", "3"], startedAt: state.generation)
    check("...and the next one is taken", freshTaken && ids(state.bar.mac) == ["1", "2", "3"])
    check("a look AeroSpace did not answer keeps what is known", state.apply(rows: nil, occupied: nil, startedAt: state.generation) && ids(state.bar.mac) == ["1", "2", "3"])

    // A command that started others: on its time limit, they all end.
    let family = "3001\(getpid())"
    let familyStart = Date()
    let shell = await runner.run("/bin/sh", ["-c", "sleep \(family) & wait"], timeout: 0.5)
    check("a hung command and the processes it started all end at its limit", shell.timedOut && running("sleep \(family)") == 0,
        "\(running("sleep \(family)")) left after \(Date().timeIntervalSince(familyStart)) s")

    // A command that leaves a child holding its output open: the bar does not wait for that child.
    let orphan = "3002\(getpid())"
    let orphanStart = Date()
    let quick = await runner.run("/bin/sh", ["-c", "echo done; sleep \(orphan) &"], timeout: 5)
    let orphanTook = Date().timeIntervalSince(orphanStart)
    check("a child left holding the output open does not hold the bar", quick.stdout == "done\n" && orphanTook < 2, "took \(orphanTook) s")
    let cleanup = Process()
    cleanup.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
    cleanup.arguments = ["-f", "sleep \(orphan)$"]
    try? cleanup.run()
    cleanup.waitUntilExit()

    // A stream started twice, or stopped and started at once, runs one process.
    let once = LineStream("/bin/sleep", ["3003\(getpid())"], restartDelay: 0.2) { _ in }
    let streamed = "sleep 3003\(getpid())"
    once.start()
    once.start()
    _ = await waitUntil(3) { running(streamed) == 1 }
    try? await Task.sleep(for: .seconds(0.3))  // room for a second process, if one were coming
    check("a stream started twice runs one process", running(streamed) == 1 && once.starts == 1)
    once.stop()
    once.start()
    // The old process ends and the new one starts: wait for exactly one, then make sure it stays one.
    let one = await waitUntil(3) { running(streamed) == 1 && once.starts == 2 }
    try? await Task.sleep(for: .seconds(0.4))
    check("stopped and started at once, it still runs one", one && running(streamed) == 1, "\(running(streamed))")
    once.stop()
    check("stopped, nothing of it runs", await waitUntil(3) { running(streamed) == 0 })

    // The battery box: battery.sh's levels and colors.
    check("80% and up is full and green", BatteryStyle(percent: 80, onPower: false) == .full && BatteryStyle.full.color == 0xa6da95)
    check("70-79% is three quarters", BatteryStyle(percent: 79, onPower: false) == .threeQuarters)
    check("40-69% is half and peach", BatteryStyle(percent: 40, onPower: false) == .half && BatteryStyle.half.color == 0xf5a97f)
    check("10-39% is a quarter", BatteryStyle(percent: 10, onPower: false) == .quarter)
    check("under 10% is empty and red", BatteryStyle(percent: 9, onPower: false) == .empty && BatteryStyle.empty.color == 0xed8796)
    check("on power it is the yellow bolt, whatever the level", BatteryStyle(percent: 5, onPower: true) == .charging && BatteryStyle.charging.glyph == "\u{F0E7}")

    // The date and time boxes.
    let santiago = TimeZone(identifier: "America/Santiago")!
    let moment = Date(timeIntervalSince1970: 1_792_948_000)  // 2026-10-25 14:06:40 in Santiago
    check("the time box reads HH:mm", ClockText.time(moment, timeZone: santiago) == "14:06", ClockText.time(moment, timeZone: santiago))
    check("the date box reads dd-MM-yyyy", ClockText.date(moment, timeZone: santiago) == "25-10-2026", ClockText.date(moment, timeZone: santiago))
    check("the boxes are redrawn when the minute changes", ClockText.nextMinute(after: moment).timeIntervalSince(moment) == 20)

    // The moon box: moon.sh's phase for known dates.
    check("2026-10-24 is the full moon (moon.sh said 4)", MoonPhase.index(at: Date(timeIntervalSince1970: 1_792_871_376)) == 4)
    check("the known new moon is phase 0", MoonPhase.index(at: Date(timeIntervalSince1970: 947_182_440)) == 0)
    check("a week later is the first quarter", MoonPhase.index(at: Date(timeIntervalSince1970: 947_182_440 + 7.4 * 86_400)) == 2)
}
