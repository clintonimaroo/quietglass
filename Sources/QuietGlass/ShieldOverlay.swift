// Clinton Imaro was here 20/09/2026.

import AppKit
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
        panel.contentView = view
    }

    func resize(to frame: NSRect) {
        guard panel.frame != frame else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        panel.setFrame(frame, display: true)
        imageLayer.frame = NSRect(origin: .zero, size: frame.size)
        gradient.frame = imageLayer.bounds
        CATransaction.commit()
    }

    func keepVisible() {
        guard hasImage else { return }
        panel.orderFrontRegardless()
    }

    func update(coverage: Double, direction: ShieldDirection) {
        guard hasImage else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = imageLayer.bounds
        switch direction {
        case .left: gradient.startPoint = CGPoint(x: 0, y: 0.5); gradient.endPoint = CGPoint(x: 1, y: 0.5)
        case .right: gradient.startPoint = CGPoint(x: 1, y: 0.5); gradient.endPoint = CGPoint(x: 0, y: 0.5)
        case .up: gradient.startPoint = CGPoint(x: 0.5, y: 1); gradient.endPoint = CGPoint(x: 0.5, y: 0)
        case .down: gradient.startPoint = CGPoint(x: 0.5, y: 0); gradient.endPoint = CGPoint(x: 0.5, y: 1)
        }
        let positions = stride(from: 0.0, through: 1.0, by: 1.0 / 32).map { $0 }
        gradient.colors = positions.map { NSColor.black.withAlphaComponent(GlassMask.opacity(position: $0, coverage: coverage)).cgColor }
        gradient.locations = positions.map(NSNumber.init(value:))
        imageLayer.mask = coverage >= 0.999 ? nil : gradient
        CATransaction.commit()
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func setImage(_ image: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        CATransaction.commit()
    }

    func clear() {
        panel.orderOut(nil)
        imageLayer.contents = nil
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
    private var animationTimer: Timer?
    private var generation = 0
    private var active = false
    private var displayedCoverage = 0.0
    private var targetCoverage = 0.0
    private var transition = GlassTransition()
    private var displayTargets: [CGDirectDisplayID: Double]?
    private var displayTransitions: [CGDirectDisplayID: GlassTransition] = [:]
    private var displayValues: [CGDirectDisplayID: Double] = [:]
    private var lastFrameTime = 0.0
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
        if surfaces.values.contains(where: \.hasImage) { startAnimation() }
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
        guard animationTimer == nil else { return }
        let frameRate = NSScreen.screens.map(\.maximumFramesPerSecond).max() ?? 60
        let frameInterval = 1.0 / Double(max(60, frameRate))
        lastFrameTime = ProcessInfo.processInfo.systemUptime - frameInterval
        animationTimer = Timer(timeInterval: frameInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.animate() }
        }
        RunLoop.main.add(animationTimer!, forMode: .common)
        animate()
    }

    private func animate() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastFrameTime
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
            animationTimer?.invalidate()
            animationTimer = nil
            if targetCoverage == 0 { clear() }
        }
    }

    func clear() {
        let wasActive = active
        active = false
        pendingFade?.cancel(); pendingFade = nil
        generation += 1
        animationTimer?.invalidate(); animationTimer = nil
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
                            if self.displayedCoverage != self.targetCoverage || self.displayTargets != nil { self.startAnimation() }
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
