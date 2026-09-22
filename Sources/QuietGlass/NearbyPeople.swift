//  Created by Clinton Imaro on 20/09/2026.

import AVFoundation
import Vision
import Combine
import ShieldCore
import OSLog

enum NearbyResponse: String, CaseIterable, Identifiable {
    case warning, blur
    var id: String { rawValue }
    var title: String { self == .warning ? "Warn me" : "Blur automatically" }
}

enum NearbyCameraFailure: Error, Equatable {
    case permission, noCamera, configuration, interrupted, disconnected, stalled, analysis, recognition, ownerAccess
    case screenPermission, escapeUnavailable

    var title: String {
        switch self {
        case .permission: return "Camera access is off"
        case .noCamera: return "No camera available"
        case .interrupted: return "Camera interrupted"
        case .disconnected: return "Camera disconnected"
        case .stalled: return "Camera stopped responding"
        case .analysis: return "Face detection unavailable"
        case .configuration: return "Camera unavailable"
        case .recognition: return "Owner recognition unavailable"
        case .ownerAccess: return "Unlock your saved face to continue"
        case .screenPermission: return "Screen Recording access is off"
        case .escapeUnavailable: return "Escape shortcut is unavailable"
        }
    }
}

enum NearbyCameraStatus: Equatable {
    case off, paused, requesting, starting, watching(Int), unavailable(NearbyCameraFailure)
}

enum NearbyPauseReason: Hashable {
    case systemSleep, displaySleep, inactiveSession, protectionTest, ownerEnrollment
}

struct NearbyFaceSample {
    let count: Int
    let capturedAt: TimeInterval
    var vector: [Float]? = nil
    var pose: OwnerPose? = nil
    var bounds: [CGRect] = []
    var faces: [CameraFace]? = nil
    var identities: [CameraIdentity?] = []
}

struct CameraIdentity {
    let vector: [Float]
    let pose: OwnerPose
}

enum NearbyDetection: String, CaseIterable, Identifiable {
    case facingScreen, anyFace
    var id: String { rawValue }
    var title: String { self == .facingScreen ? "Facing screen" : "Any extra face" }
}

protocol NearbyCameraSession: AnyObject {
    var previewSession: AVCaptureSession? { get }
    func start()
    func stop()
    func configureRecognition(_ enabled: Bool)
    func configureDevice(_ id: String?)
}

extension NearbyCameraSession {
    var previewSession: AVCaptureSession? { nil }
    func configureRecognition(_ enabled: Bool) {}
    func configureDevice(_ id: String?) {}
}

@MainActor
final class NearbyPeople: ObservableObject {
    private enum OwnerNoticeState {
        case checking, matching, unmatched, unreadable, noFace, additionalFaces
    }
    // The switch represents the user's choice, not temporary camera availability.
    @Published private(set) var detection: NearbyDetection
    @Published private(set) var wantsMonitoring: Bool
    @Published private(set) var enabled = false
    @Published private(set) var requesting = false
    @Published private(set) var covered = false
    @Published private(set) var alertActive = false
    @Published private(set) var status: NearbyCameraStatus = .off
    @Published private(set) var response: NearbyResponse
    @Published private(set) var warningSoundEnabled: Bool
    @Published private(set) var warningDelay: TimeInterval
    @Published private(set) var warningSecondsRemaining: Int?
    @Published private(set) var pauseSecondsRemaining: Int?
    @Published private(set) var cameras: [CameraChoice] = []
    @Published private(set) var selectedCameraID: String
    let owner: OwnerRecognition
    var onCoverage: ((Bool) -> Void)?
    var onMonitoring: ((Bool) -> Void)?
    var prepareMonitoring: (() -> NearbyCameraFailure?)?
    private let preferences: UserDefaults
    private let cameraAccess: () async -> Bool
    private let makeCamera: (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession
    private let clock: () -> TimeInterval
    private let wallClock: () -> Date
    private let usesWatchdog: Bool
    private var worker: NearbyCameraSession?
    private var presence = NearbyPresence()
    private var attention = NearbyAttentionPolicy()
    private var generation = 0
    private var lastFrame: TimeInterval = 0
    private var lastAcceptedFrame: TimeInterval?
    private var warmingCapture = false
    private var watchdog: Timer?
    private var warningTimer: Timer?
    private var pauseTimer: Timer?
    private var pauseUntil: Date?
    private var pauseUptimeUntil: TimeInterval?
    private var immediateBlur = false
    private var warningPolicy = NearbyWarningPolicy()
    private var ownerObservation: AnyCancellable?
    private var ownerRequired = false
    private var ownerPresence = OwnerPresence(turnPositive: Bool.random())
    private var lastMatchedBounds: CGRect?
    @Published private(set) var ownerPrompt = "Look at the camera"
    @Published private var ownerNoticeState: OwnerNoticeState = .checking
    private var ownerNoticeCandidate: OwnerNoticeState?
    private var ownerNoticeCandidateSince: TimeInterval = 0
    private var pauseReasons: Set<NearbyPauseReason> = []
    private var cameraObservers: [NSObjectProtocol] = []

    init(preferences: UserDefaults = .standard,
         cameraAccess: @escaping () async -> Bool = NearbyPeople.requestCameraAccess,
         makeCamera: @escaping (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession = { SharedFaceCamera(completion: $0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         wallClock: @escaping () -> Date = Date.init,
         usesWatchdog: Bool = true, owner: OwnerRecognition? = nil) {
        self.preferences = preferences
        self.cameraAccess = cameraAccess
        self.makeCamera = makeCamera
        self.clock = clock
        self.wallClock = wallClock
        self.usesWatchdog = usesWatchdog
        self.owner = owner ?? OwnerRecognition(preferences: preferences)
        selectedCameraID = preferences.string(forKey: CameraSelection.preferenceKey) ?? ""
        detection = NearbyDetection(rawValue: preferences.string(forKey: "nearbyDetection") ?? "") ?? .facingScreen
        wantsMonitoring = preferences.bool(forKey: "nearbyEnabled")
        response = NearbyResponse(rawValue: preferences.string(forKey: "nearbyResponse") ?? "") ?? .blur
        warningSoundEnabled = preferences.object(forKey: "nearbyWarningSound") as? Bool ?? true
        warningDelay = NearbyWarningPolicy.normalizedDelay(
            preferences.object(forKey: "nearbyWarningDelay") as? Double ?? NearbyWarningPolicy.defaultDelay)
        if wantsMonitoring, let until = preferences.object(forKey: "nearbyPauseUntil") as? Date, until > wallClock() {
            pauseUntil = until
            pauseSecondsRemaining = min(300, Int(ceil(until.timeIntervalSince(wallClock()))))
            pauseUptimeUntil = clock() + Double(pauseSecondsRemaining ?? 0)
        }
        ownerObservation = self.owner.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
        refreshCameras()
        for name in [AVCaptureDevice.wasConnectedNotification, AVCaptureDevice.wasDisconnectedNotification] {
            cameraObservers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshCameras() }
            })
        }
    }

    func refreshCameras() {
        cameras = CameraSelection.devices().map { CameraChoice(id: $0.uniqueID, name: $0.localizedName) }
    }

    func selectCamera(_ id: String) {
        guard id != selectedCameraID else { return }
        selectedCameraID = id
        preferences.set(id, forKey: CameraSelection.preferenceKey)
        if wantsMonitoring && !temporarilyPaused { begin() }
    }

    nonisolated static func requestCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    var canRetry: Bool {
        if case .unavailable = status { return true }
        return false
    }

    var needsCameraPermission: Bool { status == .unavailable(.permission) }
    var needsAttention: Bool { alertActive || canRetry }
    var requiresBlur: Bool { response == .blur || warningPolicy.escalated || immediateBlur }
    var temporarilyPaused: Bool { pauseUntil != nil }
    var noticeTitle: String {
        if case .unavailable(let failure) = status { return failure.title }
        if ownerRequired { return ownerNoticeTitle }
        return "Additional face detected"
    }
    var noticeDetail: String {
        if covered { return "Blur stays on · Esc to stop" }
        if let remaining = warningSecondsRemaining {
            let minutes = remaining / 60
            let seconds = String(format: "%02d", remaining % 60)
            return "Blurs in \(minutes):\(seconds) · Esc to stop"
        }
        if canRetry { return "Open Settings to retry" }
        return "Look around · Esc to dismiss"
    }

    private var ownerNoticeTitle: String {
        switch ownerNoticeState {
        case .checking: return "Checking your face…"
        case .matching: return alertActive ? ownerPrompt : "Owner verified"
        case .unmatched: return "Owner not verified"
        case .unreadable: return "Face the camera in good light"
        case .noFace: return "No face in view"
        case .additionalFaces: return "Additional face detected"
        }
    }

    var message: String {
        switch status {
        case .off: return "Off"
        case .paused:
            if let seconds = pauseSecondsRemaining { return String(format: "Paused · Resumes in %d:%02d", seconds / 60, seconds % 60) }
            return pauseReasons.contains(.protectionTest) ? "Paused during protection check" : "Paused while your Mac is inactive"
        case .requesting: return ownerRequired ? "Unlocking your saved face…" : "Waiting for camera access…"
        case .starting: return covered ? "Restarting camera · Blur stays on" : "Starting camera…"
        case .unavailable(let failure): return failure.title + (covered ? " · Blur stays on" : " · Monitoring stopped")
        case .watching(let count):
            if ownerRequired {
                return ownerNoticeTitle
            }
            if count == 0 { return covered ? "No face in view · Blur stays on" : "No face in view · Detection is limited" }
            if alertActive { return count > 1 ? "Additional face detected" : "Waiting for a steady single face…" }
            return count > 1 ? "Checking nearby head directions…" : "One face in view"
        }
    }

    func setDetection(_ value: NearbyDetection) {
        detection = value
        preferences.set(value.rawValue, forKey: "nearbyDetection")
        attention = NearbyAttentionPolicy()
        presence.interrupt()
    }

    func setResponse(_ value: NearbyResponse) {
        guard response != value else { return }
        response = value
        preferences.set(value.rawValue, forKey: "nearbyResponse")
        resetWarningDeadline()
        updateProtection()
    }

    func setWarningDelay(_ seconds: TimeInterval) {
        let value = NearbyWarningPolicy.normalizedDelay(seconds)
        guard value != warningDelay else { return }
        warningDelay = value
        preferences.set(value, forKey: "nearbyWarningDelay")
        updateProtection()
    }

    func setWarningSoundEnabled(_ value: Bool) {
        guard warningSoundEnabled != value else { return }
        warningSoundEnabled = value
        preferences.set(value, forKey: "nearbyWarningSound")
    }

    func setEnabled(_ value: Bool) {
        guard value else { stop(); return }
        cancelTimedPause()
        wantsMonitoring = true
        preferences.set(true, forKey: "nearbyEnabled")
        guard !enabled, !requesting else { return }
        begin()
    }

    func retry() {
        guard wantsMonitoring, canRetry else { return }
        begin()
    }

    // Called after the app has connected protection and shortcut callbacks.
    func restore() {
        guard wantsMonitoring, !enabled, !requesting, !canRetry else { return }
        if pauseUntil != nil { updatePauseDeadline(); return }
        begin()
    }

    func blurNow() {
        guard wantsMonitoring, needsAttention, !temporarilyPaused else { return }
        immediateBlur = true
        alertActive = true
        if !ownerRequired { presence.requireClear() }
        updateProtection()
    }

    func pauseForFiveMinutes() {
        guard wantsMonitoring else { return }
        stopSession()
        pauseUntil = wallClock().addingTimeInterval(300)
        pauseUptimeUntil = clock() + 300
        preferences.set(pauseUntil, forKey: "nearbyPauseUntil")
        status = .paused
        updatePauseDeadline()
    }

    func resumeNow() {
        guard wantsMonitoring, temporarilyPaused else { return }
        cancelTimedPause()
        begin()
    }

    func updatePauseDeadline() {
        guard let pauseUntil else { return }
        // Wall time includes sleep; uptime prevents a backward clock change
        // from extending a five-minute pause indefinitely.
        let seconds = min(pauseUntil.timeIntervalSince(wallClock()), (pauseUptimeUntil ?? clock()) - clock())
        let remaining = min(300, max(0, Int(ceil(seconds))))
        if remaining == 0 { cancelTimedPause(); if wantsMonitoring { begin() }; return }
        if pauseSecondsRemaining != remaining { pauseSecondsRemaining = remaining }
        status = .paused
        guard pauseTimer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePauseDeadline() }
        }
        pauseTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelTimedPause() {
        pauseUntil = nil
        pauseUptimeUntil = nil
        pauseSecondsRemaining = nil
        pauseTimer?.invalidate(); pauseTimer = nil
        preferences.removeObject(forKey: "nearbyPauseUntil")
    }

    func suspend(for reason: NearbyPauseReason) {
        guard pauseReasons.insert(reason).inserted else { return }
        stopSession()
        if wantsMonitoring { status = .paused }
    }

    func resume(after reason: NearbyPauseReason) {
        guard pauseReasons.remove(reason) != nil else { return }
        restore()
    }

    private func begin() {
        guard !temporarilyPaused else { updatePauseDeadline(); return }
        guard pauseReasons.isEmpty else { status = .paused; return }
        guard !owner.busy, !owner.enrolling else { return }
        if let failure = prepareMonitoring?() {
            failed(failure)
            return
        }
        generation += 1
        let token = generation
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        presence.interrupt()
        attention = NearbyAttentionPolicy()
        ownerRequired = owner.enabled
        ownerPresence = OwnerPresence(turnPositive: Bool.random())
        resetOwnerNotice()
        ownerPrompt = ownerPresence.challenge.prompt
        if ownerRequired {
            enabled = true // Remain armed/turn-off-able if authentication fails.
            alertActive = true
        }
        requesting = true
        status = .requesting
        // Owner mode starts protected, including while authentication is pending.
        updateProtection()
        Task { [weak self, cameraAccess] in
            guard let self, self.generation == token else { return }
            if self.ownerRequired {
                do { try await self.owner.prepareForMonitoring() }
                catch {
                    guard self.generation == token else { return }
                    self.failed(.ownerAccess)
                    return
                }
            }
            let allowed = await cameraAccess()
            guard self.generation == token else { return }
            self.requesting = false
            guard allowed else { self.failed(.permission); return }
            self.enabled = true
            self.lastFrame = self.clock()
            self.lastAcceptedFrame = nil
            self.status = .starting
            self.updateProtection()
            let worker = self.makeCamera { [weak self] result in
                Task { @MainActor in
                    guard let self, self.generation == token, self.enabled else { return }
                    switch result {
                    case .success(let sample): self.received(sample)
                    case .failure(let failure): self.failed(failure)
                    }
                }
            }
            self.worker = worker
            worker.configureDevice(self.selectedCameraID)
            worker.configureRecognition(self.ownerRequired)
            worker.start()
            if self.usesWatchdog {
                let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in self?.checkCameraHealth() }
                }
                self.watchdog = timer
                RunLoop.main.add(timer, forMode: .common)
            }
        }
    }

    func checkCameraHealth() {
        guard enabled, worker != nil, clock() - lastFrame > 4 else { return }
        failed(.stalled)
    }

    private func received(_ sample: NearbyFaceSample) {
        let now = clock()
        guard sample.count >= 0, sample.capturedAt.isFinite, sample.capturedAt >= lastFrame,
              sample.capturedAt <= now, now - sample.capturedAt <= 1 else { return }
        if let lastAcceptedFrame, sample.capturedAt <= lastAcceptedFrame { return }
        if let lastAcceptedFrame, sample.capturedAt - lastAcceptedFrame > 0.6 {
            ownerNoticeCandidate = nil
        }
        lastAcceptedFrame = sample.capturedAt
        lastFrame = sample.capturedAt
        let ownerIndices = sample.identities.indices.filter { index in
            guard let identity = sample.identities[index] else { return false }
            return owner.template?.matches(identity.vector) == true && identity.pose.isValid
        }
        let ownerIndex = ownerIndices.count == 1 ? ownerIndices.first : nil
        let facingThreat: Bool
        if let faces = sample.faces {
            facingThreat = attention.observe(faces, ownerIndex: ownerRequired ? ownerIndex : nil, at: sample.capturedAt)
        } else { facingThreat = sample.count > 1 }
        let extraThreat = detection == .anyFace ? sample.count > 1 : facingThreat
        let detected: Bool
        if ownerRequired {
            let identity = ownerIndex.flatMap { sample.identities[$0] }
            let vector = identity?.vector ?? (sample.count == 1 ? sample.vector : nil)
            let pose = identity?.pose ?? (sample.count == 1 ? sample.pose : nil)
            let ownerMatches = !extraThreat && vector.map { owner.template?.matches($0) == true } == true && pose?.isValid == true
            let ownerBounds = ownerIndex.flatMap { sample.bounds.indices.contains($0) ? sample.bounds[$0] : nil } ?? (sample.count == 1 ? sample.bounds.first : nil)
            let lostLandmarks = sample.count == 1 && (vector == nil || pose?.isValid != true) &&
                OwnerPresence.isContinuousFace(lastMatchedBounds, ownerBounds)
            detected = ownerPresence.observe(matches: ownerMatches, pose: pose, openEyes: owner.template?.openEyes ?? 0.3,
                                             at: sample.capturedAt, continuousFaceWithMissingLandmarks: lostLandmarks)
            if ownerMatches { lastMatchedBounds = ownerBounds }
            else if !lostLandmarks { lastMatchedBounds = nil }
            if detected && !alertActive && !ownerPresence.recoveringLandmarks { ownerPresence.interrupt(turnPositive: Bool.random()) }
            let prompt = ownerPresence.recoveringLandmarks ? "Face the camera again" : ownerPresence.challenge.prompt
            if ownerPrompt != prompt { ownerPrompt = prompt }
            let observation: OwnerNoticeState
            if extraThreat { observation = .additionalFaces }
            else if sample.count == 0 { observation = .noFace }
            else if vector == nil || pose?.isValid != true { observation = .unreadable }
            else { observation = ownerMatches ? .matching : .unmatched }
            updateOwnerNotice(observation, at: sample.capturedAt)
        } else {
            // Preserve the existing steady-clear and no-face behavior.
            detected = presence.observe(faceCount: sample.count == 0 ? 0 : extraThreat ? 2 : 1, at: sample.capturedAt)
        }
        if detected != alertActive { alertActive = detected }
        let next = NearbyCameraStatus.watching(sample.count)
        if status != next { status = next }
        updateProtection()
    }

    private func resetOwnerNotice() {
        ownerNoticeState = .checking
        ownerNoticeCandidate = nil
        lastMatchedBounds = nil
    }

    // Stabilize presentation only. Every fresh sample still reaches the owner
    // policy above, so a delayed label cannot defer blur or authorize clearing.
    private func updateOwnerNotice(_ observation: OwnerNoticeState, at time: TimeInterval) {
        guard observation != ownerNoticeState else { ownerNoticeCandidate = nil; return }
        if ownerNoticeCandidate != observation {
            ownerNoticeCandidate = observation
            ownerNoticeCandidateSince = time
        }
        guard time - ownerNoticeCandidateSince >= 0.3 else { return }
        ownerNoticeState = observation
        ownerNoticeCandidate = nil
    }

    private func failed(_ failure: NearbyCameraFailure) {
        generation += 1
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        requesting = false
        presence.interrupt()
        if ownerRequired {
            ownerPresence.interrupt(turnPositive: Bool.random())
            resetOwnerNotice()
            alertActive = true
            owner.endMonitoring()
        }
        status = .unavailable(failure)
        updateProtection()
    }

    private func updateProtection() {
        if !alertActive && !canRetry { immediateBlur = false }
        updateWarningDeadline()
        if warningPolicy.escalated && !alertActive {
            alertActive = true
            if !ownerRequired { presence.requireClear() }
        }
        let nextCovered = (response == .blur && alertActive) || warningPolicy.escalated || immediateBlur
        let nextWarming = nextCovered || (response == .blur && enabled && !canRetry)
        if nextWarming != warmingCapture {
            warmingCapture = nextWarming
            onMonitoring?(nextWarming)
        }
        if nextCovered != covered {
            covered = nextCovered
            onCoverage?(nextCovered)
        }
    }

    func checkWarningDeadline() {
        updateProtection()
    }

    private func updateWarningDeadline() {
        warningPolicy.update(active: response == .warning && needsAttention, delay: warningDelay, at: clock())
        if warningSecondsRemaining != warningPolicy.secondsRemaining {
            warningSecondsRemaining = warningPolicy.secondsRemaining
        }
        guard let remaining = warningSecondsRemaining, remaining > 0 else {
            warningTimer?.invalidate(); warningTimer = nil
            return
        }
        guard warningTimer == nil else { return }
        // Camera callbacks can stop during a failure. The deadline and countdown
        // therefore have their own clock and do not depend on another frame.
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkWarningDeadline() }
        }
        warningTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func resetWarningDeadline() {
        warningTimer?.invalidate(); warningTimer = nil
        warningPolicy = NearbyWarningPolicy()
        warningSecondsRemaining = nil
    }

    func stop(file: StaticString = #fileID, line: UInt = #line) {
        if wantsMonitoring {
            Logger(subsystem: "local.clinton.QuietGlass", category: "NearbyPeople")
                .notice("Detection turned off at \(String(describing: file), privacy: .public):\(line)")
        }
        wantsMonitoring = false
        preferences.set(false, forKey: "nearbyEnabled")
        cancelTimedPause()
        stopSession()
    }

    func shutdown() {
        pauseTimer?.invalidate(); pauseTimer = nil
        for observer in cameraObservers { NotificationCenter.default.removeObserver(observer) }
        cameraObservers.removeAll()
        stopSession()
    }

    private func stopSession() {
        generation += 1
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        resetWarningDeadline()
        requesting = false
        enabled = false
        covered = false
        alertActive = false
        immediateBlur = false
        warmingCapture = false
        presence = NearbyPresence()
        attention = NearbyAttentionPolicy()
        owner.endMonitoring()
        ownerRequired = false
        resetOwnerNotice()
        ownerPresence = OwnerPresence(turnPositive: Bool.random())
        lastAcceptedFrame = nil
        status = .off
        onCoverage?(false)
        onMonitoring?(false)
    }
}

final class FaceCamera: NSObject, NearbyCameraSession, AVCaptureVideoDataOutputSampleBufferDelegate {
    private static let captureQueue = DispatchQueue(label: "local.clinton.QuietGlass.camera", qos: .userInitiated)
    private let queue = FaceCamera.captureQueue
    private let session = AVCaptureSession()
    var previewSession: AVCaptureSession? { session }
    private let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    private var lastScan: TimeInterval = 0
    private var stopped = false
    private var observers: [NSObjectProtocol] = []
    private var analysisFailures = 0
    private var recognition = false
    private var recognizer: OwnerFaceModel?
    private var deviceID: String?

    init(recognition: Bool = false, completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) {
        self.recognition = recognition; self.completion = completion
    }

    func configureRecognition(_ enabled: Bool) {
        queue.async { [self] in
            guard !stopped else { return }
            recognition = enabled
            if enabled && recognizer == nil {
                do { recognizer = try OwnerFaceModel() }
                catch { completion(.failure(.recognition)) }
            } else if !enabled { recognizer = nil }
        }
    }
    func configureDevice(_ id: String?) { queue.async { [self] in deviceID = id } }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            do {
                if recognition && recognizer == nil {
                    do { recognizer = try OwnerFaceModel() }
                    catch { throw NearbyCameraFailure.recognition }
                }
                guard let device = CameraSelection.device(id: deviceID) else { throw NearbyCameraFailure.noCamera }
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                session.beginConfiguration()
                if session.canSetSessionPreset(.vga640x480) { session.sessionPreset = .vga640x480 }
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    throw NearbyCameraFailure.configuration
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                // Only the on-screen preview is mirrored. Pose directions must
                // always refer to the person's own left and right.
                if let connection = output.connection(with: .video), connection.isVideoMirroringSupported {
                    connection.automaticallyAdjustsVideoMirroring = false
                    connection.isVideoMirrored = false
                }
                limitFrameRate(device)
                observe(AVCaptureSession.runtimeErrorNotification, object: session, failure: .configuration)
                observe(AVCaptureSession.wasInterruptedNotification, object: session, failure: .interrupted)
                observe(AVCaptureDevice.wasDisconnectedNotification, object: device, failure: .disconnected)
                session.startRunning()
                if !session.isRunning { completion(.failure(.configuration)) }
            } catch { completion(.failure(error as? NearbyCameraFailure ?? .configuration)) }
        }
    }

    private func limitFrameRate(_ device: AVCaptureDevice) {
        let fps: Double = 10
        guard let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.minFrameRate <= fps && $0.maxFrameRate >= fps }),
              (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if #available(macOS 15.0, *), device.isAutoVideoFrameRateEnabled { return }
        let duration = CMTime(value: 1, timescale: CMTimeScale(fps))
        if CMTimeCompare(duration, range.maxFrameDuration) <= 0 && CMTimeCompare(duration, range.minFrameDuration) >= 0 {
            device.activeVideoMinFrameDuration = duration
        }
    }

    private func observe(_ name: Notification.Name, object: AnyObject, failure: NearbyCameraFailure) {
        observers.append(NotificationCenter.default.addObserver(forName: name, object: object, queue: nil) { [weak self] _ in
            guard let self else { return }
            self.queue.async { [self] in
                guard !self.stopped else { return }
                self.completion(.failure(failure))
            }
        })
    }

    func stop() {
        queue.async { [self] in
            stopped = true
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
            observers.removeAll()
            for output in session.outputs {
                (output as? AVCaptureVideoDataOutput)?.setSampleBufferDelegate(nil, queue: nil)
            }
            session.stopRunning()
            for output in session.outputs { session.removeOutput(output) }
            for input in session.inputs { session.removeInput(input) }
            recognizer = nil
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !stopped, now - lastScan >= 0.09, let buffer = sampleBuffer.imageBuffer else { return }
        lastScan = now
        do {
            let sample = try autoreleasepool {
                let faces: [VNFaceObservation]
                if recognition {
                    faces = try OwnerFaceDetector.observations(in: buffer)
                } else {
                    let request = VNDetectFaceRectanglesRequest()
                    request.revision = VNDetectFaceRectanglesRequestRevision3
                    try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
                    faces = (request.results ?? []).filter { $0.confidence >= 0.6 }
                }
                var sample = NearbyFaceSample(count: faces.count, capturedAt: now, bounds: faces.map(\.boundingBox))
                sample.faces = faces.map { CameraFace(bounds: $0.boundingBox, yaw: $0.yaw?.doubleValue, pitch: $0.pitch?.doubleValue) }
                if recognition {
                    guard let recognizer else { throw OwnerModelError.unavailable }
                    sample.identities = try faces.map { face in
                        guard let features = try recognizer.features(buffer: buffer, face: face) else { return nil }
                        return CameraIdentity(vector: features.vector, pose: features.pose)
                    }
                    if faces.count == 1, let identity = sample.identities.first ?? nil {
                        sample.vector = identity.vector; sample.pose = identity.pose
                    }
                }
                return sample
            }
            analysisFailures = 0
            completion(.success(sample))
        } catch {
            analysisFailures += 1
            if analysisFailures >= 3 { completion(.failure(.analysis)) }
        }
    }
}
