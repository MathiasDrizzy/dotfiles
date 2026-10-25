// The weather and moon boxes' checks: Open-Meteo's answer, the label, the remembered place, when to refresh. No check
// touches the network or Location Services: the answers are fixtures.
import DotbarCore
import Foundation

func weatherTests() async {
    // Open-Meteo's answer, rounded as weather.sh's jq `round` did (half away from zero).
    func answer(_ temperature: String) -> Data {
        Data(#"{"latitude":-33.4375,"longitude":-70.625,"current_units":{"temperature_2m":"°C"},"current":{"time":"2026-10-25T16:00","interval":900,"temperature_2m":\#(temperature)}}"#.utf8)
    }
    check("Open-Meteo's temperature is read", OpenMeteo.temperature(in: answer("24.6")) == 25)
    check("a half rounds away from zero, up", OpenMeteo.temperature(in: answer("24.5")) == 25)
    check("...and down below zero", OpenMeteo.temperature(in: answer("-0.5")) == -1)
    check("a cold day rounds to the nearest degree", OpenMeteo.temperature(in: answer("-3.4")) == -3)
    check("a whole number stays as it is", OpenMeteo.temperature(in: answer("13")) == 13)
    check("a null temperature is no temperature", OpenMeteo.temperature(in: answer("null")) == nil)
    check("an error page is no temperature", OpenMeteo.temperature(in: Data(#"{"error":true,"reason":"bad"}"#.utf8)) == nil)
    check("garbage is no temperature", OpenMeteo.temperature(in: Data("<html>".utf8)) == nil)
    let url = OpenMeteo.url(latitude: -33.437800, longitude: -70.650500).absoluteString
    check(
        "the request asks for the current temperature at the place",
        url == "https://api.open-meteo.com/v1/forecast?latitude=-33.44&longitude=-70.65&current=temperature_2m", url)

    // The label.
    check("the label is the commune and the temperature", WeatherText.label(commune: "Providencia", temperature: 25) == "Providencia 25°C")
    check("without a commune, only the temperature", WeatherText.label(commune: nil, temperature: 25) == "25°C")
    check("an empty commune is no commune", WeatherText.label(commune: "  ", temperature: -2) == "-2°C")

    // The remembered place (weather.sh's weather_place): only a named one, trusted for 12 hours.
    let now = Date(timeIntervalSince1970: 1_792_948_000)
    let named = Place.named(latitude: -33.437800, longitude: -70.650500, commune: "Providencia", at: now)
    check("a fix with a commune is remembered", named?.commune == "Providencia")
    check("a fix without one is not", Place.named(latitude: 1, longitude: 2, commune: nil, at: now) == nil
        && Place.named(latitude: 1, longitude: 2, commune: "", at: now) == nil)
    let fresh = named!
    let stale = Place(latitude: 1, longitude: 2, commune: "La Florida", savedAt: now.addingTimeInterval(-13 * 3600))
    check("a place 12 hours old is still fresh", PlaceRules.isFresh(Place(latitude: 1, longitude: 2, commune: "x", savedAt: now.addingTimeInterval(-12 * 3600)), now: now))
    check("a fresh place is drawn at once, without waiting for a fix", PlaceRules.waitForFix(remembered: fresh, now: now) == 0)
    check("an older one waits for a fix first, as long as weather.sh did", PlaceRules.waitForFix(remembered: stale, now: now) == 15)
    check("with nothing remembered, only a fix can name the place", PlaceRules.waitForFix(remembered: nil, now: now) == nil)

    // A fix the geocoder could not name (offline, throttled) keeps the commune of a place next to it.
    check("a named fix keeps its own name", PlaceRules.commune(named: "Recoleta", latitude: 1, longitude: 2, previous: fresh) == "Recoleta")
    check(
        "an unnamed fix a few hundred meters away keeps the previous commune",
        PlaceRules.commune(named: nil, latitude: -33.440, longitude: -70.652, previous: fresh) == "Providencia")
    check("an unnamed fix far away has no commune", PlaceRules.commune(named: nil, latitude: -33.45, longitude: -70.66, previous: fresh) == nil)
    check("an unnamed fix with nothing before has no commune", PlaceRules.commune(named: "", latitude: 1, longitude: 2, previous: nil) == nil)

    // The place on disk.
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("dotbar-weather-\(getpid())")
    defer { try? FileManager.default.removeItem(at: folder) }
    let store = PlaceStore(folder: folder)
    check("nothing is remembered at first", store.load() == nil)
    try? store.save(fresh)
    check("a saved place is read back", store.load() == fresh, "\(String(describing: store.load()))")
    let legacy = folder.appendingPathComponent("weather_place")
    try? Data("-33.437800\t-70.650500\tProvidencia\n".utf8).write(to: legacy)
    try? FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: legacy.path)
    let migrated = PlaceStore.legacy(at: legacy)
    check(
        "SketchyBar's weather_place is read, dated by its file",
        migrated == Place(latitude: -33.437800, longitude: -70.650500, commune: "Providencia", savedAt: now), "\(String(describing: migrated))")
    try? Data("-33.44\t-70.65\t\n".utf8).write(to: legacy)
    check("...but not one without a commune", PlaceStore.legacy(at: legacy) == nil)
    check("...nor a file that is not there", PlaceStore.legacy(at: folder.appendingPathComponent("none")) == nil)

    // Refreshing: one fetch at a time; one asked for meanwhile runs once after it.
    var gate = RefreshGate()
    check("a refresh starts when none runs", gate.begin())
    check("a second one waits", !gate.begin() && !gate.begin())
    check("...and runs once when the first ends", gate.end())
    check("then nothing is pending", !gate.end() && gate.begin())
    check("the temperature is read every 30 minutes, as update_freq=1800", WeatherText.refreshInterval == 1800)

    // The moon box is redrawn when its phase changes, not on a tick.
    let change = MoonPhase.nextChange(after: now)
    check("the next phase change is ahead, within an eighth of a month", change > now && change.timeIntervalSince(now) <= 29.530588853 / 8 * 86_400)
    check(
        "...and the phase is another one after it",
        MoonPhase.index(at: change.addingTimeInterval(-1)) != MoonPhase.index(at: change.addingTimeInterval(1)))
    check("...the one before it is the phase of now", MoonPhase.index(at: change.addingTimeInterval(-1)) == MoonPhase.index(at: now))
    let after = MoonPhase.nextChange(after: change.addingTimeInterval(1))
    check("the change after is a whole eighth later", abs(after.timeIntervalSince(change) - 29.530588853 / 8 * 86_400) < 1)
}
