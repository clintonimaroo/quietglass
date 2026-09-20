import AppKit
import Carbon
import Combine
import CoreMotion
import ShieldCore
import simd

@MainActor
final class AppModel: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published private(set) var enabled = false
    @Published private(set) var connected = false
    @Published private(set) var calibrated = false
    @Published private(set) var coverage = 0.0
    @Published private(set) var offset = HeadOffset(yaw: 0, pitch: 0)
    @Published private(set) var status = "Ready when you are"
    @Published private(set) var detail = "Connect your AirPods to this Mac, then start head tracking."
    @Published private(set) var captureNotice: String?
    @Published private(set) var screenPermission = CGPreflightScreenCaptureAccess()
    @Published private(set) var previewing = false
    @Published private(set) var shortcutError: String?
    @Published var recordingShortcut = false
    @Published var comfort: Double { didSet { save("comfort", comfort); refreshResponse() } }
    @Published var transition: Double { didSet { save("transition", transition); refreshResponse() } }
    @Published var blur: Double { didSet { save("blur", blur) } }
    @Published private(set) var shortcutLabel: String

    private let motion = CMHeadphoneMotionManager()
    private let overlay = ShieldOverlay()
    private let shortcuts = GlobalShortcuts()
    private var response = ShieldResponse()
    private var center: simd_quatd?
    private var latest: simd_quatd?
    private var sourceLocation: CMDeviceMotion.SensorLocation?
    private var lastSample: TimeInterval = 0
    private var lastPublished: TimeInterval = 0
    private var everCalibrated = false
    private var dismissedForLoss = false
    private var pendingCalibration = false
    private var timer: Timer?
    private var previewEnd: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var keyCode: UInt32
    private var keyModifiers: UInt32

    override init() {
        let prefs = UserDefaults.standard
        comfort = prefs.object(forKey: "comfort") == nil ? 15 : max(2, min(30, prefs.double(forKey: "comfort")))
        transition = prefs.object(forKey: "transition") == nil ? 18 : max(5, min(30, prefs.double(forKey: "transition")))
        blur = prefs.object(forKey: "blur") == nil ? 28 : max(10, min(70, prefs.double(forKey: "blur")))
        keyCode = prefs.object(forKey: "shortcutKey") == nil ? UInt32(kVK_ANSI_C) : UInt32(prefs.integer(forKey: "shortcutKey"))
        keyModifiers = prefs.object(forKey: "shortcutModifiers") == nil ? UInt32(controlKey | optionKey | cmdKey) : UInt32(prefs.integer(forKey: "shortcutModifiers"))
        shortcutLabel = prefs.string(forKey: "shortcutLabel") ?? "⌃⌥⌘C"
        super.init()
        motion.delegate = self
        refreshResponse()
        shortcuts.onRecenter = { [weak self] in self?.recenter() }
        shortcuts.onEscape = { [weak self] in self?.dismissShield() }
        overlay.onClear = { [weak self] in self?.shortcuts.armEscape(false) }
        overlay.onCaptureStatus = { [weak self] notice in
            if self?.captureNotice != notice { self?.captureNotice = notice }
        }
        if !shortcuts.setRecenter(keyCode: keyCode, modifiers: keyModifiers) {
            shortcutError = "The recenter shortcut is in use. Record a different one."
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.overlay.rebuild(); self?.updateShield() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForSleep() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.enabled else { return }
                self.detail = "Look at your screen and recenter after waking your Mac."
                self.beginMotionIfAvailable()
                self.updateShield()
            }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
    }

    var fullCoverAngle: Int { Int(comfort + transition) }
    var canRecenter: Bool { enabled && connected && latest != nil }

    func setEnabled(_ value: Bool) {
        if value { start() } else { stop() }
    }

    func start() {
        guard !enabled else { return }
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        guard auth != .denied && auth != .restricted else {
            status = "Motion permission needed"
            detail = "Allow QuietGlass in System Settings → Privacy & Security → Motion & Fitness."
            return
        }
        enabled = true
        status = "Connecting to AirPods"
        detail = "Wear at least one AirPod, look at the screen, then click Center my gaze."
        motion.startConnectionStatusUpdates()
        beginMotionIfAvailable()
    }

    func stop() {
        enabled = false
        motion.stopDeviceMotionUpdates()
        motion.stopConnectionStatusUpdates()
        center = nil
        latest = nil
        sourceLocation = nil
        calibrated = false
        connected = false
        everCalibrated = false
        dismissedForLoss = false
        pendingCalibration = false
        response.recenter()
        stopPreview()
        clearOverlay()
        status = "Paused"
        detail = "Your screen stays clear while head tracking is paused."
    }

    private func beginMotionIfAvailable() {
        guard enabled, !motion.isDeviceMotionActive, motion.isDeviceMotionAvailable else { return }
        motion.startDeviceMotionUpdates(to: .main) { [weak self] sample, error in
            guard let self, self.enabled else { return }
            if let error {
                self.detail = error.localizedDescription
                return
            }
            if let sample { self.receive(sample) }
        }
    }

    private func receive(_ sample: CMDeviceMotion) {
        let now = ProcessInfo.processInfo.systemUptime
        let q = sample.attitude.quaternion
        guard q.x.isFinite, q.y.isFinite, q.z.isFinite, q.w.isFinite else { return }
        if let previous = sourceLocation, previous != sample.sensorLocation {
            // The newly active earbud may have a different inertial reference frame.
            center = nil
            calibrated = false
            detail = "The active AirPod changed. Face your screen and recenter."
        }
        sourceLocation = sample.sensorLocation
        latest = simd_normalize(simd_quatd(ix: q.x, iy: q.y, iz: q.z, r: q.w))
        lastSample = now
        if !connected { connected = true }
        if pendingCalibration { recenter() }
        if let center, let latest, now - lastPublished > 1.0 / 30 {
            lastPublished = now
            offset = HeadOffset.between(center: center, current: latest)
            updateShield()
        } else if center == nil {
            updateShield()
            if !everCalibrated { status = "Center your gaze" }
        }
    }

    func recenter() {
        if !enabled { start() }
        guard enabled else { return }
        guard connected, ProcessInfo.processInfo.systemUptime - lastSample < 1.5, let latest else {
            pendingCalibration = true
            detail = "Waiting for motion. Keep your AirPods connected and face the screen."
            return
        }
        center = latest
        calibrated = true
        everCalibrated = true
        pendingCalibration = false
        dismissedForLoss = false
        offset = HeadOffset(yaw: 0, pitch: 0)
        response.recenter()
        stopPreview()
        clearOverlay()
        status = "Watching your head motion"
        detail = "Small movements stay clear. Turn past \(Int(comfort))° to cover the screen."
    }

    func dismissShield() {
        stopPreview()
        response.dismiss()
        dismissedForLoss = true
        clearOverlay()
        status = enabled ? "Shield dismissed" : "Paused"
        detail = "Face your screen to rearm, or use Center my gaze."
    }

    private func updateShield() {
        guard !previewing else { return }
        guard enabled else { clearOverlay(); return }
        if !connected || !calibrated {
            if everCalibrated && !dismissedForLoss {
                guard applyCoverage(1, direction: .left) else { return }
                status = "Covered while motion is unavailable"
            } else { clearOverlay() }
            return
        }
        let value = response.coverage(angle: offset.angle)
        if !response.dismissedUntilCentered { dismissedForLoss = false }
        guard applyCoverage(value, direction: .from(offset)) else { return }
        if response.dismissedUntilCentered { status = "Shield dismissed until you face center" }
        else if value > 0.001 { status = "Screen covered \(Int(value * 100))%" }
        else { status = "Watching your head motion" }
    }

    @discardableResult private func applyCoverage(_ value: Double, direction: ShieldDirection) -> Bool {
        if value > 0.001 {
            guard screenPermission else {
                clearOverlay()
                status = "Enable screen blur"
                captureNotice = "Allow Screen Recording to enable blur."
                return false
            }
            // Do not cover the desktop unless the emergency shortcut can be registered.
            guard shortcuts.armEscape(true) else {
                clearOverlay()
                status = "Escape is unavailable"
                detail = "Another app reserved Escape. Pause that shortcut and try again."
                return false
            }
            overlay.show(coverage: value, direction: direction, blurRadius: blur)
        } else {
            overlay.fadeOut()
        }
        if coverage != value { coverage = value }
        return true
    }

    private func clearOverlay() {
        overlay.clear()
        shortcuts.armEscape(false)
        if coverage != 0 { coverage = 0 }
    }

    func previewShield() {
        stopPreview()
        guard applyCoverage(1, direction: .right) else { return }
        previewing = true
        status = "Preview ends in 5 seconds"
        previewEnd = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard let self else { return }
            self.stopPreview(immediate: false)
            if self.enabled { self.updateShield() }
            else { self.status = "Ready when you are" }
        }
    }

    private func stopPreview(immediate: Bool = true) {
        previewEnd?.cancel()
        previewEnd = nil
        previewing = false
        if immediate { clearOverlay() }
        else { overlay.fadeOut(); coverage = 0 }
    }

    func openMotionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Motion")!)
    }

    func requestScreenPermission() {
        if !CGPreflightScreenCaptureAccess() { _ = CGRequestScreenCaptureAccess() }
        screenPermission = CGPreflightScreenCaptureAccess()
        if !screenPermission {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func recordShortcut(_ event: NSEvent) {
        if event.keyCode == UInt16(kVK_Escape) { recordingShortcut = false; return }
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard !flags.intersection([.command, .control, .option]).isEmpty else {
            shortcutError = "Include Command, Control, or Option in your shortcut."
            return
        }
        var modifiers: UInt32 = 0
        var label = ""
        if flags.contains(.control) { modifiers |= UInt32(controlKey); label += "⌃" }
        if flags.contains(.option) { modifiers |= UInt32(optionKey); label += "⌥" }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey); label += "⇧" }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey); label += "⌘" }
        let names: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
        label += names[event.keyCode] ?? event.charactersIgnoringModifiers?.uppercased() ?? "Key \(event.keyCode)"
        if keyCode == UInt32(event.keyCode), keyModifiers == modifiers {
            recordingShortcut = false
            shortcutError = nil
            return
        }
        guard shortcuts.setRecenter(keyCode: UInt32(event.keyCode), modifiers: modifiers) else {
            shortcutError = "That shortcut is already in use. Try another combination."
            return
        }
        keyCode = UInt32(event.keyCode)
        keyModifiers = modifiers
        shortcutLabel = label
        let prefs = UserDefaults.standard
        prefs.set(Int(keyCode), forKey: "shortcutKey")
        prefs.set(Int(modifiers), forKey: "shortcutModifiers")
        prefs.set(label, forKey: "shortcutLabel")
        shortcutError = nil
        recordingShortcut = false
    }

    private func heartbeat() {
        let permission = CGPreflightScreenCaptureAccess()
        if permission != screenPermission { screenPermission = permission }
        guard enabled else { return }
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        if auth == .denied || auth == .restricted {
            stop()
            status = "Motion permission needed"
            detail = "Allow QuietGlass in Privacy & Security → Motion & Fitness, then start again."
            return
        }
        if ProcessInfo.processInfo.systemUptime - lastSample > 1.5 {
            if connected {
                connected = false
                center = nil
                calibrated = false
                detail = "Motion stopped. Wear your AirPods and recenter when they reconnect."
            }
            if !everCalibrated { status = "Waiting for AirPods motion" }
            beginMotionIfAvailable()
            updateShield()
        }
    }

    private func prepareForSleep() {
        motion.stopDeviceMotionUpdates()
        center = nil
        latest = nil
        connected = false
        calibrated = false
        stopPreview()
        clearOverlay()
    }

    nonisolated func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in self?.beginMotionIfAvailable() }
    }

    nonisolated func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        Task { @MainActor [weak self] in
            guard let self, self.enabled else { return }
            self.connected = false
            self.calibrated = false
            self.center = nil
            self.latest = nil
            self.detail = "AirPods disconnected. Face the screen and recenter after reconnecting."
            self.updateShield()
        }
    }

    private func refreshResponse() {
        response.comfort = comfort
        response.transition = transition
    }

    private func save(_ key: String, _ value: Double) { UserDefaults.standard.set(value, forKey: key) }

    func shutdown() {
        stop()
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
