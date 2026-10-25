import CoreGraphics

/// When the cover may come off (cover.sh settle): once nothing has needed it for `idleChecks` checks in a row, the native
/// bar having had a moment to slide away; or after `maxChecks` (two minutes at five checks a second), when the caller only
/// hides it if nothing needs it then.
public struct CoverSettle: Sendable {
    public static let idleChecks = 3
    public static let maxChecks = 600

    private var idle = 0
    private var checks = 0

    public init() {}

    /// Whether to stop waiting.
    public mutating func check(needed: Bool) -> Bool {
        checks += 1
        idle = needed ? 0 : idle + 1
        return idle >= Self.idleChecks || checks >= Self.maxChecks
    }
}

/// How the desktop lays its picture on the screen (System Settings' Fill, Fit, Stretch and Center).
public enum WallpaperScaling: Sendable, Equatable {
    case fill
    case fit
    case stretch
    case center
    /// Fit, but never larger than the picture's own size.
    case shrink

    /// From NSWorkspace's desktop image options: NSImageScaling's raw value and whether the picture may be cut.
    public init(scaling: Int, allowClipping: Bool) {
        switch scaling {
        case 1: self = .stretch
        case 2: self = .center
        case 0: self = .shrink
        default: self = allowClipping ? .fill : .fit
        }
    }
}

/// The part of the wallpaper the desktop shows behind the bar, so the cover can draw it where it is on screen.
public enum WallpaperStrip {
    /// Where the picture of `image` size lies on a screen of `screen` size, top-left origin, centered as the desktop
    /// centers it.
    public static func placement(image: CGSize, screen: CGSize, scaling: WallpaperScaling) -> CGRect {
        guard image.width > 0, image.height > 0 else { return CGRect(origin: .zero, size: screen) }
        let widthRatio = screen.width / image.width
        let heightRatio = screen.height / image.height
        let scale: CGFloat
        switch scaling {
        case .stretch: return CGRect(origin: .zero, size: screen)
        case .fill: scale = max(widthRatio, heightRatio)
        case .fit: scale = min(widthRatio, heightRatio)
        case .shrink: scale = min(1, min(widthRatio, heightRatio))
        case .center: scale = 1
        }
        let size = CGSize(width: image.width * scale, height: image.height * scale)
        return CGRect(
            x: (screen.width - size.width) / 2, y: (screen.height - size.height) / 2, width: size.width, height: size.height)
    }

    /// The part of the picture (in its `pixels`, top-left origin) that the desktop shows in `strip` (screen points), and
    /// where it goes in the strip (points from the strip's top left). Nil when the picture does not reach the strip and the
    /// desktop shows only its fill color there.
    public static func crop(placement: CGRect, pixels: CGSize, strip: CGRect) -> (source: CGRect, destination: CGRect)? {
        let shown = placement.intersection(strip)
        guard !shown.isNull, shown.width > 0, shown.height > 0, placement.width > 0, placement.height > 0 else { return nil }
        let xScale = pixels.width / placement.width
        let yScale = pixels.height / placement.height
        let source = CGRect(
            x: (shown.minX - placement.minX) * xScale, y: (shown.minY - placement.minY) * yScale,
            width: shown.width * xScale, height: shown.height * yScale)
        let destination = shown.offsetBy(dx: -strip.minX, dy: -strip.minY)
        return (source, destination)
    }
}
