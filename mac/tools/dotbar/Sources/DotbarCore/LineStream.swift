import Foundation

/// A long-lived command whose output is read line by line (`aerospace subscribe`, `media-control stream`): one process for
/// the life of the bar instead of one per tick. When it ends (the app it talks to restarted), it is started again after
/// `restartDelay`; `stop()` ends it for good.
public final class LineStream: @unchecked Sendable {
    private let executable: String
    private let arguments: [String]
    private let restartDelay: TimeInterval
    private let onLine: @Sendable (String) -> Void
    private let lock = NSLock()
    private var process: Process?
    private var stopped = false
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

    public func start() {
        lock.withLock { stopped = false }
        launch()
    }

    public func stop() {
        let running = lock.withLock { () -> Process? in
            stopped = true
            return process
        }
        running?.terminate()
    }

    private func launch() {
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
        process.terminationHandler = { [weak self] _ in
            guard let self else { return }
            let again = self.lock.withLock { () -> Bool in
                self.process = nil
                return !self.stopped
            }
            guard again else { return }
            DispatchQueue.global().asyncAfter(deadline: .now() + self.restartDelay) { [weak self] in
                guard let self, self.lock.withLock({ !self.stopped }) else { return }
                self.launch()
            }
        }
        let launched = lock.withLock { () -> Bool in
            guard !stopped else { return false }
            self.process = process
            startCount += 1
            return true
        }
        guard launched else { return }
        do {
            try process.run()
        } catch {
            // Not installed yet, or not executable: try again later, like a stream that ended.
            process.terminationHandler?(process)
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
