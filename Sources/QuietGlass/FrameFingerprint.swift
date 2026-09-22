import CoreVideo
import CryptoKit

enum FrameFingerprint {
    /// Hash every visible pixel, not a sampled grid: even one changed character
    /// must trigger a fresh text scan. Padding outside the image is irrelevant.
    static func digest(_ buffer: CVPixelBuffer) -> SHA256.Digest? {
        guard CVPixelBufferGetPixelFormatType(buffer) == kCVPixelFormatType_32BGRA else { return nil }
        guard CVPixelBufferLockBaseAddress(buffer, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
        let width = CVPixelBufferGetWidth(buffer), height = CVPixelBufferGetHeight(buffer)
        let stride = CVPixelBufferGetBytesPerRow(buffer)
        guard width > 0, height > 0, width <= stride / 4 else { return nil }
        var hash = SHA256()
        withUnsafeBytes(of: width) { hash.update(bufferPointer: $0) }
        withUnsafeBytes(of: height) { hash.update(bufferPointer: $0) }
        for row in 0..<height {
            hash.update(bufferPointer: UnsafeRawBufferPointer(start: base.advanced(by: row * stride), count: width * 4))
        }
        return hash.finalize()
    }
}
