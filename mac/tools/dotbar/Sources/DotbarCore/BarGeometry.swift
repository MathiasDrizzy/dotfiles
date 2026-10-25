import CoreGraphics

/// Where the bar sits on a screen. AppKit puts the origin at the bottom left of the screen, y growing upwards.
public enum BarEdge: String, Sendable {
    case top
    /// Development only: drawn at the bottom, next to SketchyBar, until dotbar replaces it.
    case bottom
}

public enum BarGeometry {
    /// The bar's height in points: SketchyBar's, so the boxes keep their size and the cover hides the same strip.
    public static let height: CGFloat = 40

    /// The bar's frame on a screen whose full frame is `screen`: the whole width, `height` tall, at `edge`.
    public static func frame(on screen: CGRect, edge: BarEdge, height: CGFloat = BarGeometry.height) -> CGRect {
        let y = edge == .top ? screen.maxY - height : screen.minY
        return CGRect(x: screen.minX, y: y, width: screen.width, height: height)
    }
}
