// Clinton Imaro was here 20/09/2026.

import AppKit
import Carbon
import Combine
import CoreMotion
import ShieldCore
import simd

@MainActor
final class AppModel: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    @Published private(set) var trackingSource: HeadTrackingSource
    let cameraTracking = CameraHeadTracking()
    private var cameraPauses: Set<NearbyPauseReason> = []
    private var protectCameraOnResume = false
    @Published private(set) var enabled = false
    @Published private(set) var connected = false
    @Published private(set) var calibrated = false
    @Published private(set) var coverage = 0.0
    @Published private(set) var offset = HeadOffset(yaw: 0, pitch: 0)
    @Published private(set) var status = "Ready when you are"
    @Published private(set) var detail = "Connect your AirPods to this Mac, then start head tracking."
    @Published private(set) var captureNotice: String?
    @Published private(set) var screenPermission = CGPreflightScreenCaptureAccess()
    @Published private(set) var restarting = false
    @Published private(set) var previewing = false
    @Published private(set) var shortcutError: String?
    @Published private(set) var areaShortcutError: String?
    let areaShortcutLabel = "⌃⌥⌘A"
    @Published var recordingShortcut = false
    @Published var demoMode: Bool {
        didSet {
            UserDefaults.standard.set(demoMode, forKey: "includeBlurInCaptures")
            overlay.includeInCaptures = demoMode
            privacy.includeInCaptures = demoMode
        }
    }
    @Published var comfort: Double { didSet { save("comfort", comfort); refreshResponse() } }
    @Published var transition: Double { didSet { save("transition", transition); refreshResponse() } }
    @Published var blur: Double { didSet { save("blur", blur); privacy.blurRadius = blur } }
    @Published private(set) var shortcutLabel: String
    @Published private(set) var privacyShortcutError: String?
    @Published private(set) var learning = false
    @Published private(set) var learningProgress = 0.0
    @Published private(set) var suggestedComfort: Double?
    @Published private(set) var learningNotice: String?
    @Published private(set) var headSetupActive = false

    @Published var perDisplayTracking = false {
        didSet { displayTracking.invalidate(); displayCalibrationIDs = []; clearOverlay(); updateShield() }
    }
    @Published private(set) var displayCalibrationIDs = Set<UInt32>()
    @Published private(set) var displayCalibrationNotice: String?
    private var displayTracking = DisplayHeadTracking()
    private var displayCalibrationTask: Task<Void, Never>?
    private var displayLayout: [UInt32: CGRect] = [:]

    let privacy = PrivacyController()
    let nearby = NearbyPeople()
    let protectionCheck = ProtectionCheck()
    let loginPreference = LoginPreference()
    let updates = AppUpdates()
    private var maintenanceObservations: [AnyCancellable] = []
    private var protectionCheckObservation: AnyCancellable?
    private var nearbyObservation: AnyCancellable?
    var onOpenPrivacySettings: (() -> Void)?
    var onOpenControls: (() -> Void)?
    var onOpenProfileSettings: (() -> Void)?
    var onOpenNearbySettings: (() -> Void)?
    var onShowProfiles: ((NSView, Bool) -> Void)?
    var onRequestHeadSetup: (() -> Void)?
    var onCancelHeadSetup: (() -> Void)?

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
    private var privacyObservation: AnyCancellable?
    private var calibration = AdaptiveCalibration()
    private var learningStarted: TimeInterval = 0
    private var setupSnapshot: HeadSetupSnapshot?
    private var motionReferenceGeneration = 0

    private struct HeadSetupSnapshot {
        let enabled: Bool
        let comfort: Double
        let center: simd_quatd?
        let source: CMDeviceMotion.SensorLocation?
        let generation: Int
        let calibrated: Bool
        let everCalibrated: Bool
        let dismissedForLoss: Bool
        let response: ShieldResponse
    }

    override init() {
        let prefs = UserDefaults.standard
        trackingSource = HeadTrackingSource(rawValue: prefs.string(forKey: "headTrackingSource") ?? "") ?? .airPods
        demoMode = prefs.bool(forKey: "includeBlurInCaptures")
        comfort = prefs.object(forKey: "comfort") == nil ? 15 : max(2, min(30, prefs.double(forKey: "comfort")))
        transition = prefs.object(forKey: "transition") == nil ? 18 : max(5, min(30, prefs.double(forKey: "transition")))
        blur = prefs.object(forKey: "blur") == nil ? 28 : max(10, min(70, prefs.double(forKey: "blur")))
        keyCode = prefs.object(forKey: "shortcutKey") == nil ? UInt32(kVK_ANSI_C) : UInt32(prefs.integer(forKey: "shortcutKey"))
        keyModifiers = prefs.object(forKey: "shortcutModifiers") == nil ? UInt32(controlKey | optionKey | cmdKey) : UInt32(prefs.integer(forKey: "shortcutModifiers"))
        shortcutLabel = prefs.string(forKey: "shortcutLabel") ?? "⌃⌥⌘C"
        super.init()
        cameraTracking.onChange = { [weak self] in self?.receiveCameraTracking() }
        nearby.onCoverage = { [weak self] value in self?.privacy.setNearbyCovered(value) }
        nearby.onMonitoring = { [weak self] value in self?.privacy.setNearbyMonitoring(value) }
        protectionCheck.onBegin = { [weak self] in self?.nearby.suspend(for: .protectionTest); self?.pauseCamera(for: .protectionTest) }
        protectionCheck.onEnd = { [weak self] in self?.nearby.resume(after: .protectionTest); self?.resumeCamera(after: .protectionTest) }
        protectionCheck.onDemoCoverage = { [weak self] in self?.privacy.setTestCovered($0) }
        protectionCheck.demoAvailable = { [weak self] in self?.privacy.captureUnavailable == false }
        protectionCheckObservation = protectionCheck.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in self?.objectWillChange.send() }
        maintenanceObservations = [
            loginPreference.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            updates.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        ]
        nearby.prepareMonitoring = { [weak self] in
            guard let self else { return .escapeUnavailable }
            if self.nearby.response == .blur, !self.screenPermission { return .screenPermission }
            guard self.shortcuts.armEscape(true) else {
                self.privacyShortcutError = "Escape is unavailable. Nearby people could not start."
                return .escapeUnavailable
            }
            return nil
        }
        nearbyObservation = nearby.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            self?.objectWillChange.send()
            self?.refreshEscape()
            self?.updateShield()
        }
        privacy.blurRadius = blur
        overlay.includeInCaptures = demoMode
        privacy.includeInCaptures = demoMode
        if screenPermission { UserDefaults.standard.set(true, forKey: "screenAccessPreviouslyGranted") }
        motion.delegate = self
        refreshResponse()
        shortcuts.onRecenter = { [weak self] in self?.recenter() }
        shortcuts.onEscape = { [weak self] in
            guard let self else { return }
            if self.headSetupActive { self.onCancelHeadSetup?() } else { self.dismissShield() }
        }
        shortcuts.onPrivacy = { [weak self] in self?.toggleInstantShield() }
        shortcuts.onArea = { [weak self] in self?.privacy.chooseArea() }
        shortcuts.onPeek = { [weak self] value in self?.privacy.setPeeking(value) }
        overlay.onClear = { [weak self] in self?.refreshEscape() }
        privacy.requestEscape = { [weak self] in self?.shortcuts.armEscape(true) ?? false }
        privacy.onRulesChanged = { [weak self] in
            self?.refreshResponse()
            self?.updateShield()
        }
        privacy.onActivityChanged = { [weak self] in
            guard let self else { return }
            self.refreshEscape()
            if !self.shortcuts.armPeek(self.privacy.instant) {
                self.privacyShortcutError = "Hold to peek is in use by another app. Escape still clears the shield."
            }
            self.updateShield()
        }
        privacyObservation = privacy.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        if !shortcuts.setPrivacyShortcut() {
            privacyShortcutError = "⌃⌥⌘P is in use by another app. Use Shield screen in the menu instead."
        }
        if !shortcuts.setAreaShortcut() {
            areaShortcutError = "⌃⌥⌘A is in use by another app. Use Choose area or the notch button."
        }
        overlay.onCaptureStatus = { [weak self] notice in
            if self?.captureNotice != notice { self?.captureNotice = notice }
        }
        overlay.onPermissionDenied = { [weak self] in
            guard let self else { return }
            self.screenPermission = false
            self.stopPreview()
            self.clearOverlay()
            self.status = "Screen access needed"
            self.captureNotice = "Screen access is unavailable. Open Screen Settings to restore it."
        }
        if !shortcuts.setRecenter(keyCode: keyCode, modifiers: keyModifiers) {
            shortcutError = "The recenter shortcut is in use. Record a different one."
        }
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshDisplays() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.overlay.activeSpaceChanged() }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshScreenPermission(); self?.loginPreference.refresh(); self?.updates.checkIfDue() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.prepareForSleep() }
        })
        let nearbyLifecycle: [(Notification.Name, Notification.Name, NearbyPauseReason)] = [
            (NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification, .displaySleep),
            (NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification, .inactiveSession)
        ]
        for (pause, resume, reason) in nearbyLifecycle {
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: pause, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.nearby.suspend(for: reason); self?.pauseCamera(for: reason) }
            })
            observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: resume, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.nearby.resume(after: reason); self?.resumeCamera(after: reason) }
            })
        }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.nearby.resume(after: .systemSleep)
                self.resumeCamera(after: .systemSleep)
                guard self.enabled else { return }
                self.detail = "Look at your screen and recenter after waking your Mac."
                self.beginMotionIfAvailable()
                self.updateShield()
            }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.heartbeat() }
        }
        refreshDisplays()
        privacy.start()
    }

    var fullCoverAngle: Int { Int(comfort + transition) }
    var canRecenter: Bool { trackingSource == .camera ? enabled && cameraTracking.failure == nil && cameraPauses.isEmpty : enabled && connected && latest != nil && ProcessInfo.processInfo.systemUptime - lastSample < 1.5 }
    var hasCompletedHeadSetup: Bool { UserDefaults.standard.bool(forKey: "headSetupCompleted.v1") }
    var screenAccessPreviouslyGranted: Bool { UserDefaults.standard.bool(forKey: "screenAccessPreviouslyGranted") }
    var screenAccessAction: String { screenAccessPreviouslyGranted ? "Restore screen access" : "Allow screen access" }

    var connectedDisplays: [(id: UInt32, name: String)] {
        NSScreen.screens.compactMap { screen in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return (id, screen.localizedName)
        }
    }

    func calibrateDisplay(_ id: UInt32) {
        displayCalibrationTask?.cancel()
        displayCalibrationTask = Task { [weak self] in
            for second in stride(from: 3, through: 1, by: -1) {
                guard let self else { return }
                self.displayCalibrationNotice = "Face the selected display · \(second)"
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
            guard let self, self.perDisplayTracking, self.canRecenter, let latest = self.latest,
                  self.connectedDisplays.contains(where: { $0.id == id }) else {
                self?.displayCalibrationNotice = "Motion unavailable. Connect your AirPods and try again."
                return
            }
            if !self.calibrated { self.recenter() }
            self.displayTracking.calibrate(id, at: latest)
            self.displayCalibrationIDs = Set(self.displayTracking.centers.keys)
            self.displayCalibrationNotice = "Display centered. Repeat for your other displays."
            self.updateShield()
        }
    }

    private func refreshDisplays() {
        let layout = Dictionary(uniqueKeysWithValues: NSScreen.screens.compactMap { screen -> (UInt32, CGRect)? in
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { return nil }
            return (id, screen.frame)
        })
        if !displayLayout.isEmpty, displayLayout != layout { invalidateDisplayCalibration() }
        displayLayout = layout
        overlay.reconcileScreens()
    }

    private func invalidateDisplayCalibration() {
        displayCalibrationTask?.cancel(); displayCalibrationTask = nil
        displayTracking.invalidate()
        displayCalibrationIDs = []
        if perDisplayTracking { displayCalibrationNotice = "Head motion changed. Center each display again." }
    }

    var currentProfile: PrivacyProfile? {
        if privacy.focusEnabled { return .focus }
        return PrivacyProfile.allCases.first { $0 != .focus && $0.settings.comfort == comfort && $0.settings.transition == transition && $0.settings.blur == blur }
    }

    var notchClearsProtection: Bool {
        previewing || privacy.fullScreen || privacy.focusEnabled || nearby.wantsMonitoring
    }

    var nearbyBlurUnavailable: Bool { (nearby.enabled || nearby.requesting || nearby.covered) && nearby.requiresBlur && privacy.captureUnavailable }
    var nearbyNeedsAttention: Bool { nearby.needsAttention || nearbyBlurUnavailable || nearby.temporarilyPaused || protectionCheck.demoSeconds != nil || protectionCheck.demoBlurred }
    var nearbyNoticeTitle: String {
        if protectionCheck.demoSeconds != nil || protectionCheck.demoBlurred { return "Protection test" }
        if nearby.temporarilyPaused { return "Nearby people paused" }
        return nearbyBlurUnavailable ? "Privacy blur unavailable" : nearby.noticeTitle
    }
    var nearbyNoticeDetail: String {
        if let seconds = protectionCheck.demoSeconds { return "Test blur starts in \(seconds) seconds" }
        if protectionCheck.demoBlurred {
            return privacy.captureUnavailable ? "Test blur unavailable · Check Screen Recording" : "Test blur clears automatically · Esc to stop"
        }
        if let seconds = nearby.pauseSecondsRemaining {
            return String(format: "Resumes in %d:%02d", seconds / 60, seconds % 60)
        }
        if nearbyBlurUnavailable { return "Open Settings to restore it" }
        if nearby.covered && !privacy.ready { return "Preparing blur · Esc to clear" }
        return nearby.noticeDetail
    }

    func blurNearbyNow() {
        guard screenPermission else { requestScreenPermission(); return }
        nearby.blurNow()
    }

    func applyProfile(_ profile: PrivacyProfile) {
        comfort = profile.settings.comfort
        transition = profile.settings.transition
        blur = profile.settings.blur
        setFocus(profile == .focus)
        updateShield()
    }

    func setFocus(_ value: Bool) {
        if value { stop() }
        privacy.setFocus(value)
    }

    func setNearbyPeople(_ value: Bool) {
        if value, nearby.owner.busy || nearby.owner.enrolling { return }
        nearby.setEnabled(value)
        if value, nearby.status == .unavailable(.screenPermission) { requestScreenPermission() }
    }

    func setNearbyResponse(_ value: NearbyResponse) {
        if value == .blur, nearby.enabled || nearby.requesting, !screenPermission { requestScreenPermission(); return }
        nearby.setResponse(value)
    }

    func retryNearbyPeople() {
        if nearby.response == .blur, !screenPermission { requestScreenPermission(); return }
        guard shortcuts.armEscape(true) else { privacyShortcutError = "Escape is unavailable. Nearby people could not start."; return }
        nearby.retry()
    }

    func retryNearbyBlur() {
        guard screenPermission else { requestScreenPermission(); return }
        privacy.start()
        if !privacy.captureUnavailable { privacy.setNearbyCovered(nearby.covered) }
    }

    func setTrackingSource(_ source: HeadTrackingSource) {
        guard source != trackingSource else { return }
        stop()
        trackingSource = source
        UserDefaults.standard.set(source.rawValue, forKey: "headTrackingSource")
        detail = source == .camera ? "Use your camera to blur when you turn away. Start tracking to calibrate." : "Connect your AirPods to this Mac, then start head tracking."
    }

    func selectTrackingCamera(_ id: String) {
        let resume = enabled && trackingSource == .camera
        if resume { protectCameraOnResume = cameraTracking.policy.calibrated || cameraTracking.policy.coverage > 0; cameraTracking.stop() }
        nearby.selectCamera(id)
        if resume { startCameraTracking() }
    }

    func retryCameraTracking() { startCameraTracking() }

    private func startCameraTracking() {
        guard enabled, trackingSource == .camera, cameraPauses.isEmpty else { return }
        refreshResponse()
        cameraTracking.start(deviceID: nearby.selectedCameraID, keepCovered: protectCameraOnResume)
        protectCameraOnResume = false
        receiveCameraTracking()
    }

    private func receiveCameraTracking() {
        guard enabled, trackingSource == .camera else { return }
        connected = cameraTracking.policy.hasFace
        calibrated = cameraTracking.policy.calibrated
        offset = cameraTracking.policy.offset
        detail = cameraTracking.message
        objectWillChange.send()
        updateShield()
    }

    func pauseCamera(for reason: NearbyPauseReason) {
        guard cameraPauses.insert(reason).inserted, enabled, trackingSource == .camera else { return }
        protectCameraOnResume = protectCameraOnResume || cameraTracking.policy.calibrated || cameraTracking.policy.coverage > 0
        cameraTracking.stop(); clearOverlay()
        status = "Camera head tracking paused"
    }

    func resumeCamera(after reason: NearbyPauseReason) {
        guard cameraPauses.remove(reason) != nil else { return }
        startCameraTracking()
    }

    func setEnabled(_ value: Bool) {
        if value { start() } else { stop() }
    }

    func start() {
        guard !enabled else { return }
        if trackingSource == .camera {
            guard screenPermission else { requestScreenPermission(); return }
            guard shortcuts.armEscape(true) else { privacyShortcutError = "Escape is unavailable. Camera tracking could not start."; return }
            enabled = true; dismissedForLoss = false
            startCameraTracking(); return
        }
        if !headSetupActive, !hasCompletedHeadSetup, let onRequestHeadSetup {
            onRequestHeadSetup()
            return
        }
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
        cancelLearning()
        invalidateDisplayCalibration()
        enabled = false
        protectCameraOnResume = false
        cameraTracking.stop()
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
        guard trackingSource == .airPods, enabled, !motion.isDeviceMotionActive, motion.isDeviceMotionAvailable else { return }
        motionReferenceGeneration += 1
        invalidateDisplayCalibration()
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
        guard enabled, trackingSource == .airPods else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let q = sample.attitude.quaternion
        guard q.x.isFinite, q.y.isFinite, q.z.isFinite, q.w.isFinite else { return }
        if let previous = sourceLocation, previous != sample.sensorLocation {
            motionReferenceGeneration += 1
            invalidateDisplayCalibration()
            cancelLearning(message: "The active AirPod changed. Recenter and try again.")
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
            if learning { calibration.record(angle: offset.angle) }
            updateShield()
        } else if center == nil {
            updateShield()
            if !everCalibrated { status = "Center your gaze" }
        }
    }

    func recenter() {
        cancelLearning()
        if !enabled { start() }
        guard enabled else { return }
        if trackingSource == .camera {
            if cameraTracking.failure != nil { startCameraTracking() } else { cameraTracking.recenter() }
            return
        }
        guard connected, ProcessInfo.processInfo.systemUptime - lastSample < 1.5, let latest else {
            pendingCalibration = true
            detail = "Waiting for motion. Keep your AirPods connected and face the screen."
            return
        }
        center = latest
        if perDisplayTracking, let facing = displayTracking.facing { displayTracking.calibrate(facing, at: latest) }
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

    func dismissShield(file: StaticString = #fileID, line: UInt = #line) {
        protectionCheck.stopDemonstration()
        nearby.stop(file: file, line: line)
        if trackingSource == .camera { stop() }
        cancelLearning()
        stopPreview()
        response.dismiss()
        displayTracking.dismiss()
        dismissedForLoss = true
        privacy.dismissAll()
        clearOverlay()
        status = enabled ? "Shield dismissed" : "Paused"
        detail = "Face your screen to rearm, or use Center my gaze."
    }

    private func updateShield() {
        if privacy.fullScreen {
            stopPreview()
            if privacy.captureUnavailable { status = "Privacy capture needs attention" }
            else if !privacy.ready { status = "Preparing privacy blur" }
            else { status = privacy.nearbyCovered ? "Covered · \(nearby.noticeTitle)" : privacy.peeking ? "Peeking at your screen" : "Privacy blur is on" }
            return
        }
        guard !previewing else { return }
        if learning { clearOverlay(); status = "Learning your normal movement"; return }
        if headSetupActive { clearOverlay(); status = "Setting up head tracking"; return }
        guard enabled else {
            clearOverlay()
            if privacy.focusEnabled { status = "Focus mode is on" }
            else if nearby.wantsMonitoring { status = nearby.message }
            else { status = "Ready when you are" }
            return
        }
        if privacy.ruleMode == .pause {
            clearOverlay()
            status = "Head blur paused for \(privacy.frontAppName)"
            return
        }
        if trackingSource == .camera {
            guard cameraPauses.isEmpty else { clearOverlay(); return }
            let value = cameraTracking.policy.coverage
            guard applyCoverage(value, direction: .from(cameraTracking.policy.offset)) else { return }
            status = cameraTracking.message
            return
        }
        if !connected || !calibrated {
            if everCalibrated && !dismissedForLoss {
                guard applyCoverage(1, direction: .left) else { return }
                status = "Covered while motion is unavailable"
            } else { clearOverlay() }
            return
        }
        if perDisplayTracking, !connectedDisplays.isEmpty, connectedDisplays.allSatisfy({ displayCalibrationIDs.contains($0.id) }), let latest {
            let settings = privacy.ruleMode.settings(comfort: comfort, transition: transition, blur: blur)
            let values = displayTracking.coverage(current: latest, displays: connectedDisplays.map(\.id),
                                                  comfort: settings.comfort, transition: settings.transition)
            let maximum = values.values.max() ?? 0
            guard applyCoverage(maximum, direction: .from(offset), displays: values) else { return }
            status = displayCalibrationIDs.isEmpty ? "Center each display to use display tracking" : "Protecting displays you turn away from"
            return
        }
        let value = response.coverage(angle: offset.angle)
        if !response.dismissedUntilCentered { dismissedForLoss = false }
        guard applyCoverage(value, direction: .from(offset)) else { return }
        if response.dismissedUntilCentered { status = "Shield dismissed until you face center" }
        else if value > 0.001 { status = "Screen covered \(Int(value * 100))%" }
        else { status = "Watching your head motion" }
    }

    @discardableResult private func applyCoverage(_ value: Double, direction: ShieldDirection, displays: [UInt32: Double]? = nil) -> Bool {
        if value > 0.001 {
            guard screenPermission else {
                clearOverlay()
                status = "Screen access needed"
                return false
            }
            guard shortcuts.armEscape(true) else {
                clearOverlay()
                status = "Escape is unavailable"
                detail = "Another app reserved Escape. Pause that shortcut and try again."
                return false
            }
            let radius = previewing ? blur : privacy.ruleMode.settings(comfort: comfort, transition: transition, blur: blur).blur
            overlay.show(coverage: value, direction: direction, blurRadius: radius, displays: displays)
        } else {
            overlay.fadeOut()
        }
        if coverage != value { coverage = value }
        return true
    }

    private func clearOverlay() {
        overlay.clear()
        if coverage != 0 { coverage = 0 }
        refreshEscape()
    }

    private func refreshEscape() {
        shortcuts.armEscape((enabled && trackingSource == .camera) || nearby.wantsMonitoring || privacy.wantsProtection || overlay.isCapturing || coverage > 0)
    }

    func toggleInstantShield() {
        cancelLearning()
        stopPreview()
        privacy.toggleInstant()
        if !privacy.instant {
            if enabled { updateShield() } else { status = "Ready when you are" }
        }
    }

    func learnMovement() {
        guard canRecenter, !privacy.instant else {
            learningNotice = "Start head tracking and connect your AirPods first."
            return
        }
        recenter()
        guard calibrated else { return }
        calibration = AdaptiveCalibration()
        suggestedComfort = nil
        learningNotice = nil
        learningProgress = 0
        learningStarted = ProcessInfo.processInfo.systemUptime
        learning = true
        clearOverlay()
    }

    func cancelLearning(message: String? = nil) {
        guard learning else { return }
        learning = false
        learningProgress = 0
        learningNotice = message
    }

    func applyCalibration() {
        guard let suggestedComfort else { return }
        comfort = suggestedComfort
        self.suggestedComfort = nil
        learningNotice = "Sensitivity updated. Recenter whenever your sitting position changes."
        updateShield()
    }

    @discardableResult func beginHeadSetup() -> Bool {
        guard !headSetupActive, !privacy.instant else { return false }
        setupSnapshot = HeadSetupSnapshot(enabled: enabled, comfort: comfort, center: center,
                                          source: sourceLocation, generation: motionReferenceGeneration, calibrated: calibrated,
                                          everCalibrated: everCalibrated, dismissedForLoss: dismissedForLoss,
                                          response: response)
        cancelLearning()
        suggestedComfort = nil
        learningNotice = nil
        headSetupActive = true
        stopPreview()
        clearOverlay()
        return true
    }

    func finishHeadSetup(completed: Bool) {
        guard let snapshot = setupSnapshot else { return }
        setupSnapshot = nil
        cancelLearning()
        suggestedComfort = nil
        learningNotice = nil
        headSetupActive = false
        if completed, canRecenter {
            recenter()
            UserDefaults.standard.set(true, forKey: "headSetupCompleted.v1")
        } else if snapshot.enabled && enabled {
            comfort = snapshot.comfort
            center = snapshot.source == sourceLocation && snapshot.generation == motionReferenceGeneration ? snapshot.center : nil
            calibrated = snapshot.calibrated && center != nil && connected
            everCalibrated = snapshot.everCalibrated
            dismissedForLoss = snapshot.dismissedForLoss
            response = snapshot.response
            refreshResponse()
            if let center, let latest { offset = HeadOffset.between(center: center, current: latest) }
        } else {
            comfort = snapshot.comfort
            stop()
        }
        updateShield()
    }

    func previewShield() {
        guard !privacy.instant else { return }
        cancelLearning()
        stopPreview()
        guard applyCoverage(1, direction: .right) else { return }
        previewing = true
        status = "Preview ends in 5 seconds"
        previewEnd = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 5_000_000_000) } catch { return }
            guard !Task.isCancelled, let self, self.previewing else { return }
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
        refreshScreenPermission()
        if !screenPermission {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
        }
    }

    func restartForScreenPermission() {
        guard !restarting else { return }
        restarting = true
        stop()
        UserDefaults.standard.set(true, forKey: "showControlsAfterRelaunch")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { [weak self] application, error in
            Task { @MainActor in
                guard application != nil, error == nil else {
                    UserDefaults.standard.removeObject(forKey: "showControlsAfterRelaunch")
                    self?.restarting = false
                    self?.captureNotice = "Could not restart QuietGlass. Quit and reopen the app."
                    return
                }
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private func refreshScreenPermission() {
        guard !overlay.isCapturing else { return }
        let permission = CGPreflightScreenCaptureAccess()
        guard permission != screenPermission else { return }
        screenPermission = permission
        captureNotice = nil
        if permission {
            UserDefaults.standard.set(true, forKey: "screenAccessPreviouslyGranted")
            if enabled { updateShield() }
            else { status = "Ready when you are" }
        } else {
            stopPreview()
            clearOverlay()
            status = "Screen access needed"
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
        refreshScreenPermission()
        guard enabled else { return }
        if trackingSource == .camera { return }
        let auth = CMHeadphoneMotionManager.authorizationStatus()
        if auth == .denied || auth == .restricted {
            stop()
            status = "Motion permission needed"
            detail = "Allow QuietGlass in Privacy & Security → Motion & Fitness, then start again."
            return
        }
        if ProcessInfo.processInfo.systemUptime - lastSample > 1.5 {
            cancelLearning(message: "Motion was interrupted. Reconnect your AirPods and try again.")
            if connected {
                motionReferenceGeneration += 1
                invalidateDisplayCalibration()
                connected = false
                center = nil
                calibrated = false
                detail = "Motion stopped. Wear your AirPods and recenter when they reconnect."
            }
            if !everCalibrated { status = "Waiting for AirPods motion" }
            beginMotionIfAvailable()
            updateShield()
        }
        if learning {
            learningProgress = min(1, (ProcessInfo.processInfo.systemUptime - learningStarted) / 8)
            if learningProgress >= 1 {
                learning = false
                suggestedComfort = calibration.recommendation
                learningNotice = suggestedComfort == nil ? "Too much motion or too few samples. Face your screen and try again." : "Review the suggested angle before applying it."
                updateShield()
            }
        }
    }

    private func prepareForSleep() {
        motionReferenceGeneration += 1
        invalidateDisplayCalibration()
        cancelLearning(message: "Calibration stopped while your Mac slept.")
        nearby.suspend(for: .systemSleep)
        pauseCamera(for: .systemSleep)
        privacy.dismissAll()
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
            guard let self, self.enabled, self.trackingSource == .airPods else { return }
            self.motionReferenceGeneration += 1
            self.invalidateDisplayCalibration()
            self.cancelLearning(message: "AirPods disconnected. Reconnect and try again.")
            self.connected = false
            self.calibrated = false
            self.center = nil
            self.latest = nil
            self.detail = "AirPods disconnected. Face the screen and recenter after reconnecting."
            self.updateShield()
        }
    }

    private func refreshResponse() {
        let settings = privacy.ruleMode.settings(comfort: comfort, transition: transition, blur: blur)
        cameraTracking.comfort = settings.comfort
        cameraTracking.transition = settings.transition
        response.comfort = settings.comfort
        response.transition = settings.transition
    }

    private func save(_ key: String, _ value: Double) { UserDefaults.standard.set(value, forKey: key) }

    func shutdown() {
        updates.shutdown()
        protectionCheck.close()
        nearby.shutdown()
        stop()
        privacy.shutdown()
        timer?.invalidate()
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
    }
}
