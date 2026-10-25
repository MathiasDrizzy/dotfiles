import Foundation

/// A long-lived command whose output is read line by line (`aerospace subscribe`, `media-control stream`): one process for
/// the life of the bar instead of one per tick. When it ends (the app it talks to restarted), it is started again after
/// `restartDelay`; `stop()` ends it for good. Only one process runs at a time, whatever the order of start, stop and the
/// end of the previous one.
public final class LineStream: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let restartDelay: TimeInterval
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var process: Process?
    private var running = false
    /// Bumped by every start and stop: a restart scheduled under an older generation is dropped.
    private var generation = 0
    private var startCount = 0

    public init(
        _ executable: String, _ arguments: [String], restartDelay: TimeInterval = 2,
        onLine: @escaping @Sendable (String) -> Void
    ) {
        self.executable = executable
        self.arguments = arguments
        self.restartDelay = restartDelay
        self.onLine = onLine
    }

    /// How many times the command was started; the tests count restarts.
    public var starts: Int { lock.withLock { startCount } }

    /// Starts the stream; a stream already running is left as it is.
    public func start() {
        let current = lock.withLock { () -> Int? in
            guard !running else { return nil }
            running = true
            generation += 1
            return generation
        }
        if let current { launch(current) }
    }

    public func stop() {
        let old = lock.withLock { () -> Process? in
            running = false
            generation += 1
            let old = process
            process = nil
            return old
        }
        old?.terminate()
    }

    private func launch(_ current: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        let pending = Pending()
        pipe.fileHandleForReading.readabilityHandler = { [onLine] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
            for line in pending.append(chunk) { onLine(line) }
        }
        process.terminationHandler = { [weak self] ended in
            self?.ended(ended, generation: current)
        }
        // Published and started under the lock: a stop() in between either comes before (nothing starts) or after
        // (it sees the process and ends it).
        let started = lock.withLock { () -> Bool in
            guard running, generation == current else { return false }
            do {
                try process.run()
            } catch {
                return false
            }
            self.process = process
            startCount += 1
            return true
        }
        if !started {
            pipe.fileHandleForReading.readabilityHandler = nil
            scheduleRestart(current)
        }
    }

    private func ended(_ ended: Process, generation current: Int) {
        lock.withLock {
            if process === ended { process = nil }
        }
        scheduleRestart(current)
    }

    /// Starts it again after the delay, unless it was stopped or started afresh meanwhile.
    private func scheduleRestart(_ current: Int) {
        DispatchQueue.global().asyncAfter(deadline: .now() + restartDelay) { [weak self] in
            guard let self else { return }
            let again = self.lock.withLock { self.running && self.generation == current && self.process == nil }
            if again { self.launch(current) }
        }
    }
}

/// The bytes of a line not yet complete. The read handler runs on one queue at a time, so it is never touched at once.
private final class Pending: @unchecked Sendable {
    private var data = Data()

    /// Adds a chunk and returns the lines it completed.
    func append(_ chunk: Data) -> [String] {
        data.append(chunk)
        var lines: [String] = []
        while let newline = data.firstIndex(of: 0x0A) {
            let line = String(decoding: data[data.startIndex..<newline], as: UTF8.self)
            data.removeSubrange(data.startIndex...newline)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }
}
