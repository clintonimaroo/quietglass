//  Created by Clinton Imaro on 20/09/2026.

import Foundation
import CoreGraphics
import CryptoKit

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
    public var protectWindows: Bool
    public var id: String { bundleID }

    public init(bundleID: String, name: String, mode: AppProtectionMode = .standard, protectWindows: Bool = false) {
        self.bundleID = bundleID
        self.name = name
        self.mode = mode
        self.protectWindows = protectWindows
    }

    private enum CodingKeys: String, CodingKey { case bundleID, name, mode, protectWindows }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try values.decode(String.self, forKey: .bundleID)
        name = try values.decode(String.self, forKey: .name)
        mode = try values.decode(AppProtectionMode.self, forKey: .mode)
        protectWindows = try values.decodeIfPresent(Bool.self, forKey: .protectWindows) ?? false
    }
}

public struct SavedWindowArea: Codable, Equatable, Identifiable {
    public let id: UUID
    public let bundleID: String
    public let appName: String
    public let titleDigest: String
    public let rectangle: CGRect

    public init(bundleID: String, appName: String, windowTitle: String, rectangle: CGRect) {
        id = UUID(); self.bundleID = bundleID; self.appName = appName
        titleDigest = Self.digest(windowTitle); self.rectangle = rectangle
    }
    public var isValid: Bool {
        !bundleID.isEmpty && titleDigest.count == 64 && rectangle.width > 0 && rectangle.height > 0 &&
        [rectangle.minX, rectangle.minY, rectangle.width, rectangle.height].allSatisfy(\.isFinite) &&
        CGRect(x: 0, y: 0, width: 1, height: 1).contains(rectangle)
    }
    public func matches(bundleID: String, windowTitle: String) -> Bool {
        isValid && !windowTitle.isEmpty && self.bundleID == bundleID && titleDigest == Self.digest(windowTitle)
    }
    private static func digest(_ title: String) -> String {
        SHA256.hash(data: Data(title.utf8)).map { String(format: "%02x", $0) }.joined()
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
