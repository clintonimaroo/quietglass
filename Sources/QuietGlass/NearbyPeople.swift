//  Created by Clinton Imaro on 20/09/2026.

import AVFoundation
import Vision
import Combine
import ShieldCore

enum NearbyResponse: String, CaseIterable, Identifiable {
    case warning, blur
    var id: String { rawValue }
    var title: String { self == .warning ? "Warn me" : "Blur automatically" }
}

enum NearbyCameraFailure: Error, Equatable {
    case permission, noCamera, configuration, interrupted, disconnected, stalled, analysis, recognition, ownerAccess

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
        }
    }
}

enum NearbyCameraStatus: Equatable {
    case off, requesting, starting, watching(Int), unavailable(NearbyCameraFailure)
}

struct NearbyFaceSample {
    let count: Int
    let capturedAt: TimeInterval
    var vector: [Float]? = nil
    var pose: OwnerPose? = nil
}

protocol NearbyCameraSession: AnyObject {
    var previewSession: AVCaptureSession? { get }
    func start()
    func stop()
    func configureRecognition(_ enabled: Bool)
}

extension NearbyCameraSession {
    var previewSession: AVCaptureSession? { nil }
    func configureRecognition(_ enabled: Bool) {}
}

@MainActor
final class NearbyPeople: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requesting = false
    @Published private(set) var covered = false
    @Published private(set) var alertActive = false
    @Published private(set) var status: NearbyCameraStatus = .off
    @Published private(set) var response: NearbyResponse
    let owner: OwnerRecognition
    var onCoverage: ((Bool) -> Void)?
    var onMonitoring: ((Bool) -> Void)?
    private let preferences: UserDefaults
    private let cameraAccess: () async -> Bool
    private let makeCamera: (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession
    private let clock: () -> TimeInterval
    private let usesWatchdog: Bool
    private var worker: NearbyCameraSession?
    private var presence = NearbyPresence()
    private var generation = 0
    private var lastFrame: TimeInterval = 0
    private var lastAcceptedFrame: TimeInterval?
    private var warmingCapture = false
    private var watchdog: Timer?
    private var ownerObservation: AnyCancellable?
    private var ownerRequired = false
    private var ownerPresence = OwnerPresence(turnPositive: Bool.random())
    @Published private(set) var ownerPrompt = "Look at the camera"
    private var ownerMatches = false

    init(preferences: UserDefaults = .standard,
         cameraAccess: @escaping () async -> Bool = NearbyPeople.requestCameraAccess,
         makeCamera: @escaping (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession = { FaceCamera(completion: $0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         usesWatchdog: Bool = true, owner: OwnerRecognition? = nil) {
        self.preferences = preferences
        self.cameraAccess = cameraAccess
        self.makeCamera = makeCamera
        self.clock = clock
        self.usesWatchdog = usesWatchdog
        self.owner = owner ?? OwnerRecognition(preferences: preferences)
        response = NearbyResponse(rawValue: preferences.string(forKey: "nearbyResponse") ?? "") ?? .blur
        ownerObservation = self.owner.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
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
    var noticeTitle: String {
        if case .unavailable(let failure) = status { return failure.title }
        if ownerRequired { return ownerMatches ? ownerPrompt : "Owner not verified" }
        return "Additional face detected"
    }
    var noticeDetail: String { covered ? "Blur stays on · Esc to stop" : canRetry ? "Open Settings to retry" : "Look around · Esc to dismiss" }

    var message: String {
        switch status {
        case .off: return "Off"
        case .requesting: return ownerRequired ? "Unlocking your saved face…" : "Waiting for camera access…"
        case .starting: return covered ? "Restarting camera · Blur stays on" : "Starting camera…"
        case .unavailable(let failure): return failure.title + (covered ? " · Blur stays on" : " · Monitoring stopped")
        case .watching(let count):
            if ownerRequired {
                if count > 1 { return "Additional face detected · Owner check paused" }
                if !ownerMatches { return "Owner not verified · Face the camera in good light" }
                return alertActive ? ownerPrompt : "Owner verified"
            }
            if count == 0 { return covered ? "No face in view · Blur stays on" : "No face in view · Detection is limited" }
            if alertActive { return count > 1 ? "Additional face detected" : "Waiting for a steady single face…" }
            return count > 1 ? "Checking an additional face…" : "One face in view"
        }
    }

    func setResponse(_ value: NearbyResponse) {
        guard response != value else { return }
        response = value
        preferences.set(value.rawValue, forKey: "nearbyResponse")
        updateProtection()
    }

    func setEnabled(_ value: Bool) {
        guard value else { stop(); return }
        guard !enabled, !requesting else { return }
        begin()
    }

    func retry() {
        guard canRetry else { return }
        begin()
    }

    private func begin() {
        generation += 1
        let token = generation
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        presence.interrupt()
        ownerRequired = owner.enabled
        ownerPresence = OwnerPresence(turnPositive: Bool.random())
        ownerMatches = false
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
            guard let self else { return }
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
        lastAcceptedFrame = sample.capturedAt
        lastFrame = sample.capturedAt
        let detected: Bool
        if ownerRequired {
            let template = owner.template
            ownerMatches = sample.count == 1 && sample.vector.map { template?.matches($0) == true } == true && sample.pose != nil
            detected = ownerPresence.observe(matches: ownerMatches, pose: sample.pose, openEyes: template?.openEyes ?? 0.3, at: sample.capturedAt)
            if detected && !alertActive { ownerPresence.interrupt(turnPositive: Bool.random()) }
            ownerPrompt = ownerPresence.challenge.prompt
        } else {
            detected = presence.observe(faceCount: sample.count, at: sample.capturedAt)
        }
        if detected != alertActive { alertActive = detected }
        let next = NearbyCameraStatus.watching(sample.count)
        if status != next { status = next }
        updateProtection()
    }

    private func failed(_ failure: NearbyCameraFailure) {
        generation += 1
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        requesting = false
        presence.interrupt()
        if ownerRequired {
            ownerPresence.interrupt(turnPositive: Bool.random())
            ownerMatches = false
            alertActive = true
            owner.endMonitoring()
        }
        status = .unavailable(failure)
        updateProtection()
    }

    private func updateProtection() {
        let nextCovered = response == .blur && alertActive
        let nextWarming = response == .blur && (nextCovered || (enabled && !canRetry))
        if nextWarming != warmingCapture {
            warmingCapture = nextWarming
            onMonitoring?(nextWarming)
        }
        if nextCovered != covered {
            covered = nextCovered
            onCoverage?(nextCovered)
        }
    }

    func stop() {
        generation += 1
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        requesting = false
        enabled = false
        covered = false
        alertActive = false
        warmingCapture = false
        presence = NearbyPresence()
        owner.endMonitoring()
        ownerRequired = false
        ownerMatches = false
        ownerPresence = OwnerPresence(turnPositive: Bool.random())
        lastAcceptedFrame = nil
        status = .off
        onCoverage?(false)
        onMonitoring?(false)
    }
}

final class FaceCamera: NSObject, NearbyCameraSession, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "local.clinton.QuietGlass.camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    var previewSession: AVCaptureSession? { session }
    private let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    private var lastScan: TimeInterval = 0
    private var stopped = false
    private var observers: [NSObjectProtocol] = []
    private var analysisFailures = 0
    private var recognition = false
    private var recognizer: OwnerFaceModel?

    init(recognition: Bool = false, completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) {
        self.recognition = recognition; self.completion = completion
    }

    func configureRecognition(_ enabled: Bool) { queue.async { [self] in recognition = enabled } }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            do {
                if recognition {
                    do { recognizer = try OwnerFaceModel() }
                    catch { throw NearbyCameraFailure.recognition }
                }
                guard let device = AVCaptureDevice.default(for: .video) else { throw NearbyCameraFailure.noCamera }
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
        let fps: Double = recognition ? 10 : 5
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
        guard !stopped, now - lastScan >= (recognition ? 0.09 : 0.2), let buffer = sampleBuffer.imageBuffer else { return }
        lastScan = now
        do {
            let sample = try autoreleasepool {
                let request: VNImageBasedRequest = recognition ? VNDetectFaceLandmarksRequest() : VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
                let faces = (request.results as? [VNFaceObservation] ?? []).filter { $0.confidence >= 0.6 }
                var sample = NearbyFaceSample(count: faces.count, capturedAt: now)
                if recognition, faces.count == 1 {
                    guard let recognizer else { throw OwnerModelError.unavailable }
                    if let features = try recognizer.features(buffer: buffer, face: faces[0]) {
                        sample.vector = features.vector; sample.pose = features.pose
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
