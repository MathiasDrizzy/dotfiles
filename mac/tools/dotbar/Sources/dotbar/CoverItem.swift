import AppKit
import DotbarCore
import Observation
import SwiftUI

extension Theme {
    /// The cover while no picture of the wallpaper is ready: Catppuccin Macchiato's crust, cover.sh's fallback.
    static let crust = Color(hex: 0x181926)
}

/// The cover (cover.sh and the rc's `cover` bracket). With the menu bar set to hide always, the system slides its own bar
/// down while the pointer is at the top of the screen and while Control Center or a menu bar extra is open; the bar's
/// window sits one level above it but is transparent between the boxes, so the cover fills the whole strip with the
/// wallpaper as the desktop shows it there: the native bar stays hidden and the bar still looks like the desktop.
///
/// The picture is the wallpaper file itself (`NSWorkspace.desktopImageURL(for:)`), laid out with the desktop's own options
/// (fill, fit, stretch, center and the fill color) and cut to the bar's strip once per change. SketchyBar's cover took a
/// screenshot instead (`ctlcenter backdrop`, ScreenCaptureKit): it needs the Screen Recording permission, a capture can
/// only be taken while nothing covers the strip, and it hung for days at 10% of a core. The file needs no permission and
/// no process, cannot hang the bar, and is never stale: it is read again when the wallpaper store changes (a file system
/// event, no polling), when the Space or the screens change, and after a wake.
///
/// Nothing runs while the cover is idle: the pointer is followed from AppKit's event monitors, and only a release of the
/// cover checks, five times a second and for two minutes at most, whether anything still needs it (cover.sh settle).
@MainActor
@Observable
final class CoverModel {
    private(set) var shown = false
    private(set) var picture: CGImage?
    private(set) var pictureScale: CGFloat = 2

    /// Apps whose panels and menus bring the native bar down: Control Center and Vorssaint (colors.sh MENU_EXTRA_BUNDLE).
    static let popupBundles = ["com.apple.controlcenter", "com.vorssaint.utils"]
    private static let settleCheck: TimeInterval = 0.2
    /// The native bar takes this long to slide away once the pointer leaves the top (drag.sh's COVER_GRACE).
    private static let awayGrace: TimeInterval = 0.6
    /// A panel or menu just asked for takes a moment to show (cover.sh's MENU_DELAY).
    private static let releaseDelay: TimeInterval = 0.5
    /// macOS rewrites its index on every wallpaper change; the new desktop URL can lag the file a moment.
    private static let wallpaperStore = NSHomeDirectory() + "/Library/Application Support/com.apple.wallpaper/Store"
    private static let wallpaperDelay: TimeInterval = 1

    @ObservationIgnored private let edge: BarEdge
    @ObservationIgnored private var holds: Set<String> = []
    /// Holds that end on their own (a popover closed by the user, not by the bar): checked each time the cover asks.
    @ObservationIgnored private var holdChecks: [String: () -> Bool] = [:]
    @ObservationIgnored private var holdSince: [String: Date] = [:]
    /// A popover reported open may not be a window yet: its hold is not checked for this long.
    private static let holdGrace: TimeInterval = 1.5
    @ObservationIgnored private var atTop = false
    @ObservationIgnored private var monitors: [Any] = []
    @ObservationIgnored private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    @ObservationIgnored private var settle: CoverSettle?
    @ObservationIgnored private var settleTimer: Timer?
    @ObservationIgnored private var storeWatch: [DispatchSourceFileSystemObject] = []
    @ObservationIgnored private var reload: DispatchWorkItem?
    @ObservationIgnored private var loaded: WallpaperKey?
    @ObservationIgnored private var generation = 0

    init(edge: BarEdge) {
        self.edge = edge
    }

    func start() {
        loadWallpaper()
        watchStore()
        // Moves over other apps reach the global monitor, moves over the bar's own boxes the local one; either way the
        // pointer's position is read from the event system, so it holds whichever window is under it.
        let global: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]
        if let monitor = NSEvent.addGlobalMonitorForEvents(matching: global, handler: { [weak self] _ in
            MainActor.assumeIsolated { self?.pointerMoved() }
        }) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: global.union([.mouseEntered, .mouseExited]),
            handler: { [weak self] event in
                MainActor.assumeIsolated { self?.pointerMoved() }
                return event
            })
        {
            monitors.append(monitor)
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            observe(workspace, name)
        }
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification)
    }

    /// Everything the cover started ends with the bar: monitors, observers, the store watch and any timer.
    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        observers.forEach { center, token in center.removeObserver(token) }
        observers = []
        storeWatch.forEach { $0.cancel() }
        storeWatch = []
        reload?.cancel()
        settleTimer?.invalidate()
        settleTimer = nil
        settle = nil
    }

    /// Keeps the cover on for `reason` (the Control Center driver, a menu being opened) until `release`.
    func hold(_ reason: String, while stillNeeded: (() -> Bool)? = nil) {
        holds.insert(reason)
        holdChecks[reason] = stillNeeded
        holdSince[reason] = Date()
        shown = true
        // Checked once the grace is over, not only at the next event: a popover closed meanwhile lets the cover go.
        if stillNeeded != nil { settleSoon(after: Self.holdGrace + 0.1) }
    }

    /// Lets go of `reason`; the cover comes off once nothing else needs it.
    func release(_ reason: String) {
        holds.remove(reason)
        holdChecks[reason] = nil
        holdSince[reason] = nil
        settleSoon(after: Self.releaseDelay)
    }

    /// The pointer is in the strip at the top of the Mac's own screen where the native bar reveals itself.
    static func pointerAtTop() -> Bool {
        TopStrip.contains(CGEvent(source: nil)?.location ?? .zero, mainDisplay: CGDisplayBounds(CGMainDisplayID()))
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.loadWallpaper() }
        }
        observers.append((center, token))
    }

    private func pointerMoved() {
        let top = Self.pointerAtTop()
        guard top != atTop else { return }
        atTop = top
        if top {
            shown = true
        } else {
            settleSoon(after: Self.awayGrace)
        }
    }

    private func needed() -> Bool {
        for (reason, check) in holdChecks
        where Date().timeIntervalSince(holdSince[reason] ?? .distantPast) > Self.holdGrace && !check() {
            holds.remove(reason)
            holdChecks[reason] = nil
            holdSince[reason] = nil
        }
        return Self.pointerAtTop() || !holds.isEmpty || ScreenWindows.popupOpen(bundles: Self.popupBundles)
    }

    /// Past the waiter's two minutes, something still needs the cover (a panel left open): look again this often.
    private static let recheckAfterCap: TimeInterval = 10

    /// One waiter at a time (cover.sh settle): it hides the cover once nothing has needed it for a few checks, or after two
    /// minutes if nothing needs it then.
    private func settleSoon(after delay: TimeInterval) {
        guard shown, settle == nil else { return }
        settle = CoverSettle()
        let timer = Timer(fire: Date().addingTimeInterval(delay), interval: Self.settleCheck, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkSettle() }
        }
        RunLoop.main.add(timer, forMode: .common)
        settleTimer = timer
    }

    private func checkSettle() {
        let isNeeded = needed()
        guard settle?.check(needed: isNeeded) == true else { return }
        settleTimer?.invalidate()
        settleTimer = nil
        settle = nil
        if needed() {
            settleSoon(after: Self.recheckAfterCap)
        } else {
            shown = false
        }
    }

    // MARK: The wallpaper

    /// The store's directory and its index: the index is replaced on a change, so both are watched and the watch is set up
    /// again after every event.
    private func watchStore() {
        storeWatch.forEach { $0.cancel() }
        storeWatch = []
        for path in [Self.wallpaperStore, Self.wallpaperStore + "/Index.plist"] {
            let descriptor = open(path, O_EVTONLY)
            guard descriptor >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(
                fileDescriptor: descriptor, eventMask: [.write, .delete, .rename, .extend, .attrib], queue: .main)
            source.setEventHandler { [weak self] in
                MainActor.assumeIsolated { self?.storeChanged() }
            }
            source.setCancelHandler { close(descriptor) }
            source.resume()
            storeWatch.append(source)
        }
    }

    private func storeChanged() {
        reload?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.watchStore()
                self?.loadWallpaper()
            }
        }
        reload = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.wallpaperDelay, execute: work)
    }

    /// Reads the desktop's picture and options for the main display and, when they changed, cuts the bar's strip from the
    /// picture off the main thread (a 4K picture takes a moment to decode).
    private func loadWallpaper() {
        guard let screen = NSScreen.screens.first, let url = NSWorkspace.shared.desktopImageURL(for: screen) else {
            loaded = nil
            picture = nil
            return
        }
        let options = NSWorkspace.shared.desktopImageOptions(for: screen) ?? [:]
        let scaling = WallpaperScaling(
            scaling: (options[.imageScaling] as? NSNumber)?.intValue ?? 3,
            allowClipping: (options[.allowClipping] as? NSNumber)?.boolValue ?? true)
        let fill = (options[.fillColor] as? NSColor)?.usingColorSpace(.sRGB)
        let size = screen.frame.size
        let strip = CGRect(
            x: 0, y: edge == .top ? 0 : size.height - BarGeometry.height, width: size.width, height: BarGeometry.height)
        let key = WallpaperKey(
            url: url, modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
            scaling: scaling,
            fill: fill.map { [$0.redComponent, $0.greenComponent, $0.blueComponent] } ?? [0.094, 0.098, 0.149],
            screen: size, scale: screen.backingScaleFactor, strip: strip)
        guard key != loaded else { return }
        loaded = key
        generation += 1
        let current = generation
        Task.detached(priority: .utility) {
            let rendered = WallpaperKey.render(key)
            await MainActor.run { [weak self] in
                guard let self, self.generation == current else { return }
                self.picture = rendered?.image
                self.pictureScale = key.scale
            }
        }
    }
}

/// What the strip was cut from: a new picture is made only when one of these changes.
struct WallpaperKey: Equatable, Sendable {
    let url: URL
    let modified: Date?
    let scaling: WallpaperScaling
    let fill: [CGFloat]
    let screen: CGSize
    let scale: CGFloat
    let strip: CGRect

    /// A picture is immutable once made: safe to hand from the decoding task to the main thread.
    struct Picture: @unchecked Sendable {
        let image: CGImage
    }

    /// The strip as the desktop shows it, at the screen's pixel density: the fill color, then the part of the picture
    /// that reaches the strip, where the desktop puts it.
    nonisolated static func render(_ key: WallpaperKey) -> Picture? {
        let width = Int((key.strip.width * key.scale).rounded())
        let height = Int((key.strip.height * key.scale).rounded())
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
        else { return nil }
        context.setFillColor(CGColor(srgbRed: key.fill[0], green: key.fill[1], blue: key.fill[2], alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let source = CGImageSourceCreateWithURL(key.url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return context.makeImage().map(Picture.init) }
        let pixels = CGSize(width: image.width, height: image.height)
        // Center shows the picture a pixel per screen pixel; the other layouts only depend on its proportions.
        let size = key.scaling == .center ? CGSize(width: pixels.width / key.scale, height: pixels.height / key.scale) : pixels
        let placement = WallpaperStrip.placement(image: size, screen: key.screen, scaling: key.scaling)
        if let piece = WallpaperStrip.crop(placement: placement, pixels: pixels, strip: key.strip) {
            // Whole pixels of the picture, and the exact spot those land on, so the strip lines up with the desktop.
            let whole = piece.source.integral.intersection(CGRect(origin: .zero, size: pixels))
            let pointsPerPixel = CGSize(width: placement.width / pixels.width, height: placement.height / pixels.height)
            let landing = CGRect(
                x: placement.minX + whole.minX * pointsPerPixel.width - key.strip.minX,
                y: placement.minY + whole.minY * pointsPerPixel.height - key.strip.minY,
                width: whole.width * pointsPerPixel.width, height: whole.height * pointsPerPixel.height)
            if let cut = image.cropping(to: whole) {
                context.interpolationQuality = .high
                // The context's origin is at the bottom left.
                context.draw(
                    cut,
                    in: CGRect(
                        x: landing.minX * key.scale, y: (key.strip.height - landing.maxY) * key.scale,
                        width: landing.width * key.scale, height: landing.height * key.scale))
            }
        }
        return context.makeImage().map(Picture.init)
    }
}

/// The cover behind every box: the wallpaper's strip while it is on, nothing otherwise.
struct CoverView: View {
    let model: CoverModel

    var body: some View {
        if model.shown {
            if let picture = model.picture {
                Image(decorative: picture, scale: model.pictureScale).resizable().interpolation(.high)
            } else {
                Theme.crust
            }
        }
    }
}
