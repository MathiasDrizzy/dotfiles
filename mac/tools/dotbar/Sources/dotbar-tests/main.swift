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

print(failures == 0 ? "dotbar-tests: PASS" : "dotbar-tests: \(failures) FAILED")
exit(failures == 0 ? 0 : 1)
