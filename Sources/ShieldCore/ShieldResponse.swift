// Clinton Imaro was here 20/09/2026.

import Foundation
import simd

public struct HeadOffset: Equatable {
    public var yaw: Double
    public var pitch: Double
    public var angle: Double

    public init(yaw: Double, pitch: Double, angle: Double? = nil) {
        self.yaw = yaw
        self.pitch = pitch
        self.angle = angle ?? acos(max(-1, min(1, cos(yaw * .pi / 180) * cos(pitch * .pi / 180)))) * 180 / .pi
    }

    public static func between(center: simd_quatd, current: simd_quatd) -> HeadOffset {
        let relative = simd_normalize(center.inverse * current)
        let forward = relative.act(SIMD3<Double>(0, 1, 0))
        return HeadOffset(
            yaw: atan2(-forward.x, forward.y) * 180 / .pi,
            pitch: asin(max(-1, min(1, forward.z))) * 180 / .pi,
            angle: acos(max(-1, min(1, forward.y))) * 180 / .pi
        )
    }
}

public struct ShieldResponse {
    public var comfort: Double = 15
    public var transition: Double = 18
    public private(set) var dismissedUntilCentered = false
    private var isCovering = false

    public init(comfort: Double = 15, transition: Double = 18) {
        self.comfort = comfort
        self.transition = transition
    }

    public mutating func dismiss() { dismissedUntilCentered = true; isCovering = false }
    public mutating func recenter() { dismissedUntilCentered = false; isCovering = false }

    public mutating func coverage(angle: Double) -> Double {
        guard angle.isFinite else { return dismissedUntilCentered ? 0 : 1 }
        let threshold = max(2, min(30, comfort))
        if dismissedUntilCentered {
            if angle < threshold - min(2, threshold / 2) { dismissedUntilCentered = false }
            return 0
        }
        if !isCovering {
            guard angle > threshold else { return 0 }
            isCovering = true
        }
        if angle <= threshold - min(3, threshold / 2) {
            isCovering = false
            return 0
        }
        return max(0.01, min(1, (angle - threshold) / max(5, min(30, transition))))
    }
}

public enum ShieldDirection: String, CaseIterable {
    case left, right, up, down

    public static func from(_ offset: HeadOffset) -> ShieldDirection {
        if abs(offset.pitch) > abs(offset.yaw) { return offset.pitch >= 0 ? .up : .down }
        return offset.yaw >= 0 ? .left : .right
    }
}

public enum GlassMask {
    public static func opacity(position: Double, coverage: Double) -> Double {
        guard coverage.isFinite, position.isFinite else { return 0 }
        let progress = max(0, min(1, coverage))
        if progress == 0 { return 0 }
        if progress == 1 { return 1 }
        let feather = 0.48
        let linear = max(0, min(1, (progress * (1 + feather) - position) / feather))
        // Zero slope and acceleration at both ends keep the feather from
        // developing a visible edge as it enters or leaves the display.
        return linear * linear * linear * (linear * (linear * 6 - 15) + 10)
    }
}

public struct GlassTransition {
    public private(set) var value = 0.0
    private var velocity = 0.0
    public init() {}

    public mutating func advance(to requestedTarget: Double, elapsed: Double) -> Double {
        guard requestedTarget.isFinite, elapsed.isFinite else { return value }
        let target = max(0, min(1, requestedTarget))
        let dt = max(0, min(1.0 / 15, elapsed))
        let frequency = 14.0
        let displacement = value - target
        let change = velocity + frequency * displacement
        let decay = exp(-frequency * dt)
        value = target + (displacement + change * dt) * decay
        velocity = (velocity - frequency * change * dt) * decay
        if value < 0 || value > 1 { value = max(0, min(1, value)); velocity = 0 }
        if abs(value - target) < 0.001 && abs(velocity) < 0.02 { value = target; velocity = 0 }
        return value
    }

    public mutating func reset() { value = 0; velocity = 0 }
}
