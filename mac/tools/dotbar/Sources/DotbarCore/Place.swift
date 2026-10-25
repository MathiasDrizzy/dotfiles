import Foundation

/// Where the Mac is, as the weather box names it: a point and its commune (CLGeocoder's locality).
public struct Place: Codable, Equatable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let commune: String
    /// When Location Services gave it.
    public let savedAt: Date

    public init(latitude: Double, longitude: Double, commune: String, savedAt: Date) {
        self.latitude = latitude
        self.longitude = longitude
        self.commune = commune
        self.savedAt = savedAt
    }

    /// The place worth remembering from a fix: only a named one, as weather.sh kept only a fix with its commune (a fix
    /// without one is still used for the temperature, but would name nothing next time).
    public static func named(latitude: Double, longitude: Double, commune: String?, at date: Date) -> Place? {
        guard let name = commune?.trimmingCharacters(in: .whitespaces), !name.isEmpty else { return nil }
        return Place(latitude: latitude, longitude: longitude, commune: name, savedAt: date)
    }
}

/// When the remembered place is used instead of a fresh fix (weather.sh's weather_place and PLACE_MAX_HOURS).
public enum PlaceRules {
    /// A place this recent is drawn at once: a slow fix (a loaded Mac) or a denied one does not leave the box empty.
    public static let maxAge: TimeInterval = 12 * 3600
    /// How long an older place waits for a fix first (weather.sh's LOCATE_SECONDS): the Mac may have moved since.
    public static let locateSeconds: TimeInterval = 15

    /// A fix's commune: its own name; without one (the geocoder offline or throttled), the previous place's when the fix
    /// is within a kilometer of it, so a lookup that failed does not drop the name from the box.
    public static func commune(named: String?, latitude: Double, longitude: Double, previous: Place?) -> String? {
        if let name = named?.trimmingCharacters(in: .whitespaces), !name.isEmpty { return name }
        guard let previous, distance(latitude, longitude, previous.latitude, previous.longitude) <= 1_000 else { return nil }
        return previous.commune
    }

    /// Meters between two points (haversine; plenty for "within a kilometer").
    static func distance(_ lat1: Double, _ lon1: Double, _ lat2: Double, _ lon2: Double) -> Double {
        let radians = Double.pi / 180
        let dLat = (lat2 - lat1) * radians
        let dLon = (lon2 - lon1) * radians
        let a = sin(dLat / 2) * sin(dLat / 2) + cos(lat1 * radians) * cos(lat2 * radians) * sin(dLon / 2) * sin(dLon / 2)
        return 6_371_000 * 2 * atan2(a.squareRoot(), (1 - a).squareRoot())
    }

    public static func isFresh(_ place: Place, now: Date) -> Bool {
        now.timeIntervalSince(place.savedAt) <= maxAge
    }

    /// Seconds to wait for a fix before drawing from the remembered place: none when it is fresh, LOCATE_SECONDS when
    /// it is older (it is still the best there is without a fix), nil when nothing is remembered (only a fix can name
    /// the place).
    public static func waitForFix(remembered: Place?, now: Date) -> TimeInterval? {
        guard let remembered else { return nil }
        return isFresh(remembered, now: now) ? 0 : locateSeconds
    }
}

/// The remembered place on disk, so a new launch draws the box before (or without) a fix:
/// ~/Library/Application Support/dotbar/place.json.
public struct PlaceStore: Sendable {
    public let file: URL

    public init(folder: URL) {
        file = folder.appendingPathComponent("place.json")
    }

    /// ~/Library/Application Support/dotbar.
    public static var standard: PlaceStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return PlaceStore(folder: support.appendingPathComponent("dotbar"))
    }

    public func load() -> Place? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Place.self, from: data)
    }

    public func save(_ place: Place) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(place).write(to: file, options: .atomic)
    }

    /// SketchyBar's weather_place ("latitude<TAB>longitude<TAB>commune", dated by the file), read once when dotbar has
    /// none of its own: the first launch, before Location Services is allowed, still names the place.
    public static func legacy(at file: URL) -> Place? {
        guard let text = try? String(contentsOf: file, encoding: .utf8),
            let date = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date
        else { return nil }
        let fields = text.trimmingCharacters(in: .newlines).split(separator: "\t", omittingEmptySubsequences: false)
        guard fields.count >= 3, let latitude = Double(fields[0]), let longitude = Double(fields[1]) else { return nil }
        return Place.named(latitude: latitude, longitude: longitude, commune: String(fields[2]), at: date)
    }

    /// Where SketchyBar's weather.sh kept it.
    public static var legacyFile: URL {
        let cache = ProcessInfo.processInfo.environment["XDG_CACHE_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache")
        return cache.appendingPathComponent("sketchybar/weather_place")
    }
}
