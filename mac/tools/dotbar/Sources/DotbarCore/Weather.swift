import Foundation

/// The temperature and the sky, from Open-Meteo: no key, no account (WeatherKit needs a paid developer account), one
/// small JSON.
public enum OpenMeteo {
    public static func url(latitude: Double, longitude: Double) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            // About a kilometer is all a temperature needs: no more of where you are goes to another service.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,is_day"),
        ]
        return parts.url!
    }

    /// `current.weather_code` and `current.is_day`; no code is no sky (the box shows the thermometer). A missing
    /// `is_day` counts as day.
    public static func sky(in data: Data) -> Sky? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any],
            let code = current["weather_code"] as? NSNumber
        else { return nil }
        return Sky(code: code.intValue, isDay: (current["is_day"] as? NSNumber)?.intValue != 0)
    }

    /// `current.temperature_2m`, rounded as weather.sh's jq `round` did: to the nearest degree, a half away from zero.
    /// Anything else (an error page, a null, garbage) is no temperature, and the box keeps what it showed.
    public static func temperature(in data: Data) -> Int? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let current = root["current"] as? [String: Any],
            let value = current["temperature_2m"] as? NSNumber
        else { return nil }
        let rounded = value.doubleValue.rounded(.toNearestOrAwayFromZero)
        return rounded.isFinite ? Int(rounded) : nil
    }
}

/// The sky now: a WMO weather code (https://open-meteo.com/en/docs, "WMO Weather interpretation codes") and daylight.
public struct Sky: Equatable, Sendable {
    public let code: Int
    public let isDay: Bool

    public init(code: Int, isDay: Bool) {
        self.code = code
        self.isDay = isDay
    }
}

/// The weather box's icon: the Nerd Font's weather-icons glyph for the sky, the thermometer until one is known.
public enum WeatherIcon {
    public static let thermometer = "\u{F2C7}"

    public static func glyph(for sky: Sky?) -> String {
        guard let sky else { return thermometer }
        switch sky.code {
        case 0: return sky.isDay ? "\u{E30D}" : "\u{E32B}"  // day_sunny, night_clear
        case 1, 2: return sky.isDay ? "\u{E302}" : "\u{E379}"  // day_cloudy, night_alt_partly_cloudy
        case 3: return "\u{E312}"  // cloudy
        case 45, 48: return "\u{E313}"  // fog
        case 51, 53, 55, 56, 57: return "\u{E31B}"  // sprinkle
        case 61, 63, 65: return "\u{E318}"  // rain
        case 66, 67: return "\u{E316}"  // rain_mix
        case 80, 81, 82: return "\u{E319}"  // showers
        case 71, 73, 75, 77, 85, 86: return "\u{E31A}"  // snow
        case 95, 96, 99: return "\u{E31D}"  // thunderstorm
        default: return thermometer
        }
    }
}

/// The weather box's text: "Providencia 25°C", or "25°C" when no commune is known.
public enum WeatherText {
    /// SketchyBar's update_freq=1800: Open-Meteo has no event to wait for, so the temperature is read every 30 minutes
    /// (and on wake, and when the Mac moves).
    public static let refreshInterval: TimeInterval = 1800

    public static func label(commune: String?, temperature: Int) -> String {
        let name = commune?.trimmingCharacters(in: .whitespaces) ?? ""
        return name.isEmpty ? "\(temperature)°C" : "\(name) \(temperature)°C"
    }
}

/// One refresh at a time (S2): a refresh asked for while one runs is not started beside it; it runs once after it ends,
/// however many were asked for meanwhile.
public struct RefreshGate: Sendable {
    private var running = false
    private var pending = false

    public init() {}

    /// True when the caller should start now; false when one runs (it is then owed one more run).
    public mutating func begin() -> Bool {
        if running {
            pending = true
            return false
        }
        running = true
        return true
    }

    /// Ends the running refresh; true when another was asked for meanwhile and the caller should run it (it is then
    /// the running one).
    public mutating func end() -> Bool {
        if pending {
            pending = false
            return true
        }
        running = false
        return false
    }
}
