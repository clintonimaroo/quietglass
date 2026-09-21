//  Created by Clinton Imaro on 20/09/2026.

import Foundation
import simd

public struct DisplayHeadTracking {
    public private(set) var centers: [UInt32: simd_quatd] = [:]
    public private(set) var facing: UInt32?
    private var responses: [UInt32: ShieldResponse] = [:]
    private var dismissed = false

    public init() {}

    public mutating func calibrate(_ id: UInt32, at rotation: simd_quatd) {
        centers[id] = rotation
        responses[id] = ShieldResponse()
        dismissed = false
    }

    public mutating func invalidate() { centers = [:]; responses = [:]; facing = nil }
    public mutating func dismiss() { dismissed = true }

    public mutating func coverage(current: simd_quatd, displays: [UInt32], comfort: Double, transition: Double) -> [UInt32: Double] {
        let offsets = centers.filter { displays.contains($0.key) }.mapValues { HeadOffset.between(center: $0, current: current).angle }
        guard let closest = offsets.min(by: { $0.value < $1.value }) else {
            return Dictionary(uniqueKeysWithValues: displays.map { ($0, dismissed ? 0 : 1) })
        }
        if dismissed {
            if closest.value < max(2, comfort - 2) { dismissed = false }
            return Dictionary(uniqueKeysWithValues: displays.map { ($0, 0) })
        }
        if let facing, let previous = offsets[facing], previous <= closest.value + 4 {} else { facing = closest.key }
        return Dictionary(uniqueKeysWithValues: displays.map { id in
            guard id == facing, let angle = offsets[id] else { return (id, 1) }
            var response = responses[id] ?? ShieldResponse()
            response.comfort = comfort
            response.transition = transition
            let value = response.coverage(angle: angle)
            responses[id] = response
            return (id, value)
        })
    }
}
