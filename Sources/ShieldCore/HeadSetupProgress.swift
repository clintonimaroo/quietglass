//  Created by Clinton Imaro on 20/09/2026.

import Foundation

public enum HeadSetupDirection: Int, CaseIterable {
    case up, right, down, left
}

public struct HeadSetupProgress {
    public private(set) var completed: Set<HeadSetupDirection> = []
    private var held = [Double](repeating: 0, count: 4)
    private var amounts = [Double](repeating: 0, count: 4)
    private var lastTime: TimeInterval?

    public init() {}
    public var isComplete: Bool { completed.count == 4 }
    public func fraction(for direction: HeadSetupDirection) -> Double {
        completed.contains(direction) ? 1 : amounts[direction.rawValue]
    }

    public mutating func record(_ offset: HeadOffset, at time: TimeInterval) {
        guard offset.yaw.isFinite, offset.pitch.isFinite, offset.angle.isFinite, time.isFinite,
              offset.angle <= 45, offset.angle >= 0 else {
            held = Array(repeating: 0, count: 4)
            amounts = Array(repeating: 0, count: 4)
            lastTime = nil
            return
        }
        let elapsed = lastTime.map { time - $0 } ?? 0
        lastTime = time
        let delta = elapsed >= 0 && elapsed <= 0.12 ? elapsed : 0
        if delta == 0 { held = Array(repeating: 0, count: 4) }
        let angles = [offset.pitch, -offset.yaw, -offset.pitch, offset.yaw]
        for direction in HeadSetupDirection.allCases where !completed.contains(direction) {
            let index = direction.rawValue
            amounts[index] = max(0, min(0.85, angles[index] / 10 * 0.85))
            held[index] = angles[index] >= 10 ? held[index] + delta : 0
            if held[index] >= 0.2 { completed.insert(direction) }
        }
    }
}
