import AppKit
import CoreLocation
import DotbarCore
import Observation
import SwiftUI

/// The weather box's data, natively (S7): where the Mac is from Location Services, its commune from CLGeocoder, the
/// temperature from Open-Meteo through URLSession. No shortcut, no CoreLocationCLI, no curl, no process. The temperature
/// is read every 30 minutes, on wake and when the Mac moves (a significant location change); the last named place is
/// remembered on disk so the box is drawn before a fix, or without one while Location Services is not allowed.
@MainActor
@Observable
final class WeatherModel {
    /// "Providencia 25°C"; nil until a temperature was read once. Offline, it keeps the last text.
    private(set) var label: String?

    @ObservationIgnored private let store = PlaceStore.standard
    @ObservationIgnored private let locator = Locator()
    @ObservationIgnored private let geocoder = CLGeocoder()
    @ObservationIgnored private var gate = RefreshGate()
    /// The place the temperature is read for: the last fix, or the remembered place until one comes.
    @ObservationIgnored private var place: (latitude: Double, longitude: Double, commune: String?)?
    @ObservationIgnored private var gotFix = false
    /// The last named place (remembered or from a fix), whose commune an unnamed fix next to it keeps.
    @ObservationIgnored private var named: Place?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var fallback: Timer?
    @ObservationIgnored private var wake: NSObjectProtocol?
    @ObservationIgnored private let session: URLSession = {
        // weather.sh's curl --max-time 10: a request that hangs is given up, and the box keeps its text.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.waitsForConnectivity = false
        return URLSession(configuration: configuration)
    }()

    func start() {
        let remembered = store.load() ?? PlaceStore.legacy(at: PlaceStore.legacyFile)
        named = remembered
        if let remembered {
            place = (remembered.latitude, remembered.longitude, remembered.commune)
        }
        switch PlaceRules.waitForFix(remembered: remembered, now: Date()) {
        case 0:
            refresh()
        case let seconds?:
            // An old place: give Location Services LOCATE_SECONDS to answer first, then draw with what is known.
            let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.gotFix else { return }
                    self.refresh()
                }
            }
            RunLoop.main.add(timer, forMode: .common)
            fallback = timer
        case nil:
            break  // nothing to draw until a fix names the place
        }
        locator.onFix = { [weak self] location in self?.fixed(location) }
        locator.start()

        let every = Timer(timeInterval: WeatherText.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        every.tolerance = 60
        RunLoop.main.add(every, forMode: .common)
        timer = every
        // After a sleep the temperature is old and the Mac may be somewhere else.
        wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
                self?.locator.locate()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        fallback?.invalidate()
        locator.stop()
        geocoder.cancelGeocode()
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
        session.invalidateAndCancel()
    }

    /// A fix: name it, remember it when it has a name, and read the temperature there.
    private func fixed(_ location: CLLocation) {
        gotFix = true
        fallback?.invalidate()
        let latitude = location.coordinate.latitude
        let longitude = location.coordinate.longitude
        geocoder.cancelGeocode()  // a newer fix wins over a lookup still running
        geocoder.reverseGeocodeLocation(location) { [weak self] marks, _ in
            let locality = marks?.first?.locality
            Task { @MainActor in
                guard let self else { return }
                let commune = PlaceRules.commune(named: locality, latitude: latitude, longitude: longitude, previous: self.named)
                self.place = (latitude, longitude, commune)
                if let named = Place.named(latitude: latitude, longitude: longitude, commune: locality, at: Date()) {
                    self.named = named
                    try? self.store.save(named)
                }
                self.refresh()
            }
        }
    }

    /// Reads the temperature for the current place; one read at a time, one more after it if asked meanwhile.
    private func refresh() {
        guard place != nil, gate.begin() else { return }
        Task { await self.fetch() }
    }

    private func fetch() async {
        repeat {
            guard let place else { break }
            let url = OpenMeteo.url(latitude: place.latitude, longitude: place.longitude)
            if let (data, response) = try? await session.data(from: url),
                (response as? HTTPURLResponse)?.statusCode == 200,
                let temperature = OpenMeteo.temperature(in: data)
            {
                label = WeatherText.label(commune: place.commune, temperature: temperature)
            }
        } while gate.end()
    }
}

/// Location Services for the weather box: one fix at start and on wake, then the significant changes (about 500 m) as
/// they come. Asks for the permission once (the app's Info.plist explains why); denied or not yet allowed, it is quiet
/// and the box uses the remembered place.
@MainActor
final class Locator: NSObject, CLLocationManagerDelegate {
    var onFix: ((CLLocation) -> Void)?
    private let manager = CLLocationManager()

    func start() {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        follow()
    }

    func stop() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.delegate = nil
    }

    /// One fix now (after a wake), when allowed.
    func locate() {
        if allowed { manager.requestLocation() }
    }

    /// The app asks for "when in use" (its Info.plist says so). On macOS that grant reads as `.authorized` (3), the
    /// value iOS calls when-in-use, which Swift marks deprecated here: compared by its raw value. Both count.
    private var allowed: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedAlways || status.rawValue == 3
    }

    private func follow() {
        guard allowed else { return }
        manager.startMonitoringSignificantLocationChanges()
        manager.requestLocation()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated { follow() }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let last = locations.last else { return }
        MainActor.assumeIsolated { onFix?(last) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        // No fix this time (no Wi-Fi around, denied): the remembered place stays; the next change or wake tries again.
    }
}

extension Theme {
    /// The weather item's icon: ICON_SIZE in Bold (sketchybarrc's icon.font="$NERD_FONT:Bold:$ICON_SIZE").
    static let boldIconFont = Font.custom(fontName, size: 15).bold()
}

/// The weather box (sketchybarrc's weather item): the pink thermometer with 5 points on each side, then the label with 5
/// after it; as wide as its text, like SketchyBar's. Not clickable, so no hover tint.
struct WeatherView: View {
    let model: WeatherModel

    var body: some View {
        BarBox(id: "weather") {
            HStack(spacing: 0) {
                Text("\u{F2C7}").font(Theme.boldIconFont).foregroundStyle(Theme.pink).fixedSize()
                    .padding(.horizontal, 5)
                if let label = model.label {
                    Text(label).font(Theme.mediumFont).foregroundStyle(Theme.text).fixedSize().padding(.trailing, 5)
                }
            }
        }
    }
}
