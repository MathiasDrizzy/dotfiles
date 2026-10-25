import Darwin
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
        let task = Task<Output, Never> {
            // The waiting happens on a dispatch thread, never on one of Swift's few cooperative threads: a hung command
            // must not starve the rest of the bar.
            await withCheckedContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    continuation.resume(returning: Self.launch(executable, arguments, timeout: timeout))
                }
            }
        }
        inFlight[key] = task
        let output = await task.value
        inFlight[key] = nil
        return output
    }

    /// Starts the process and waits at most `timeout`; past it the process and everything it started get SIGTERM, then
    /// SIGKILL a moment later.
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
        // Read as the output comes (a full pipe would block a chatty command until its limit), without a thread blocked
        // on the pipe: a child the command left behind could hold it open forever.
        let collected = Collected()
        let reader = pipe.fileHandleForReading
        reader.readabilityHandler = { handle in
            let chunk = handle.availableData
            if chunk.isEmpty {
                handle.readabilityHandler = nil
                collected.finish()
            } else {
                collected.append(chunk)
            }
        }
        do {
            try process.run()
        } catch {
            reader.readabilityHandler = nil
            return Output(status: 127, stdout: "", timedOut: false)
        }
        var timedOut = false
        if finished.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            let family = [process.processIdentifier] + Self.descendants(of: process.processIdentifier)
            family.forEach { kill($0, SIGTERM) }
            if finished.wait(timeout: .now() + 0.5) == .timedOut {
                family.forEach { kill($0, SIGKILL) }
                _ = finished.wait(timeout: .now() + 1)
            }
        }
        // The rest of the output, if it is coming; then the pipe is let go either way.
        collected.waitForEnd(upTo: 0.5)
        reader.readabilityHandler = nil
        try? reader.close()
        return Output(
            status: timedOut ? -1 : process.terminationStatus,
            stdout: String(decoding: collected.data, as: UTF8.self),
            timedOut: timedOut
        )
    }

    /// Every process below `pid`, children first.
    static func descendants(of pid: pid_t) -> [pid_t] {
        var buffer = [pid_t](repeating: 0, count: 256)
        // It returns how many pids it wrote, not how many bytes.
        let count = proc_listchildpids(pid, &buffer, Int32(buffer.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        let children = Array(buffer.prefix(min(Int(count), buffer.count))).filter { $0 > 0 }
        return children + children.flatMap { descendants(of: $0) }
    }
}

/// The output a read handler fills while the command runs; every access holds the lock.
private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var bytes = Data()
    private let ended = DispatchSemaphore(value: 0)

    var data: Data { lock.withLock { bytes } }

    func append(_ chunk: Data) { lock.withLock { bytes.append(chunk) } }

    func finish() { ended.signal() }

    func waitForEnd(upTo seconds: TimeInterval) { _ = ended.wait(timeout: .now() + seconds) }
}
