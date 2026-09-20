//  Created by Clinton Imaro on 20/09/2026.

import Vision
import CoreVideo
import ShieldCore

final class LocalTextAnalyzer {
    private let queue = DispatchQueue(label: "local.clinton.QuietGlass.text", qos: .utility)
    private let lock = NSLock()
    private var busy = false
    private var lastScan: TimeInterval = 0
    private var cancelled = false
    private let options: SensitiveTextOptions
    private let completion: @MainActor (Result<[CGRect], Error>) -> Void

    init(options: SensitiveTextOptions, completion: @escaping @MainActor (Result<[CGRect], Error>) -> Void) {
        self.options = options
        self.completion = completion
    }

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func offer(_ buffer: CVPixelBuffer) {
        let now = ProcessInfo.processInfo.systemUptime
        lock.lock()
        guard !cancelled, !busy, now - lastScan >= 1 else { lock.unlock(); return }
        busy = true
        lastScan = now
        lock.unlock()
        queue.async { [self] in
            let result: Result<[CGRect], Error> = Result {
                try autoreleasepool {
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = false
                    request.recognitionLanguages = ["en-US"]
                    try VNImageRequestHandler(cvPixelBuffer: buffer, options: [:]).perform([request])
                    return Self.regions(in: request.results ?? [], options: options)
                }
            }
            lock.lock()
            busy = false
            let shouldDeliver = !cancelled
            lock.unlock()
            if shouldDeliver { Task { @MainActor [completion] in completion(result) } }
        }
    }

    static func regions(in observations: [VNRecognizedTextObservation], options: SensitiveTextOptions) -> [CGRect] {
        observations.flatMap { observation -> [CGRect] in
            guard let candidate = observation.topCandidates(1).first else { return [] }
            return SensitiveText.ranges(in: candidate.string, options: options).compactMap { match in
                guard let range = Range(match, in: candidate.string) else { return nil }
                let box = (try? candidate.boundingBox(for: range))?.boundingBox ?? observation.boundingBox
                return box.insetBy(dx: -0.003, dy: -0.004).intersection(CGRect(x: 0, y: 0, width: 1, height: 1))
            }
        }
    }
}
