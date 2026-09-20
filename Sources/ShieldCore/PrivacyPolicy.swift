//  Created by Clinton Imaro on 20/09/2026.

import Foundation
import CoreGraphics

public enum AppProtectionMode: String, Codable, CaseIterable, Identifiable {
    case standard, stronger, pause
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .standard: return "Standard"
        case .stronger: return "Stronger"
        case .pause: return "Pause head blur"
        }
    }

    public func settings(comfort: Double, transition: Double, blur: Double) -> (comfort: Double, transition: Double, blur: Double) {
        self == .stronger ? (min(comfort, 8), min(transition, 12), max(blur, 45)) : (comfort, transition, blur)
    }
}

public struct AppPrivacyRule: Codable, Equatable, Identifiable {
    public let bundleID: String
    public var name: String
    public var mode: AppProtectionMode
    public var id: String { bundleID }

    public init(bundleID: String, name: String, mode: AppProtectionMode = .standard) {
        self.bundleID = bundleID
        self.name = name
        self.mode = mode
    }
}

public struct AdaptiveCalibration {
    private var angles: [Double] = []
    private var rejected = 0
    public init() {}

    public mutating func record(angle: Double) {
        guard angles.count + rejected < 1200 else { return }
        guard angle.isFinite, angle >= 0, angle <= 25 else { rejected += 1; return }
        angles.append(angle)
    }

    public var recommendation: Double? {
        guard angles.count >= 60, Double(rejected) / Double(angles.count + rejected) < 0.15 else { return nil }
        let sorted = angles.sorted()
        let percentile = sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * 0.95))]
        return min(25, max(6, ceil(percentile + 3)))
    }
}

public enum ScreenRegions {
    public static func subtract(_ cut: CGRect, from rectangle: CGRect) -> [CGRect] {
        let intersection = rectangle.intersection(cut)
        guard !intersection.isNull, !intersection.isEmpty else { return [rectangle] }
        return [
            CGRect(x: rectangle.minX, y: rectangle.minY, width: rectangle.width, height: intersection.minY - rectangle.minY),
            CGRect(x: rectangle.minX, y: intersection.maxY, width: rectangle.width, height: rectangle.maxY - intersection.maxY),
            CGRect(x: rectangle.minX, y: intersection.minY, width: intersection.minX - rectangle.minX, height: intersection.height),
            CGRect(x: intersection.maxX, y: intersection.minY, width: rectangle.maxX - intersection.maxX, height: intersection.height)
        ].filter { $0.width > 0 && $0.height > 0 }
    }

    public static func visible(_ rectangle: CGRect, behind occluders: [CGRect]) -> [CGRect] {
        occluders.reduce([rectangle]) { regions, occluder in regions.flatMap { subtract(occluder, from: $0) } }
    }

    public static func fromVision(_ normalized: CGRect, in screen: CGRect) -> CGRect {
        CGRect(x: screen.minX + normalized.minX * screen.width, y: screen.minY + normalized.minY * screen.height,
               width: normalized.width * screen.width, height: normalized.height * screen.height).intersection(screen)
    }
}
