// Clinton Imaro was here 20/09/2026.

import CoreImage
import ScreenCaptureKit

final class DisplayCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let id: UUID
    private var stream: SCStream!
    private let frameQueue = DispatchQueue(label: "local.clinton.QuietGlass.frames", qos: .userInteractive)
    private let renderQueue = DispatchQueue(label: "local.clinton.QuietGlass.blur", qos: .userInteractive)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let onFrame: @MainActor (CGImage) -> Void
    private let onFailure: @MainActor (Error) -> Void
    private let onSample: ((CVPixelBuffer) -> Void)?
    private var radius: Double
    private var pendingBuffer: CVPixelBuffer?
    private var lastBuffer: CVPixelBuffer?
    private var rendering = false
    private var stopped = false

    init(id: UUID, filter: SCContentFilter, configuration: SCStreamConfiguration, radius: Double,
         onFrame: @escaping @MainActor (CGImage) -> Void,
         onFailure: @escaping @MainActor (Error) -> Void,
         onSample: ((CVPixelBuffer) -> Void)? = nil) {
        self.id = id
        self.radius = radius
        self.onFrame = onFrame
        self.onFailure = onFailure
        self.onSample = onSample
        super.init()
        stream = SCStream(filter: filter, configuration: configuration, delegate: self)
    }

    func start() async throws {
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: frameQueue)
        try await stream.startCapture()
    }

    func stop() {
        frameQueue.async { [self] in stopped = true; pendingBuffer = nil; lastBuffer = nil }
        let stream = stream!
        Task { try? await stream.stopCapture() }
    }

    func setRadius(_ value: Double) {
        frameQueue.async { [self] in
            guard !stopped else { return }
            radius = value
            pendingBuffer = lastBuffer
            renderNextFrame()
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        frameQueue.async { [self] in
            guard !stopped else { return }
            stopped = true
            pendingBuffer = nil
            lastBuffer = nil
            Task { @MainActor [onFailure] in onFailure(error) }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard !stopped, type == .screen, sampleBuffer.isValid,
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let rawStatus = attachments.first?[.status] as? Int,
              SCFrameStatus(rawValue: rawStatus) == .complete,
              let buffer = sampleBuffer.imageBuffer else { return }
        lastBuffer = buffer
        onSample?(buffer)
        pendingBuffer = buffer
        renderNextFrame()
    }

    private func renderNextFrame() {
        guard !stopped, !rendering, let buffer = pendingBuffer else { return }
        pendingBuffer = nil
        rendering = true
        let radius = radius
        renderQueue.async { [self] in
            let image: CGImage? = autoreleasepool {
                let input = CIImage(cvPixelBuffer: buffer)
                let output = radius > 0 ? input.clampedToExtent()
                    .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
                    .cropped(to: input.extent) : input
                return context.createCGImage(output, from: input.extent)
            }
            frameQueue.async { [self] in
                rendering = false
                guard !stopped else { return }
                if let image { Task { @MainActor [onFrame] in onFrame(image) } }
                renderNextFrame()
            }
        }
    }
}
