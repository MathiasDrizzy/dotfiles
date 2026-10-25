import CoreGraphics

/// Keeps every box of the bar from covering its neighbour or sitting under the camera housing, as fit.sh did:
///   left  - Apple, the front app, the workspaces and the moon and weather boxes share the strip left of the housing.
///           When they do not fit, the front app's name narrows first (down to `minNameWidth`), then workspaces leave
///           (the pill says "+N").
///   right - the track right of the housing may only reach Vorssaint: it gets a character budget.
public enum BarFit {
    /// SketchyBar's notch_width: the gap kept around the camera housing, centered, on a screen that has one.
    public static let notchWidth: CGFloat = 224
    public static let nameWidth: CGFloat = 94
    public static let minNameWidth: CGFloat = 40
    /// A workspace slot: its 26 points plus 1 of padding on each side.
    public static let slotStep: CGFloat = 28
    /// The "+N" a capped pill shows.
    public static let spareForMore: CGFloat = 28
    public static let gap: CGFloat = 5
    /// JetBrains Mono at 12 points: 7.2 points a character.
    public static let charWidth: CGFloat = 7.2
    /// The Spotify logo and the paddings of the track's box, and the separator between title and artist.
    public static let mediaOverhead: CGFloat = 70
    public static let mediaMinChars = 8
    public static let mediaMaxChars = 35

    /// The left and right edges of the gap around the camera housing; on a screen without one there is no gap and both
    /// sides meet in the middle.
    public static func notch(screenWidth: CGFloat, hasNotch: Bool) -> (left: CGFloat, right: CGFloat) {
        let width = hasNotch ? notchWidth : 0
        return ((screenWidth - width) / 2, (screenWidth + width) / 2)
    }

    public struct Left: Equatable, Sendable {
        public let nameWidth: CGFloat
        /// How many workspace slots fit; nil: all of them.
        public let cap: Int?

        public init(nameWidth: CGFloat, cap: Int?) {
            self.nameWidth = nameWidth
            self.cap = cap
        }
    }

    /// `room` is what the name and the workspace slots may use together: the strip left of the moon box, less every box
    /// of fixed width. `natural` is how many workspaces would show without a cap.
    public static func left(room: CGFloat, natural: Int) -> Left {
        let slots = CGFloat(natural) * slotStep
        guard room < nameWidth + slots else { return Left(nameWidth: nameWidth, cap: nil) }
        let name = room - slots
        if name >= minNameWidth { return Left(nameWidth: name.rounded(.down), cap: nil) }
        let cap = Int(((room - minNameWidth - spareForMore) / slotStep).rounded(.down))
        return Left(nameWidth: minNameWidth, cap: max(1, cap))
    }

    /// The characters the track may use, between the housing and Vorssaint.
    public static func mediaChars(notchRight: CGFloat, vorssaintLeft: CGFloat) -> Int {
        let room = vorssaintLeft - gap - notchRight - mediaOverhead
        let chars = Int((room / charWidth).rounded(.down))
        return min(mediaMaxChars, max(mediaMinChars, chars))
    }
}
