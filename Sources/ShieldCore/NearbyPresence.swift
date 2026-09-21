//  Created by Clinton Imaro on 20/09/2026.

import Foundation

public struct NearbyPresence {
    public private(set) var covered = false
    private var candidate: Bool?
    private var candidateSince: TimeInterval = 0
    private var lastSample: TimeInterval?

    public init() {}

    @discardableResult public mutating func observe(faceCount: Int, at time: TimeInterval) -> Bool {
        guard time.isFinite, faceCount >= 0 else { return covered }
        if let lastSample, time <= lastSample { return covered }
        if let lastSample, time - lastSample > 1 { candidate = nil }
        lastSample = time
        guard faceCount > 0 else { candidate = nil; return covered }
        let target = faceCount > 1
        guard target != covered else { candidate = nil; return covered }
        if candidate != target { candidate = target; candidateSince = time }
        if time - candidateSince >= (target ? 0.35 : 1.5) {
            covered = target
            candidate = nil
        }
        return covered
    }
}

public enum PrivacyProfile: String, CaseIterable, Identifiable {
    case home, office, publicSpace, focus
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .home: return "Home"
        case .office: return "Office"
        case .publicSpace: return "Public"
        case .focus: return "Focus"
        }
    }
    public var settings: (comfort: Double, transition: Double, blur: Double) {
        switch self {
        case .home: return (24, 20, 24)
        case .office: return (15, 18, 28)
        case .publicSpace: return (8, 12, 45)
        case .focus: return (15, 18, 28)
        }
    }
}
