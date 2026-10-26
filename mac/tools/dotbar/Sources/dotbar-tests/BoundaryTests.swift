// Edges the native reviews found: the track text at an odd limit, the precision sent to Open-Meteo, a command that floods
// its output.
import DotbarCore
import Foundation

func boundaryTests() async {
    let even = NowPlaying(title: String(repeating: "t", count: 18), artist: String(repeating: "a", count: 18), playing: true)
    let text = Media.text(even, maxLength: 35)
    let parts = text.components(separatedBy: " \(Media.dot) ")
    check(
        "a title and an artist at half an odd limit still fit it",
        parts.count == 2 && parts[0].count + parts[1].count <= 35, "\(text)")

    let url = OpenMeteo.url(latitude: -33.437830, longitude: -70.650480).absoluteString
    check(
        "Open-Meteo gets the place to about a kilometer, not the exact fix",
        url.contains("latitude=-33.44") && url.contains("longitude=-70.65") && !url.contains("437830"), url)

    let flood = await CommandRunner().run("/usr/bin/yes", ["flood"], timeout: 1)
    check(
        "a command flooding its output ends at its limit with at most a megabyte kept",
        flood.timedOut && flood.stdout.utf8.count <= 1_048_576, "\(flood.stdout.utf8.count) bytes")
    check("...and nothing of it keeps running", await waitUntil(2) { running("yes flood") == 0 })
}
