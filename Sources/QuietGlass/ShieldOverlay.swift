import AppKit
import CoreImage
import ScreenCaptureKit
import ShieldCore

private final class ShieldPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class ShieldSurface {
    let panel: ShieldPanel
    private let imageLayer = CALayer()
    private let gradient = CAGradientLayer()
    var hasImage: Bool { imageLayer.contents != nil }

    init(screen: NSScreen) {
        panel = ShieldPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "QuietGlass Blur"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 1)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = .none
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = imageLayer
        imageLayer.backgroundColor = NSColor.clear.cgColor
        imageLayer.contentsGravity = .resize
        panel.contentView = view
    }

    func update(coverage: Double, direction: ShieldDirection) {
        // Never present a colored backing while waiting for a usable blurred image.
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

private actor BlurRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    func render(_ image: CGImage, radius: Double) -> CGImage? {
        autoreleasepool {
            let input = CIImage(cgImage: image)
            let output = input.clampedToExtent()
                .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                .cropped(to: input.extent)
            // Preserve the original image colors: no white veil, tint, or saturation shift.
            return context.createCGImage(output, from: input.extent)
        }
    }
}

@MainActor
final class ShieldOverlay {
    var onClear: (() -> Void)?
    var onCaptureStatus: ((String?) -> Void)?
    private var surfaces: [CGDirectDisplayID: ShieldSurface] = [:]
    private let renderer = BlurRenderer()
    private var captureTask: Task<Void, Never>?
    private var pendingFade: Task<Void, Never>?
    private var refreshTimer: Timer?
    private var animationTimer: Timer?
    private var generation = 0
    private var active = false
    private var displayedCoverage = 0.0
    private var targetCoverage = 0.0
    private var transition = GlassTransition()
    private var lastFrameTime = 0.0
    private var direction: ShieldDirection = .left
    private var blurRadius = 28.0

    func show(coverage: Double, direction: ShieldDirection, blurRadius: Double) {
        guard coverage > 0.001 else { fadeOut(); return }
        pendingFade?.cancel(); pendingFade = nil
        if surfaces.isEmpty { rebuild() }
        targetCoverage = max(0, min(1, coverage))
        self.blurRadius = blurRadius
        if !active {
            // Keep the same sweep edge until the screen is fully clear. A small
            // change in the dominant head axis must not move the mask instantly.
            self.direction = direction
            active = true
            capture()
            refreshTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.capture() }
            }
            RunLoop.main.add(refreshTimer!, forMode: .common)
        }
        if surfaces.values.contains(where: \.hasImage) { startAnimation() }
    }

    func fadeOut() {
        guard active, targetCoverage > 0, pendingFade == nil else { return }
        // Ignore a brief clear sample while the user is still looking away.
        // Repeated clear samples share this deadline instead of postponing it.
        pendingFade = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard let self else { return }
            self.pendingFade = nil
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
        displayedCoverage = transition.advance(to: targetCoverage, elapsed: now - lastFrameTime)
        lastFrameTime = now
        for surface in surfaces.values { surface.update(coverage: displayedCoverage, direction: direction) }
        if displayedCoverage == targetCoverage {
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
        displayedCoverage = 0
        targetCoverage = 0
        transition.reset()
        for surface in surfaces.values { surface.clear() }
        if wasActive { onClear?() }
    }

    func rebuild() {
        clear()
        for surface in surfaces.values { surface.panel.close() }
        surfaces.removeAll()
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { continue }
            surfaces[number.uint32Value] = ShieldSurface(screen: screen)
        }
    }

    private func capture() {
        guard active, targetCoverage > 0, captureTask == nil else { return }
        guard CGPreflightScreenCaptureAccess() else {
            onCaptureStatus?("Allow Screen Recording to enable blur.")
            clear()
            return
        }
        let token = generation
        let radius = blurRadius
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.captureTask = nil } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
                guard !Task.isCancelled, self.active, self.generation == token else { return }
                let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !ownApps.isEmpty else {
                    self.onCaptureStatus?("Blur is waiting for the display. Try the preview again.")
                    return
                }
                for display in content.displays {
                    guard self.surfaces[display.displayID] != nil else { continue }
                    guard !Task.isCancelled, self.active, self.generation == token else { return }
                    let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
                    if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                    let config = SCStreamConfiguration()
                    config.width = max(1, display.width)
                    config.height = max(1, display.height)
                    config.showsCursor = false
                    config.scalesToFit = true
                    config.preservesAspectRatio = true
                    let source = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
                    guard !Task.isCancelled, self.active, self.generation == token else { return }
                    let blurred = await self.renderer.render(source, radius: radius)
                    guard !Task.isCancelled, self.active, self.generation == token else { return }
                    if let blurred {
                        self.surfaces[display.displayID]?.setImage(blurred)
                        self.startAnimation()
                    }
                }
                self.onCaptureStatus?(nil)
            } catch {
                guard !Task.isCancelled, self.generation == token else { return }
                self.onCaptureStatus?("Blur unavailable: \(error.localizedDescription)")
                // A previously blurred image stays in place while capture retries.
                // Before the first good frame the display stays clear, never gray or white.
            }
        }
    }
}
