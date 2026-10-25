// Checks for DotbarCore, run with `swift run dotbar-tests` (exit status 1 on any failure). `swift test` needs Xcode;
// this needs only the Command Line Tools.
import CoreGraphics
import DotbarCore
import Foundation

nonisolated(unsafe) var failures = 0

func check(_ name: String, _ condition: Bool, _ detail: @autoclosure () -> String = "") {
    if condition {
        print("PASS  \(name)")
    } else {
        failures += 1
        print("FAIL  \(name)\(detail().isEmpty ? "" : " (\(detail()))")")
    }
}

/// Processes whose command line ends with `pattern`.
func running(_ pattern: String) -> Int {
    let pgrep = Process()
    pgrep.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
    pgrep.arguments = ["-f", pattern + "$"]
    let pipe = Pipe()
    pgrep.standardOutput = pipe
    try? pgrep.run()
    pgrep.waitUntilExit()
    return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        .split(separator: "\n").count
}

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

print(failures == 0 ? "dotbar-tests: PASS" : "dotbar-tests: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
