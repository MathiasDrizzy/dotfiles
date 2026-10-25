// The now playing pill's checks: media-control's answers (fixtures captured from the real tool, the artwork shortened),
// the Spotify-only filter, media.sh's text and cut, the open/closed decision, and the feed against a stub media-control.
import DotbarCore
import Foundation

/// `media-control get` with Spotify paused, as the tool printed it.
private let getPaused = """
    {"album":"Los Bandoleros","mediaType":"kMRMediaRemoteNowPlayingInfoTypeAudio","trackNumber":13,"elapsedTime":54.045000000000002,"timestamp":"2026-10-25T19:32:21Z","bundleIdentifier":"com.spotify.client","processIdentifier":90512,"artworkData":"/9j/4AAQ","title":"Dale Mami Pégate","totalDiscCount":0,"totalTrackCount":0,"artworkMimeType":"image/jpeg","duration":173.107,"artist":"Don Omar","contentItemIdentifier":"181CB5CA-DB97-4395-9350-953175C078F9","playing":false}
    """
/// `media-control stream --no-diff`: the empty payload it sends first, then the whole info.
private let streamEmpty = #"{"type":"data","diff":false,"payload":{}}"#
private let streamPlaying = """
    {"type":"data","diff":false,"payload":{"album":"Los Bandoleros","mediaType":"kMRMediaRemoteNowPlayingInfoTypeAudio","trackNumber":13,"elapsedTime":54.045000000000002,"timestamp":"2026-10-25T19:32:21Z","bundleIdentifier":"com.spotify.client","processIdentifier":90512,"artworkData":"/9j/4AAQ","title":"Dale Mami Pégate","totalDiscCount":0,"totalTrackCount":0,"artworkMimeType":"image/jpeg","duration":173.107,"artist":"Don Omar","contentItemIdentifier":"181CB5CA-DB97-4395-9350-953175C078F9","playing":true}}
    """
/// A video in a browser tab is "now playing" too.
private let streamSafari = """
    {"type":"data","diff":false,"payload":{"bundleIdentifier":"com.apple.Safari","title":"A video","artist":"","playing":true}}
    """

private let dale = NowPlaying(title: "Dale Mami Pégate", artist: "Don Omar", playing: false)

private final class Readings: @unchecked Sendable {
    let lock = NSLock()
    var all: [MediaReading] = []
    func add(_ reading: MediaReading) { lock.withLock { all.append(reading) } }
    var list: [MediaReading] { lock.withLock { all } }
}

/// A stand-in for media-control in a scratch folder: `get` prints get.json after `getDelay` seconds, `stream` prints
/// stream.txt and then waits (as the real stream does) with a sleep only this run has, `toggle-play-pause` adds a line
/// to toggles. It never touches the real player.
private func stub(get: String, getDelay: Double = 0, stream: [String], hang: String) -> URL {
    let dir = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dotbar-media-\(getpid())-\(hang)")
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    try? get.write(to: dir.appendingPathComponent("get.json"), atomically: true, encoding: .utf8)
    try? (stream.joined(separator: "\n") + "\n").write(
        to: dir.appendingPathComponent("stream.txt"), atomically: true, encoding: .utf8)
    let script = """
        #!/bin/sh
        dir="$(dirname "$0")"
        case "$1" in
        get) sleep \(getDelay); cat "$dir/get.json" ;;
        stream) while read -r line; do echo "$line"; sleep 0.2; done < "$dir/stream.txt"; exec /bin/sleep \(hang) ;;
        toggle-play-pause) sleep 0.2; echo toggled >> "$dir/toggles" ;;
        esac
        """
    let path = dir.appendingPathComponent("media-control")
    try? script.write(to: path, atomically: true, encoding: .utf8)
    try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path.path)
    return path
}

func mediaTests() async {
    // Parsing what the real tool prints.
    check("a get of Spotify reads its track", Media.parseGet(getPaused) == .track(dale), "\(String(describing: Media.parseGet(getPaused)))")
    check("a get with nothing playing is nothing", Media.parseGet("null\n") == .nothing && Media.parseGet("") == .nothing)
    check("a get that is not JSON keeps what is shown", Media.parseGet("media-control: error") == nil)
    check("the stream's empty payload is not taken as nothing", Media.parseStreamLine(streamEmpty) == .unsure)
    check(
        "a stream line reads the whole track",
        Media.parseStreamLine(streamPlaying) == .track(NowPlaying(title: dale.title, artist: dale.artist, playing: true)))
    check("a line that is not data is skipped", Media.parseStreamLine("not json") == nil && Media.parseStreamLine(#"{"type":"other"}"#) == nil)

    // Spotify's only.
    check("another app's media is nothing for the pill", Media.parseStreamLine(streamSafari) == .nothing)
    check(
        "a Spotify with no title is nothing",
        Media.parseGet(#"{"bundleIdentifier":"com.spotify.client","title":"","playing":true}"#) == .nothing)

    // The text and its cut (media.sh, MAX_LENGTH 35).
    check("title, the dot, artist", Media.text(dale) == "Dale Mami Pégate \u{F47D} Don Omar")
    check("no artist, the title alone", Media.text(NowPlaying(title: "Podcast", artist: "", playing: true)) == "Podcast")
    let long = String(repeating: "t", count: 30)
    let longArtist = String(repeating: "a", count: 30)
    check(
        "both long: each gets half",
        Media.text(NowPlaying(title: long, artist: longArtist, playing: true))
            == String(repeating: "t", count: 17) + "… \u{F47D} " + String(repeating: "a", count: 16) + "…")
    check(
        "a long title gives way to the artist",
        Media.text(NowPlaying(title: long, artist: "Don Omar", playing: true))
            == String(repeating: "t", count: 26) + "… \u{F47D} Don Omar")
    check(
        "a long artist gives way to the title",
        Media.text(NowPlaying(title: "Dale", artist: String(repeating: "a", count: 33), playing: true))
            == "Dale \u{F47D} " + String(repeating: "a", count: 30) + "…")
    check(
        "together within the limit, nothing is cut",
        Media.text(NowPlaying(title: "Dale Mami Pégate", artist: "Don Omar", playing: true), maxLength: 24)
            == "Dale Mami Pégate \u{F47D} Don Omar")
    check(
        "the limit counts characters, not bytes",
        Media.text(NowPlaying(title: String(repeating: "é", count: 40), artist: "", playing: true))
            == String(repeating: "é", count: 34) + "…")

    // Open or closed.
    check("a track loads: it slides open", MediaPill.change(shown: nil, reading: .track(dale)) == .open)
    check("none is left: it slides closed", MediaPill.change(shown: dale, reading: .nothing) == .close)
    check(
        "a new track or a pause: repainted in place",
        MediaPill.change(shown: dale, reading: .track(NowPlaying(title: dale.title, artist: dale.artist, playing: true)))
            == .update)
    check("the same track: nothing to do", MediaPill.change(shown: dale, reading: .track(dale)) == .stay)
    check("closed and nothing: it stays closed", MediaPill.change(shown: nil, reading: .nothing) == .stay)
    check("unsure never closes it", MediaPill.change(shown: dale, reading: .unsure) == .stay)

    // The feed against a stub: the get at start, the stream's empty payload settled by a get, then the stream's track.
    let hang = "3006\(getpid())"
    let tool = stub(get: getPaused, stream: [streamEmpty, streamPlaying], hang: hang)
    let readings = Readings()
    let runner = CommandRunner()
    let feed = MediaFeed(runner: runner, executable: tool.path) { readings.add($0) }
    feed.start()
    try? await Task.sleep(for: .seconds(1.5))
    let got = readings.list
    check("the feed never hands on an unsure payload", !got.contains(.unsure), "\(got)")
    check("the feed reads the player at start", got.first == .track(dale), "\(got)")
    check(
        "...and then follows the stream",
        got.last == .track(NowPlaying(title: dale.title, artist: dale.artist, playing: true)), "\(got)")
    check("one stream process", running("sleep \(hang)") == 1, "\(running("sleep \(hang)"))")

    // The click: two at once run one toggle, with a time limit.
    async let first: Void = feed.toggle()
    async let second: Void = feed.toggle()
    _ = await (first, second)
    let toggles = (try? String(contentsOf: tool.deletingLastPathComponent().appendingPathComponent("toggles"), encoding: .utf8)) ?? ""
    check("a click toggles play/pause once", toggles == "toggled\n", "\(toggles.debugDescription)")

    feed.stop()
    try? await Task.sleep(for: .seconds(0.4))
    check("stopped, the stream is gone", running("sleep \(hang)") == 0, "\(running("sleep \(hang)"))")

    // A get that started before a stream update must not paint the older state back.
    let staleHang = "3007\(getpid())"
    let slow = stub(get: getPaused, getDelay: 0.8, stream: [streamPlaying], hang: staleHang)
    let later = Readings()
    let slowFeed = MediaFeed(runner: CommandRunner(), executable: slow.path) { later.add($0) }
    slowFeed.start()
    try? await Task.sleep(for: .seconds(1.5))
    slowFeed.stop()
    let seen = later.list
    check(
        "a get older than the stream's update is dropped",
        seen == [.track(NowPlaying(title: dale.title, artist: dale.artist, playing: true))], "\(seen)")
    try? await Task.sleep(for: .seconds(0.4))
    check("...and its stream is gone too", running("sleep \(staleHang)") == 0)

    try? FileManager.default.removeItem(at: tool.deletingLastPathComponent())
    try? FileManager.default.removeItem(at: slow.deletingLastPathComponent())
}
