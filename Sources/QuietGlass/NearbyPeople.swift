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
    case permission, noCamera, configuration, interrupted, disconnected, stalled, analysis

    var title: String {
        switch self {
        case .permission: return "Camera access is off"
        case .noCamera: return "No camera available"
        case .interrupted: return "Camera interrupted"
        case .disconnected: return "Camera disconnected"
        case .stalled: return "Camera stopped responding"
        case .analysis: return "Face detection unavailable"
        case .configuration: return "Camera unavailable"
        }
    }
}

enum NearbyCameraStatus: Equatable {
    case off, requesting, starting, watching(Int), unavailable(NearbyCameraFailure)
}

struct NearbyFaceSample {
    let count: Int
    let capturedAt: TimeInterval
}

protocol NearbyCameraSession: AnyObject {
    func start()
    func stop()
}

@MainActor
final class NearbyPeople: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requesting = false
    @Published private(set) var covered = false
    @Published private(set) var alertActive = false
    @Published private(set) var status: NearbyCameraStatus = .off
    @Published private(set) var response: NearbyResponse
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
    private var warmingCapture = false
    private var watchdog: Timer?

    init(preferences: UserDefaults = .standard,
         cameraAccess: @escaping () async -> Bool = NearbyPeople.requestCameraAccess,
         makeCamera: @escaping (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession = { FaceCamera(completion: $0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         usesWatchdog: Bool = true) {
        self.preferences = preferences
        self.cameraAccess = cameraAccess
        self.makeCamera = makeCamera
        self.clock = clock
        self.usesWatchdog = usesWatchdog
        response = NearbyResponse(rawValue: preferences.string(forKey: "nearbyResponse") ?? "") ?? .blur
    }

    nonisolated private static func requestCameraAccess() async -> Bool {
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
        return "Additional face detected"
    }
    var noticeDetail: String { covered ? "Blur stays on · Esc to clear" : canRetry ? "Open Settings to retry" : "Look around · Esc to dismiss" }

    var message: String {
        switch status {
        case .off: return "Off"
        case .requesting: return "Waiting for camera access…"
        case .starting: return covered ? "Restarting camera · Blur stays on" : "Starting camera…"
        case .unavailable(let failure): return failure.title + (covered ? " · Blur stays on" : " · Monitoring stopped")
        case .watching(let count):
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
        requesting = true
        status = .requesting
        Task { [weak self, cameraAccess] in
            let allowed = await cameraAccess()
            guard let self, self.generation == token else { return }
            self.requesting = false
            guard allowed else { self.failed(.permission); return }
            self.enabled = true
            self.lastFrame = self.clock()
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
        lastFrame = sample.capturedAt
        let detected = presence.observe(faceCount: sample.count, at: sample.capturedAt)
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
        status = .off
        onCoverage?(false)
        onMonitoring?(false)
    }
}

final class FaceCamera: NSObject, NearbyCameraSession, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "local.clinton.QuietGlass.camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    private var lastScan: TimeInterval = 0
    private var stopped = false
    private var observers: [NSObjectProtocol] = []
    private var analysisFailures = 0

    init(completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) { self.completion = completion }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            do {
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
        guard let range = device.activeFormat.videoSupportedFrameRateRanges.first(where: { $0.minFrameRate <= 5 && $0.maxFrameRate >= 5 }),
              (try? device.lockForConfiguration()) != nil else { return }
        defer { device.unlockForConfiguration() }
        if #available(macOS 15.0, *), device.isAutoVideoFrameRateEnabled { return }
        let duration = CMTime(value: 1, timescale: 5)
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
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard !stopped, now - lastScan >= 0.2, let buffer = sampleBuffer.imageBuffer else { return }
        lastScan = now
        do {
            let count = try autoreleasepool {
                let request = VNDetectFaceRectanglesRequest()
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:]).perform([request])
                return (request.results ?? []).filter { $0.confidence >= 0.6 }.count
            }
            analysisFailures = 0
            completion(.success(NearbyFaceSample(count: count, capturedAt: now)))
        } catch {
            analysisFailures += 1
            if analysisFailures >= 3 { completion(.failure(.analysis)) }
        }
    }
}
