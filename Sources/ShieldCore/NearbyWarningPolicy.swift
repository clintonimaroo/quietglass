import Foundation

/// An unresolved warning escalates once. Editing its duration cannot uncover
/// an already blurred screen; the warning must resolve or be explicitly stopped.
public struct NearbyWarningPolicy {
    public static let defaultDelay: TimeInterval = 120
    public static let maximumDelay: TimeInterval = 24 * 60 * 60
    public private(set) var secondsRemaining: Int?
    public private(set) var escalated = false
    private var startedAt: TimeInterval?

    public init() {}

    public static func normalizedDelay(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return defaultDelay }
        return min(maximumDelay, max(60, (seconds / 60).rounded() * 60))
    }

    public mutating func update(active: Bool, delay: TimeInterval, at time: TimeInterval) {
        guard active else { self = Self(); return }
        guard time.isFinite else { return }
        if startedAt == nil { startedAt = time }
        if escalated { secondsRemaining = 0; return }
        let remaining = Self.normalizedDelay(delay) - max(0, time - (startedAt ?? time))
        secondsRemaining = Int(ceil(max(0, remaining)))
        if remaining <= 0 { escalated = true }
    }
}
