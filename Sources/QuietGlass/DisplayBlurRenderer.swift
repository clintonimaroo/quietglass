//  Created by Clinton Imaro on 20/09/2026.

import CoreImage

final class DisplayBlurRenderer {
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var previous: CGImage?

    func render(_ input: CIImage, radius: Double) -> CGImage? {
        guard !input.extent.isEmpty, !input.extent.isInfinite, !input.extent.isNull else { return previous }
        let blurred = radius > 0 ? input.clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: radius])
            .cropped(to: input.extent) : input
        let background: CIImage
        if let previous, previous.width == Int(input.extent.width), previous.height == Int(input.extent.height) {
            background = CIImage(cgImage: previous)
        } else {
            background = CIImage(color: CIColor(red: 0.08, green: 0.08, blue: 0.08)).cropped(to: input.extent)
        }
        let output = blurred.composited(over: background).cropped(to: input.extent)
        guard let image = context.createCGImage(output, from: input.extent) else { return previous }
        previous = image
        return image
    }
}
