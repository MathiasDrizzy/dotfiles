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
