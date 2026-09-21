//  Created by Clinton Imaro on 20/09/2026.

import AVFoundation
import Vision
import Combine
import ShieldCore

@MainActor
final class NearbyPeople: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var requesting = false
    @Published private(set) var covered = false
    @Published private(set) var message = "Off"
    var onCoverage: ((Bool) -> Void)?
    var onMonitoring: ((Bool) -> Void)?
    private var worker: FaceCamera?
    private var presence = NearbyPresence()
    private var generation = 0
    private var lastFrame: TimeInterval = 0
    private var watchdog: Timer?

    func setEnabled(_ value: Bool) {
        if value, enabled || requesting { return }
        generation += 1
        let token = generation
        if !value { stop(); return }
        guard !enabled else { return }
        requesting = true
        message = "Waiting for camera access…"
        Task { [weak self] in
            let allowed: Bool
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized: allowed = true
            case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
            default: allowed = false
            }
            guard let self, self.generation == token else { return }
            self.requesting = false
            guard allowed else { self.message = "Allow camera access in System Settings to use this feature."; return }
            self.enabled = true
            self.lastFrame = ProcessInfo.processInfo.systemUptime
            self.message = "Starting camera…"
            self.onMonitoring?(true)
            let worker = FaceCamera { [weak self] result in
                Task { @MainActor in
                    guard let self, self.generation == token, self.enabled else { return }
                    switch result {
                    case .success(let count): self.received(count)
                    case .failure: self.cameraFailed()
                    }
                }
            }
            self.worker = worker
            worker.start()
            self.watchdog = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.enabled,
                          ProcessInfo.processInfo.systemUptime - self.lastFrame > 4 else { return }
                    self.cameraFailed()
                }
            }
            RunLoop.main.add(self.watchdog!, forMode: .common)
        }
    }

    private func received(_ count: Int) {
        lastFrame = ProcessInfo.processInfo.systemUptime
        let value = presence.observe(faceCount: count, at: lastFrame)
        if value != covered { covered = value; onCoverage?(value) }
        let next = covered ? "Additional face detected · Blur requested" : count == 0 ? "No face in view" : count > 1 ? "Checking an additional face…" : "One face in view"
        if message != next { message = next }
    }

    private func cameraFailed() {
        generation += 1
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        if !covered { onMonitoring?(false) }
        message = covered ? "Camera unavailable · Blur stays on until you turn this off" : "Camera unavailable · Turn off and on to retry"
    }

    func stop() {
        generation += 1
        worker?.stop(); worker = nil
        watchdog?.invalidate(); watchdog = nil
        requesting = false
        enabled = false
        covered = false
        presence = NearbyPresence()
        message = "Off"
        onCoverage?(false)
        onMonitoring?(false)
    }
}

private final class FaceCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private let queue = DispatchQueue(label: "local.clinton.QuietGlass.camera", qos: .userInitiated)
    private let session = AVCaptureSession()
    private let completion: (Result<Int, Error>) -> Void
    private var lastScan: TimeInterval = 0
    private var stopped = false
    private enum Failure: Error { case noCamera, configuration }

    init(completion: @escaping (Result<Int, Error>) -> Void) { self.completion = completion }

    func start() {
        queue.async { [self] in
            guard !stopped else { return }
            do {
                guard let device = AVCaptureDevice.default(for: .video) else { throw Failure.noCamera }
                let input = try AVCaptureDeviceInput(device: device)
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                output.setSampleBufferDelegate(self, queue: queue)
                session.beginConfiguration()
                session.sessionPreset = .vga640x480
                guard session.canAddInput(input), session.canAddOutput(output) else {
                    session.commitConfiguration()
                    throw Failure.configuration
                }
                session.addInput(input)
                session.addOutput(output)
                session.commitConfiguration()
                session.startRunning()
            } catch { completion(.failure(error)) }
        }
    }

    func stop() {
        queue.async { [self] in
            stopped = true
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
            completion(.success(count))
        } catch { completion(.failure(error)) }
    }
}
