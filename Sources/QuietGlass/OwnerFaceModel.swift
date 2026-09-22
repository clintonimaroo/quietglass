import CoreML
import CoreImage
import Vision
import ShieldCore

enum OwnerModelError: Error { case unavailable, invalidOutput }

enum OwnerFaceDetector {
    static func observations(in buffer: CVPixelBuffer) throws -> [VNFaceObservation] {
        let handler = VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up, options: [:])
        // A landmarks request on its own uses the older internal face detector,
        // whose yaw is quantized to 0 / +/- pi/4. Detect explicitly with revision
        // 3, then preserve those continuous poses while locating the landmarks.
        let detector = VNDetectFaceRectanglesRequest()
        detector.revision = VNDetectFaceRectanglesRequestRevision3
        try handler.perform([detector])
        let faces = (detector.results ?? []).filter { $0.confidence >= 0.6 }
        guard !faces.isEmpty else { return faces }
        let landmarks = VNDetectFaceLandmarksRequest()
        landmarks.revision = VNDetectFaceLandmarksRequestRevision3
        landmarks.inputFaceObservations = faces
        try handler.perform([landmarks])
        // Preserve the detected count if landmarks are temporarily unavailable;
        // feature extraction will reject that frame without inventing a pose.
        if let result = landmarks.results, result.count == faces.count { return result }
        return faces
    }
}

/// Instantiated and used only on the camera's serial queue. No frames leave it.
final class OwnerFaceModel {
    private let model: MLModel
    private let context = CIContext(options: [.cacheIntermediates: false])

    init(bundle: Bundle = .main) throws {
        let url: URL
        if let bundled = bundle.url(forResource: "SFace", withExtension: "mlmodelc") {
            url = bundled
        } else {
            // Distributed apps must not fall back to SwiftPM's generated
            // accessor, which traps when its development bundle is absent.
            guard bundle.bundleURL.pathExtension != "app" else { throw OwnerModelError.unavailable }
            guard let source = Bundle.module.url(forResource: "SFace", withExtension: "mlmodel") else { throw OwnerModelError.unavailable }
            url = try MLModel.compileModel(at: source)
        }
        let configuration = MLModelConfiguration()
        // Full precision, consistent with the checked conversion. Profile before
        // enabling GPU/ANE precision changes for a biometric operating point.
        configuration.computeUnits = .cpuOnly
        model = try MLModel(contentsOf: url, configuration: configuration)
    }

    func features(buffer: CVPixelBuffer, face: VNFaceObservation) throws -> (vector: [Float], pose: OwnerPose)? {
        let width = CGFloat(CVPixelBufferGetWidth(buffer)), height = CGFloat(CVPixelBufferGetHeight(buffer))
        guard let landmarks = face.landmarks, let leftEye = landmarks.leftEye, let rightEye = landmarks.rightEye,
              let nose = landmarks.noseCrest, let lips = landmarks.outerLips, let yaw = face.yaw?.doubleValue,
              let roll = face.roll?.doubleValue, abs(roll) < 0.30,
              face.boundingBox.width * width >= 90, face.boundingBox.height * height >= 90,
              face.boundingBox.minX > 0.02, face.boundingBox.maxX < 0.98,
              face.boundingBox.minY > 0.02, face.boundingBox.maxY < 0.98 else { return nil }
        let box = face.boundingBox
        // Vision coordinates start at the lower left; model alignment starts at
        // the upper left. Sort image-space eyes/corners, not anatomical names.
        func points(_ region: VNFaceLandmarkRegion2D) -> [CGPoint] {
            region.normalizedPoints.map { CGPoint(x: (box.minX + $0.x * box.width) * width,
                                                 y: (1 - box.minY - $0.y * box.height) * height) }
        }
        func mean(_ points: [CGPoint]) -> CGPoint {
            CGPoint(x: points.map(\.x).reduce(0,+) / CGFloat(points.count), y: points.map(\.y).reduce(0,+) / CGFloat(points.count))
        }
        let eyePoints = [points(leftEye), points(rightEye)]
        guard eyePoints.allSatisfy({ $0.count >= 4 }), lips.pointCount >= 4, nose.pointCount >= 3 else { return nil }
        let eyes = eyePoints.map(mean).sorted { $0.x < $1.x }
        let mouth = points(lips).sorted { $0.x < $1.x }
        // The lowest point of the center crest supplies the nose-tip landmark.
        let nosePoints = points(nose)
        let noseTip = nosePoints.max { $0.y < $1.y }!
        let source = [eyes[0], eyes[1], noseTip, mouth.first!, mouth.last!]
        guard let aligned = Self.alignment(source) else { return nil }
        let input = try alignedInput(buffer: buffer, topLeftTransform: aligned)
        let vector = try prediction(input)
        let openness = eyePoints.map { p -> Double in
            let w = (p.map(\.x).max()! - p.map(\.x).min()!)
            return Double((p.map(\.y).max()! - p.map(\.y).min()!) / max(w, 1))
        }
        return (vector, OwnerPose(yaw: yaw, eyes: openness.min()!, widestEye: openness.max()!))
    }

    func alignedInput(buffer: CVPixelBuffer, topLeftTransform aligned: CGAffineTransform) throws -> MLMultiArray {
        let height = CGFloat(CVPixelBufferGetHeight(buffer))
        // Convert the top-left similarity transform to Core Image's bottom-left.
        let t = CGAffineTransform(a: aligned.a, b: -aligned.b, c: -aligned.c, d: aligned.d,
                                  tx: aligned.c * height + aligned.tx,
                                  ty: 112 - aligned.d * height - aligned.ty)
        let image = CIImage(cvPixelBuffer: buffer).transformed(by: t)
        var pixels = [UInt8](repeating: 0, count: 112 * 112 * 4)
        context.render(image, toBitmap: &pixels, rowBytes: 112 * 4, bounds: CGRect(x: 0, y: 0, width: 112, height: 112),
                       format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB))
        let input = try MLMultiArray(shape: [3, 112, 112], dataType: .float32)
        let data = input.dataPointer.bindMemory(to: Float.self, capacity: 3 * 112 * 112)
        // CIContext's bitmap rows are top-to-bottom, matching ONNX/OpenCV RGB.
        for i in 0..<(112 * 112) {
            data[i] = Float(pixels[i * 4])
            data[112 * 112 + i] = Float(pixels[i * 4 + 1])
            data[2 * 112 * 112 + i] = Float(pixels[i * 4 + 2])
        }
        return input
    }

    func prediction(_ input: MLMultiArray) throws -> [Float] {
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["data": input]))
        guard let output = result.featureValue(for: "fc1")?.multiArrayValue, output.count == 128,
              let vector = OwnerTemplate.normalize((0..<128).map { output[$0].floatValue }) else { throw OwnerModelError.invalidOutput }
        return vector
    }

    /// Least-squares similarity transform to SFace's five canonical landmarks.
    static func alignment(_ source: [CGPoint]) -> CGAffineTransform? {
        let target = [CGPoint(x: 38.2946, y: 51.6963), CGPoint(x: 73.5318, y: 51.5014),
                      CGPoint(x: 56.0252, y: 71.7366), CGPoint(x: 41.5493, y: 92.3655), CGPoint(x: 70.7299, y: 92.2041)]
        guard source.count == 5, source.allSatisfy({ $0.x.isFinite && $0.y.isFinite }), source[1].x - source[0].x > 12 else { return nil }
        let sx = source.map(\.x).reduce(0,+) / 5, sy = source.map(\.y).reduce(0,+) / 5
        let tx = target.map(\.x).reduce(0,+) / 5, ty = target.map(\.y).reduce(0,+) / 5
        var denom: CGFloat = 0, real: CGFloat = 0, imaginary: CGFloat = 0
        for (s,t) in zip(source,target) {
            let x = s.x - sx, y = s.y - sy, u = t.x - tx, v = t.y - ty
            denom += x*x + y*y; real += x*u + y*v; imaginary += x*v - y*u
        }
        guard denom > 1 else { return nil }
        let a = real / denom, b = imaginary / denom
        let result = CGAffineTransform(a: a, b: b, c: -b, d: a, tx: tx - a*sx + b*sy, ty: ty - b*sx - a*sy)
        var residual: CGFloat = 0
        for (s,t) in zip(source,target) {
            let p = s.applying(result)
            residual += hypot(p.x - t.x, p.y - t.y)
        }
        residual /= 5
        return residual < 8 ? result : nil
    }
}
