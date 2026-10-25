import Foundation

/// The temperature, from Open-Meteo: no key, no account (WeatherKit needs a paid developer account), one small JSON.
public enum OpenMeteo {
    public static func url(latitude: Double, longitude: Double) -> URL {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            // About a kilometer is all a temperature needs: no more of where you are goes to another service.
            URLQueryItem(name: "latitude", value: String(format: "%.2f", latitude)),
            URLQueryItem(name: "longitude", value: String(format: "%.2f", longitude)),
            URLQueryItem(name: "current", value: "temperature_2m"),
        ]
        return parts.url!
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
