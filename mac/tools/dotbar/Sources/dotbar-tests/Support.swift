// Shared helpers of the checks. Each area of the bar has its own file with one async function, called from main.swift.
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

/// Waits until `condition` holds, polling every 50 ms, at most `seconds`: a check that waits for a process to start or end
/// on a loaded machine instead of guessing a fixed pause. Returns whether it held in time.
func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return condition()
}
