import SwiftUI
import AVFoundation
import AVKit

// MARK: - Rowan motion
// Plays a bundled Higgsfield clip of Rowan (HEVC with alpha, `.mov`) over
// whatever surface sits behind it, and degrades gracefully in this order:
//   1. Reduce Motion on → still pose from the same source artwork.
//   2. Clip missing / fails to load → still pose.
//   3. Plays once and holds on the final frame (brand rule: prefer a single
//      play-through over infinite looping) unless `loops` is set.
// The animation never carries required information — copy lives in native
// text next to it, so the view is accessibility-hidden by default.

struct RowanMotionView: View {
    let pose: KinrowsAsset.RowanPose
    var loops: Bool = false
    /// Plays only while this is true; flip it when the containing page is
    /// offscreen so background clips stop burning cycles.
    var isActive: Bool = true
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat? = nil
    var accessibility: KinrowsIllustration.Accessibility = .decorative

    var body: some View {
        KinrowsClipView(
            clipName: pose.motionClipName,
            still: .mascot(pose),
            loops: loops,
            isActive: isActive,
            maxWidth: maxWidth,
            maxHeight: maxHeight,
            accessibility: accessibility
        )
    }
}

/// The generic player behind RowanMotionView: any bundled HEVC-alpha clip
/// layered over its own still. Use directly for non-Rowan brand motion (the
/// crew paddling on the launch screen).
struct KinrowsClipView: View {
    /// Bundle resource name without extension (`.mov`); nil renders the still only.
    let clipName: String?
    let still: KinrowsAsset
    var loops: Bool = false
    var isActive: Bool = true
    var maxWidth: CGFloat? = nil
    var maxHeight: CGFloat? = nil
    var accessibility: KinrowsIllustration.Accessibility = .decorative

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var player = RowanClipPlayer()

    private var clipURL: URL? {
        guard let clipName else { return nil }
        return Bundle.main.url(forResource: clipName, withExtension: "mov")
    }

    var body: some View {
        ZStack {
            // The still is always underneath: it is the first paint and the
            // fallback, so there is never a blank box while the clip decodes.
            KinrowsIllustration(still, accessibility: accessibility, maxWidth: maxWidth, maxHeight: maxHeight)
                .opacity(player.isShowingVideo ? 0 : 1)

            if !reduceMotion, let clipURL {
                RowanClipLayerView(player: player.avPlayer)
                    .aspectRatio(1, contentMode: .fit)
                    .frame(maxWidth: maxWidth, maxHeight: maxHeight)
                    .opacity(player.isShowingVideo ? 1 : 0)
                    .accessibilityHidden(true)
                    .task(id: clipURL) { player.load(clipURL, loops: loops) }
                    .onChange(of: isActive, initial: true) { _, active in
                        active ? player.play() : player.pause()
                    }
                    .onDisappear { player.pause() }
            }
        }
        .animation(KinrowsBrand.Motion.standardCurve, value: player.isShowingVideo)
    }
}

/// Owns the AVPlayer so SwiftUI re-renders don't recreate it. `isShowingVideo`
/// flips true once the first frame is ready, and false if playback fails.
@MainActor
@Observable
final class RowanClipPlayer {
    let avPlayer = AVPlayer()
    private(set) var isShowingVideo = false
    private var loops = false
    private var endObserver: NSObjectProtocol?
    private var statusObservation: NSKeyValueObservation?
    private var loadedURL: URL?

    init() {
        avPlayer.isMuted = true
        avPlayer.actionAtItemEnd = .pause
        avPlayer.preventsDisplaySleepDuringVideoPlayback = false
    }

    func load(_ url: URL, loops: Bool) {
        guard loadedURL != url else { return }
        loadedURL = url
        self.loops = loops
        let item = AVPlayerItem(url: url)
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self else { return }
                switch item.status {
                case .readyToPlay: self.isShowingVideo = true
                case .failed: self.isShowingVideo = false
                default: break
                }
            }
        }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.loops {
                    self.avPlayer.seek(to: .zero)
                    self.avPlayer.play()
                }
                // Not looping: actionAtItemEnd = .pause holds the last frame.
            }
        }
        avPlayer.replaceCurrentItem(with: item)
    }

    func play() {
        guard avPlayer.currentItem != nil else { return }
        avPlayer.play()
    }

    func pause() { avPlayer.pause() }

    /// Restart from the first frame (e.g. a page came back into view).
    func replay() {
        avPlayer.seek(to: .zero)
        avPlayer.play()
    }
}

/// A bare AVPlayerLayer host — no controls, transparent backing so the alpha
/// channel of the HEVC clip composites over the SwiftUI surface beneath.
struct RowanClipLayerView: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.playerLayer.videoGravity = .resizeAspect
        view.playerLayer.pixelBufferAttributes = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        view.backgroundColor = .clear
        view.isOpaque = false
        return view
    }

    func updateUIView(_ uiView: PlayerLayerView, context: Context) {
        if uiView.playerLayer.player !== player { uiView.playerLayer.player = player }
    }

    final class PlayerLayerView: UIView {
        override static var layerClass: AnyClass { AVPlayerLayer.self }
        var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
    }
}

#Preview("Rowan waves") {
    ZStack {
        AmbientBackground(style: .home)
        VStack(spacing: 16) {
            RowanMotionView(pose: .wave, maxWidth: 220, maxHeight: 220)
            Text("Hi, I'm Rowan.")
                .font(.flDisplay)
                .foregroundStyle(WarmPalette.ink1)
        }
    }
}

#Preview("Thinking loop") {
    ZStack {
        AmbientBackground(style: .home)
        RowanMotionView(pose: .thinking, loops: true, maxWidth: 120, maxHeight: 120)
    }
}
