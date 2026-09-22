import AppKit
import AVFoundation
import CoreImage
import SwiftUI

/// Blur the decoded frames themselves so the preview matches the moving content.
struct BlurPreviewVideo: NSViewRepresentable {
    let url: URL
    let strength: Double

    func makeNSView(context: Context) -> BlurPreviewPlayerView {
        BlurPreviewPlayerView(url: url, strength: strength)
    }

    func updateNSView(_ view: BlurPreviewPlayerView, context: Context) {
        view.update(strength: strength)
    }

    static func dismantleNSView(_ view: BlurPreviewPlayerView, coordinator: ()) {
        view.stop()
    }
}

private final class PreviewBlurState: @unchecked Sendable {
    private let lock = NSLock()
    private var strength: Double
    private var width: CGFloat = 460

    init(strength: Double) { self.strength = strength }

    func update(strength: Double? = nil, width: CGFloat? = nil) {
        lock.lock()
        defer { lock.unlock() }
        if let strength { self.strength = strength }
        if let width, width > 0 { self.width = width }
    }

    func radius(for imageWidth: CGFloat) -> CGFloat {
        lock.lock()
        defer { lock.unlock() }
        return strength / 6 * imageWidth / width
    }
}

final class BlurPreviewPlayerView: NSView {
    private let player = AVQueuePlayer()
    private let playerLayer = AVPlayerLayer()
    private let blur: PreviewBlurState
    private var looper: AVPlayerLooper?
    private var visibilityTimer: Timer?

    init(url: URL, strength: Double) {
        blur = PreviewBlurState(strength: strength)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.backgroundColor = NSColor(white: 0.96, alpha: 1).cgColor
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
        player.isMuted = true
        player.preventsDisplaySleepDuringVideoPlayback = false

        let asset = AVURLAsset(url: url)
        let item = AVPlayerItem(asset: asset)
        let blur = self.blur
        let context = CIContext(options: [.cacheIntermediates: false])
        item.videoComposition = AVVideoComposition(asset: asset) { request in
            let source = request.sourceImage
            let filtered = source.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: blur.radius(for: source.extent.width)])
                .cropped(to: source.extent)
            request.finish(with: filtered, context: context)
        }
        looper = AVPlayerLooper(player: player, templateItem: item)

        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updatePlayback() }
        }
        visibilityTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    required init?(coder: NSCoder) { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
        blur.update(width: bounds.width)
        updatePlayback()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePlayback()
    }

    func update(strength: Double) { blur.update(strength: strength) }

    private func updatePlayback() {
        let visible = window.map { $0.isVisible && !$0.isMiniaturized && $0.occlusionState.contains(.visible) } ?? false
        if visible && NSApp.isActive && !visibleRect.isEmpty {
            if player.rate == 0 { player.play() }
        } else {
            player.pause()
        }
    }

    func stop() {
        visibilityTimer?.invalidate()
        visibilityTimer = nil
        player.pause()
        looper?.disableLooping()
        looper = nil
        player.removeAllItems()
        playerLayer.player = nil
    }

    deinit { visibilityTimer?.invalidate() }
}
