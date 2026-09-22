// Clinton Imaro was here 20/09/2026.

import AppKit
import QuartzCore
import ScreenCaptureKit
import ShieldCore
import OSLog

final class ShieldPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

final class ShieldSurface {
    let panel: ShieldPanel
    private let imageLayer = CALayer()
    private let gradient = CAGradientLayer()
    private let startupCover = CALayer()
    private static let maskPositions = stride(from: 0.0, through: 1.0, by: 1.0 / 64).map { $0 }
    private static let maskLocations = maskPositions.map(NSNumber.init(value:))
    private var requestedCoverage = 0.0
    var hasImage: Bool { imageLayer.contents != nil }

    init(screen: NSScreen, includeInCaptures: Bool = false) {
        panel = ShieldPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "QuietGlass Blur"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = includeInCaptures ? .readOnly : .none
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = imageLayer
        imageLayer.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resize
        startupCover.backgroundColor = DisplayCapture.background
        startupCover.opacity = 0
        imageLayer.addSublayer(startupCover)
        gradient.locations = Self.maskLocations
        panel.contentView = view
    }

    func resize(to frame: NSRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        imageLayer.frame = NSRect(origin: .zero, size: frame.size)
        gradient.frame = imageLayer.bounds
        startupCover.frame = imageLayer.bounds
        CATransaction.commit()
    }

    func keepVisible() {
        guard requestedCoverage > 0, hasImage || imageLayer.backgroundColor != nil else { return }
        panel.orderFrontRegardless()
    }

    func update(coverage: Double, direction: ShieldDirection) {
        requestedCoverage = coverage
        guard coverage > 0 else { panel.orderOut(nil); return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.backgroundColor = hasImage ? nil : DisplayCapture.background
        gradient.frame = imageLayer.bounds
        switch direction {
        case .left: gradient.startPoint = CGPoint(x: 0, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 0.5)
        case .right: gradient.startPoint = CGPoint(x: 1, y: 0.5); gradient.endPoint = CGPoint(x: 0, y: 0.5)
        case .up: gradient.startPoint = CGPoint(x: 0.5, y: 1); gradient.endPoint = CGPoint(x: 0.5, y: 0)
        case .down: gradient.startPoint = CGPoint(x: 0.5, y: 0); gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        gradient.colors = Self.maskPositions.map { NSColor.black.withAlphaComponent(GlassMask.opacity(position: $0, coverage: coverage)).cgColor }
        imageLayer.mask = coverage >= 0.999 ? nil : gradient
        CATransaction.commit()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func setImage(_ image: CGImage) {
        let revealFirstFrame = !hasImage && requestedCoverage > 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.backgroundColor = nil
        if revealFirstFrame {
            // Fade the temporary cover onto already-blurred pixels. Never fade
            // the panel itself, which would expose the clear desktop beneath it.
            startupCover.frame = imageLayer.bounds
            let reveal = CABasicAnimation(keyPath: "opacity")
            reveal.fromValue = 1
            reveal.toValue = 0
            reveal.duration = 0.22
            reveal.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            startupCover.add(reveal, forKey: "firstFrame")
        }
        CATransaction.commit()
    }

    func clear() {
        requestedCoverage = 0
        panel.orderOut(nil)
        startupCover.removeAllAnimations()
        imageLayer.contents = nil
        imageLayer.backgroundColor = nil
    }
}

@MainActor
private final class ShieldFrameTarget: NSObject {
    weak var overlay: ShieldOverlay?

    @objc func drawFrame(_ link: CADisplayLink) {
        guard let overlay else { link.invalidate(); return }
        overlay.animate(link)
    }
}

@MainActor
final class ShieldOverlay {
    var onClear: (() -> Void)?
    var onCaptureStatus: ((String?) -> Void)?
    var onPermissionDenied: (() -> Void)?
    var includeInCaptures = false {
        didSet {
            for surface in surfaces.values {
                surface.panel.sharingType = includeInCaptures ? .readOnly : .none
            }
        }
    }
    private(set) var surfaces: [CGDirectDisplayID: ShieldSurface] = [:]
    private var captures: [CGDirectDisplayID: DisplayCapture] = [:]
    private var captureTask: Task<Void, Never>?
    private var pendingFade: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var animationLink: CADisplayLink?
    private let frameTarget = ShieldFrameTarget()
    private var generation = 0
    private var active = false
    private var displayedCoverage = 0.0
    private var targetCoverage = 0.0
    private var transition = GlassTransition()
    private var displayTargets: [CGDirectDisplayID: Double]?
    private var displayTransitions: [CGDirectDisplayID: GlassTransition] = [:]
    private var displayValues: [CGDirectDisplayID: Double] = [:]
    private var lastFrameTime: CFTimeInterval?
    private var direction: ShieldDirection = .left
    private var blurRadius = 28.0
    private let logger = Logger(subsystem: "local.clinton.QuietGlass", category: "Blur")
    var isCapturing: Bool { !captures.isEmpty }

    func show(coverage: Double, direction: ShieldDirection, blurRadius: Double, displays: [CGDirectDisplayID: Double]? = nil) {
        guard coverage > 0.001 else { fadeOut(); return }
        pendingFade?.cancel(); pendingFade = nil
        if surfaces.isEmpty { reconcileScreens() }
        displayTargets = displays
        targetCoverage = max(0, min(1, coverage))
        if self.blurRadius != blurRadius {
            self.blurRadius = blurRadius
            for capture in captures.values { capture.setRadius(blurRadius) }
        }
        if !active {
            self.direction = direction
            active = true
            capture()
            refreshTimer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.restoreVisibility()
                    self.capture()
                }
            }
            RunLoop.main.add(refreshTimer!, forMode: .common)
        }
        startAnimation()
    }

    func fadeOut() {
        guard active, targetCoverage > 0, pendingFade == nil else { return }
        pendingFade = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard let self else { return }
            self.pendingFade = nil
            self.displayTargets = nil
            self.targetCoverage = 0
            if self.displayedCoverage == 0 { self.clear() }
            else { self.startAnimation() }
        }
    }

    private func startAnimation() {
        let hasUnsettledDisplay = surfaces.keys.contains {
            (displayValues[$0] ?? 0) != (displayTargets?[$0] ?? targetCoverage)
        }
        guard animationLink == nil, displayedCoverage != targetCoverage || hasUnsettledDisplay,
              let screen = NSScreen.screens.max(by: { $0.maximumFramesPerSecond < $1.maximumFramesPerSecond }) else { return }
        frameTarget.overlay = self
        let link = screen.displayLink(target: frameTarget, selector: #selector(ShieldFrameTarget.drawFrame(_:)))
        let frameRate = Float(screen.maximumFramesPerSecond > 0 ? screen.maximumFramesPerSecond : 60)
        link.preferredFrameRateRange = CAFrameRateRange(minimum: min(60, frameRate), maximum: frameRate, preferred: frameRate)
        lastFrameTime = nil
        animationLink = link
        link.add(to: .main, forMode: .common)
    }

    fileprivate func animate(_ link: CADisplayLink) {
        guard link === animationLink else { return }
        let now = link.targetTimestamp
        let elapsed = now - (lastFrameTime ?? link.timestamp)
        displayedCoverage = transition.advance(to: targetCoverage, elapsed: elapsed)
        lastFrameTime = now
        var settled = true
        for (id, surface) in surfaces {
            let target = displayTargets?[id] ?? targetCoverage
            var animation = displayTransitions[id] ?? GlassTransition()
            let value = animation.advance(to: target, elapsed: elapsed)
            displayTransitions[id] = animation
            displayValues[id] = value
            surface.update(coverage: value, direction: direction)
            if value != target { settled = false }
        }
        if settled, displayedCoverage == targetCoverage {
            animationLink?.invalidate()
            animationLink = nil
            if targetCoverage == 0 { clear() }
        }
    }

    func clear() {
        let wasActive = active
        active = false
        pendingFade?.cancel(); pendingFade = nil
        generation += 1
        animationLink?.invalidate(); animationLink = nil
        lastFrameTime = nil
        refreshTimer?.invalidate(); refreshTimer = nil
        captureTask?.cancel(); captureTask = nil
        for capture in captures.values { capture.stop() }
        captures.removeAll()
        displayedCoverage = 0
        targetCoverage = 0
        transition.reset()
        displayTargets = nil
        displayTransitions = [:]
        displayValues = [:]
        for surface in surfaces.values { surface.clear() }
        if wasActive { onClear?() }
    }

    func reconcileScreens() {
        var currentDisplays = Set<CGDirectDisplayID>()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            let id = number.uint32Value
            currentDisplays.insert(id)
            if let surface = surfaces[id] {
                if surface.panel.frame != screen.frame {
                    surface.resize(to: screen.frame)
                    captures.removeValue(forKey: id)?.stop()
                }
            } else { surfaces[id] = ShieldSurface(screen: screen, includeInCaptures: includeInCaptures) }
        }
        for id in Set(surfaces.keys).subtracting(currentDisplays) {
            captures.removeValue(forKey: id)?.stop()
            surfaces.removeValue(forKey: id)?.panel.close()
        }
        restoreVisibility()
        capture()
        // A display link belongs to its screen. Rebind after display changes
        // so unplugging a monitor cannot strand an unfinished transition.
        if animationLink != nil {
            animationLink?.invalidate(); animationLink = nil
            startAnimation()
        }
    }

    func activeSpaceChanged() {
        guard active else { return }
        logger.info("Space changed; retaining blur coverage and display surfaces")
        reconcileScreens()
    }

    private func restoreVisibility() {
        guard active else { return }
        for (id, surface) in surfaces {
            surface.update(coverage: displayValues[id] ?? displayedCoverage, direction: direction)
            surface.keepVisible()
        }
    }

    private func capture() {
        guard active, targetCoverage > 0, captureTask == nil,
              !Set(surfaces.keys).subtracting(captures.keys).isEmpty else { return }
        let token = generation
        let radius = blurRadius
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.captureTask = nil } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard !Task.isCancelled, self.active, self.generation == token else { return }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !ownApps.isEmpty else { return }
                for display in content.displays {
                    let id = display.displayID
                    guard self.surfaces[id] != nil, self.captures[id] == nil else { continue }
                    guard !Task.isCancelled, self.active, self.generation == token else { return }
                    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                    if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                    let config = SCStreamConfiguration()
                    config.width = max(1, display.width)
                    config.height = max(1, display.height)
                    config.backgroundColor = DisplayCapture.background
                    config.shouldBeOpaque = true
                    config.showsCursor = false
                    config.scalesToFit = true
                    config.preservesAspectRatio = true
                    config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
                    config.queueDepth = 3
                    config.capturesAudio = false
                    config.pixelFormat = kCVPixelFormatType_32BGRA
                    let sessionID = UUID()
                    let capture = DisplayCapture(id: sessionID, filter: filter, configuration: config, radius: radius,
                        onFrame: { [weak self] image in
                            guard let self, self.active, self.generation == token,
                                  self.captures[id]?.id == sessionID else { return }
                            self.surfaces[id]?.setImage(image)
                            self.surfaces[id]?.update(coverage: self.displayValues[id] ?? self.displayedCoverage, direction: self.direction)
                            self.startAnimation()
                            self.onCaptureStatus?(nil)
                        }, onFailure: { [weak self] error in
                            guard let self, self.generation == token,
                                  self.captures[id]?.id == sessionID else { return }
                            self.captures.removeValue(forKey: id)?.stop()
                            self.captureFailed(error)
                        })
                    self.captures[id] = capture
                    do { try await capture.start() }
                    catch {
                        guard self.generation == token else { return }
                        self.captures.removeValue(forKey: id)?.stop()
                        throw error
                    }
                    guard !Task.isCancelled, self.active, self.generation == token,
                          self.captures[id]?.id == sessionID else { capture.stop(); return }
                }
                self.onCaptureStatus?(nil)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.captureFailed(error)
            }
        }
    }

    private func captureFailed(_ error: Error) {
        let failure = error as NSError
        logger.error("Capture failure \(failure.domain, privacy: .public):\(failure.code)")
        if failure.domain == SCStreamErrorDomain, failure.code == SCStreamError.Code.userDeclined.rawValue {
            clear()
            onPermissionDenied?()
        } else {
            onCaptureStatus?("Reconnecting screen blur…")
        }
    }
}
