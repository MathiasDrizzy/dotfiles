import Foundation

/// The track the now playing pill shows (media.sh): Spotify's only, since a video in a browser tab is "now playing" too.
public struct NowPlaying: Equatable, Sendable {
    public let title: String
    public let artist: String
    public let playing: Bool

    public init(title: String, artist: String, playing: Bool) {
        self.title = title
        self.artist = artist
        self.playing = playing
    }
}

/// What one answer of `media-control` says about the pill.
public enum MediaReading: Equatable, Sendable {
    /// Spotify has a track loaded, playing or paused.
    case track(NowPlaying)
    /// Nothing for the pill: no player, another app's media, or a Spotify with no title.
    case nothing
    /// The stream sent an empty payload. It does so when it starts, before the real one, so it is not taken as "nothing"
    /// (the pill would close and open again): a `get` settles it.
    case unsure
}

public enum Media {
    public static let bundle = "com.spotify.client"
    /// Characters of title and artist together, at most (media.sh's MAX_LENGTH; T7 narrows it to fit the notch side).
    public static let maxLength = 35
    /// Between the title and the artist (MEDIA_DOT of icons.sh).
    public static let dot = "\u{F47D}"

    /// The answer of `media-control get` that exited well: the now playing info as one JSON object, `null` or nothing at
    /// all when nothing plays. `nil` when it is not JSON: the pill keeps what it shows.
    public static func parseGet(_ output: String) -> MediaReading? {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "null" { return .nothing }
        guard let data = trimmed.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return reading(object)
    }

    /// One line of `media-control stream --no-diff`: `{"type":"data","diff":false,"payload":{...}}`, every payload the
    /// whole info (no diff to merge). `nil` for a line that is not data.
    public static func parseStreamLine(_ line: String) -> MediaReading? {
        guard let data = line.data(using: .utf8),
            let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            object["type"] as? String == "data",
            let payload = object["payload"] as? [String: Any]
        else { return nil }
        return payload.isEmpty ? .unsure : reading(payload)
    }

    private static func reading(_ info: [String: Any]) -> MediaReading {
        guard info["bundleIdentifier"] as? String == bundle,
            let title = info["title"] as? String, !title.isEmpty
        else { return .nothing }
        return .track(
            NowPlaying(title: title, artist: info["artist"] as? String ?? "", playing: info["playing"] as? Bool ?? false))
    }

    /// "title  artist", cut as media.sh cut it (neutonfoo/dotfiles's Spotify item): when both are long each gets half,
    /// otherwise the long one gives way to the other.
    public static func text(_ track: NowPlaying, maxLength: Int = maxLength) -> String {
        var title = track.title
        var artist = track.artist
        let half = (maxLength + 1) / 2
        if title.count + artist.count > maxLength {
            if title.count > half && artist.count > half {
                title = String(title.prefix(half - 1)) + "…"
                artist = String(artist.prefix(half - 2)) + "…"
            } else if title.count > half {
                title = String(title.prefix(max(0, maxLength - artist.count - 1))) + "…"
            } else if artist.count > half {
                artist = String(artist.prefix(max(0, maxLength - title.count - 1))) + "…"
            }
        }
        return artist.isEmpty ? title : "\(title) \(dot) \(artist)"
    }
}

/// Whether the pill is open, and what a new reading does to it: it slides open when a track loads, closed when none is
/// left, and only repaints while a track replaces another.
public enum MediaPill: Equatable, Sendable {
    case open
    case close
    case update
    case stay

    public static func change(shown: NowPlaying?, reading: MediaReading) -> MediaPill {
        switch (shown, reading) {
        case (nil, .track): return .open
        case (let old?, .track(let new)): return old == new ? .stay : .update
        case (.some, .nothing): return .close
        case (nil, .nothing), (_, .unsure): return .stay
        }
    }
}

/// The player's side of the pill: one long-lived `media-control stream` for changes, a `get` at start, after wake and to
/// settle an empty stream payload, and the play/pause click. Each `get` and each click has a time limit and never runs
/// twice at once (CommandRunner keys); nothing is polled. A `get` that started before a stream update is dropped, so an
/// older answer never paints over a newer one.
public final class MediaFeed: @unchecked Sendable {
    private let runner: CommandRunner
    private let executable: String
    private let onReading: @Sendable (MediaReading) -> Void
    private let lock = NSLock()
    private var stream: LineStream?
    /// Bumped by every stream update; a `get` answer is taken only if none came while it ran.
    private var generation = 0

    /// The player answers in milliseconds; past this it is not answering.
    public static let timeout: TimeInterval = 5

    public init(runner: CommandRunner, executable: String, onReading: @escaping @Sendable (MediaReading) -> Void) {
        self.runner = runner
        self.executable = executable
        self.onReading = onReading
    }

    public func start() {
        let stream = LineStream(executable, ["stream", "--no-diff"]) { [weak self] line in
            self?.received(line)
        }
        // Taken before the stream starts: its first update may come before the get is even asked, and then it wins.
        let startedAt = lock.withLock { () -> Int in
            self.stream = stream
            return generation
        }
        stream.start()
        Task { await fetch(startedAt: startedAt) }
    }

    public func stop() {
        let stream = lock.withLock { () -> LineStream? in
            let old = self.stream
            self.stream = nil
            return old
        }
        stream?.stop()
    }

    /// Asks the player once (at start, after wake): what the stream would only say at its next change.
    public func refresh() async {
        await fetch(startedAt: lock.withLock { generation })
    }

    private func fetch(startedAt: Int) async {
        let output = await runner.run(executable, ["get"], timeout: Self.timeout, key: "media get")
        guard output.status == 0, let reading = Media.parseGet(output.stdout) else { return }
        let current = lock.withLock { generation == startedAt }
        if current { onReading(reading) }
    }

    /// Plays or pauses; the stream then reports the new state.
    public func toggle() async {
        _ = await runner.run(executable, ["toggle-play-pause"], timeout: Self.timeout, key: "media toggle")
    }

    private func received(_ line: String) {
        guard let reading = Media.parseStreamLine(line) else { return }
        if reading == .unsure {
            Task { await refresh() }
            return
        }
        lock.withLock { generation += 1 }
        onReading(reading)
    }
}
