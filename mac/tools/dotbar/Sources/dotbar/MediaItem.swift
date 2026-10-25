import AppKit
import DotbarCore
import Observation
import SwiftUI

extension Theme {
    /// The Spotify logo while playing (GREEN of colors.sh); paused it is yellow.
    static let spotifyGreen = Color(hex: 0xa6da95)
    /// fa-spotify (SPOTIFY of icons.sh), at SPOTIFY_SIZE in bold.
    static let spotifyGlyph = "\u{F1BC}"
    static let spotifyFont = Font.custom(fontName, size: 20).bold()
    /// The room the logo takes at that size, as SketchyBar measured it.
    static let spotifyWidth: CGFloat = 19
}

/// Where media-control is (Homebrew): a login agent starts the bar with a bare PATH. macOS 15.4 and later keep MediaRemote
/// from third-party apps, and media-control reads it through a helper Apple allows.
func mediaControlPath() -> String {
    let candidates = ["/opt/homebrew/bin/media-control", "/usr/local/bin/media-control"]
    return candidates.first { FileManager.default.isExecutableFile(atPath: $0) } ?? candidates[0]
}

/// The now playing pill (media.sh): Spotify's track from one `media-control stream`, sliding open when a track loads and
/// closed when none is left, as SketchyBar animated it: the width over 24 frames on a sine curve with the box's color,
/// the text fading over 9 frames, in once the box is half open and out as it starts to close.
@MainActor
@Observable
final class MediaModel {
    /// What the pill draws. It stays while the pill slides closed, so the text fades out instead of vanishing.
    private(set) var track: NowPlaying?
    /// In the bar at all; false once it has slid closed.
    private(set) var drawn = false
    /// The characters the track may use (the fit narrows it so the pill stops short of Vorssaint).
    var maxLength = Media.maxLength
    /// How open the pill is, 0 to 1 (animated).
    private(set) var reveal: CGFloat = 0
    private(set) var textOpacity: Double = 0

    /// The track the player has now, which `track` lags behind while closing.
    @ObservationIgnored private var current: NowPlaying?
    /// Bumped by every slide: a step scheduled by an older one is dropped.
    @ObservationIgnored private var slide = 0
    @ObservationIgnored private var feed: MediaFeed?
    @ObservationIgnored private var wake: NSObjectProtocol?
    @ObservationIgnored private let runner: CommandRunner
    @ObservationIgnored private let mediaControl: String

    /// SketchyBar's frames are 60 a second: 24 for the slide, 9 for the text; the text starts 0.22 s into an opening.
    private static let slideAnimation = Animation.timingCurve(0.39, 0.575, 0.565, 1, duration: 0.4)
    private static let textAnimation = Animation.timingCurve(0.39, 0.575, 0.565, 1, duration: 0.15)
    private static let textDelay: TimeInterval = 0.22
    private static let slideSeconds: TimeInterval = 0.45

    init(runner: CommandRunner, mediaControl: String) {
        self.runner = runner
        self.mediaControl = mediaControl
    }

    func start() {
        let feed = MediaFeed(runner: runner, executable: mediaControl) { [weak self] reading in
            Task { @MainActor in self?.apply(reading) }
        }
        feed.start()
        self.feed = feed
        // Asleep, the stream may have missed the player quitting or the track changing.
        wake = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak feed] _ in
            Task { await feed?.refresh() }
        }
    }

    /// Ends the stream: the bar is quitting.
    func stop() {
        feed?.stop()
        if let wake { NSWorkspace.shared.notificationCenter.removeObserver(wake) }
    }

    func toggle() {
        guard let feed else { return }
        Task { await feed.toggle() }
    }

    private func apply(_ reading: MediaReading) {
        let change = MediaPill.change(shown: current, reading: reading)
        if case .track(let new) = reading { current = new } else if reading == .nothing { current = nil }
        switch change {
        case .open: open()
        case .update: track = current
        case .close: close()
        case .stay: break
        }
    }

    private func open() {
        slide += 1
        let mine = slide
        track = current
        if !drawn {
            drawn = true
            reveal = 0
            textOpacity = 0
        }
        // The next turn, once the pill is in the bar at width 0: an animation in the same update as its insertion would
        // not run.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.slide == mine else { return }
            withAnimation(Self.slideAnimation) { self.reveal = 1 }
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.textDelay) { [weak self] in
                guard let self, self.slide == mine else { return }
                withAnimation(Self.textAnimation) { self.textOpacity = 1 }
            }
        }
    }

    private func close() {
        slide += 1
        let mine = slide
        withAnimation(Self.textAnimation) { textOpacity = 0 }
        withAnimation(Self.slideAnimation) { reveal = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.slideSeconds) { [weak self] in
            guard let self, self.slide == mine else { return }
            self.drawn = false
            self.track = nil
        }
    }
}

/// Lays its content out at its own size and takes `progress` of its width: the pill slides open from the notch side.
struct Reveal: Layout {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let content = subviews.first else { return .zero }
        let size = content.sizeThatFits(.unspecified)
        return CGSize(width: size.width * max(0, min(1, progress)), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.minX, y: bounds.midY), anchor: .leading, proposal: .unspecified)
    }
}

/// The pill: the logo (green while playing, yellow paused), then "title  artist" (text while playing, dimmed paused),
/// as the media_icon and media items drew them. A click plays or pauses; the box has no hover tint, as before.
struct MediaView: View {
    let model: MediaModel

    var body: some View {
        if model.drawn, let track = model.track {
            Reveal(progress: model.reveal) {
                HStack(spacing: 0) {
                    // NerdIcon's trick at the logo's size: the space after the glyph gives it room to be drawn whole.
                    Text(Theme.spotifyGlyph + " ").font(Theme.spotifyFont)
                        .foregroundStyle(track.playing ? Theme.spotifyGreen : Theme.yellow)
                        .fixedSize()
                        // Placed where SketchyBar drew it, side by side by screenshot: 6 points in, 1.5 lower.
                        .offset(x: Theme.spotifyWidth / 4 - 2.5, y: 1.5)
                        .frame(width: Theme.spotifyWidth)
                        .padding(.leading, 6)
                        .padding(.trailing, 4)
                    Text(Media.text(track, maxLength: model.maxLength)).font(Theme.textFont)
                        .foregroundStyle(track.playing ? Theme.text : Theme.overlay0)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: 1)
                        // The label's 8 points and most of the item's 3: where SketchyBar's box ended, measured by screenshot.
                        .padding(.trailing, 10.5)
                }
                .opacity(model.textOpacity)
                .frame(height: Theme.pillHeight)
            }
            .background(RoundedRectangle(cornerRadius: Theme.pillRadius).fill(Theme.barColor).opacity(Double(model.reveal)))
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { model.toggle() }
        }
    }
}
