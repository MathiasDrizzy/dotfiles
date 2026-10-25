import Foundation

/// Runs outside commands for the bar. The bash plugins it replaces started a command on every tick and waited on it with
/// no limit: one that hung was started again by the next tick, and they piled up by the dozens. Here every command has a
/// time limit, and a command still running under a key is never started again under that key: callers that ask
/// meanwhile wait for the run in flight and share its result.
public actor CommandRunner {
    public struct Output: Sendable, Equatable {
        public let status: Int32
        public let stdout: String
        public let timedOut: Bool

        public init(status: Int32, stdout: String, timedOut: Bool) {
            self.status = status
            self.stdout = stdout
            self.timedOut = timedOut
        }
    }

    private var inFlight: [String: Task<Output, Never>] = [:]
    private var launches = 0

    public init() {}

    /// How many processes this runner has started; the tests count them.
    public var launchCount: Int { launches }

    /// Runs `executable` with `arguments`, ended once `timeout` seconds pass. While a run under `key` is in flight, a
    /// second call waits for it instead of starting another process.
    public func run(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval, key: String? = nil) async
        -> Output
    {
        let key = key ?? ([executable] + arguments).joined(separator: " ")
        if let running = inFlight[key] {
            return await running.value
        }
        launches += 1
        let task = Task.detached { Self.launch(executable, arguments, timeout: timeout) }
        inFlight[key] = task
        let output = await task.value
        inFlight[key] = nil
        return output
    }

    /// Starts the process and waits at most `timeout`; past it the process gets SIGTERM, then SIGKILL a moment later.
    private static func launch(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Output {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let finished = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in finished.signal() }
        do {
            try process.run()
        } catch {
            return Output(status: 127, stdout: "", timedOut: false)
        }
        // Read while it runs: a full pipe would block a chatty command until the limit.
        let collected = Collected()
        let read = DispatchSemaphore(value: 0)
        DispatchQueue(label: "dotbar.command.reader").async {
            collected.data = pipe.fileHandleForReading.readDataToEndOfFile()
            read.signal()
        }
        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                finished.wait()
            }
        }
        // A child the command left behind may keep the pipe open: the output read so far is enough.
        _ = read.wait(timeout: .now() + 0.5)
        return Output(
            status: timedOut ? -1 : process.terminationStatus,
            stdout: String(decoding: collected.data, as: UTF8.self),
            timedOut: timedOut
        )
    }
}

/// The output a reader thread fills; read only after its semaphore (or the half second given to it) has passed.
private final class Collected: @unchecked Sendable {
    var data = Data()
}
