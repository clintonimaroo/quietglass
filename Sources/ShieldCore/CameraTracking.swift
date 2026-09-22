import Foundation

/// Camera-normalized bounds and head angles in radians. No identity or image data.
public struct CameraFace: Equatable {
    public let bounds: CGRect
    public let yaw: Double?
    public let pitch: Double?
    public init(bounds: CGRect, yaw: Double?, pitch: Double?) {
        self.bounds = bounds; self.yaw = yaw; self.pitch = pitch
    }
    public var valid: Bool {
        !bounds.isEmpty && !bounds.isNull && [bounds.minX, bounds.minY, bounds.width, bounds.height].allSatisfy(\.isFinite) &&
        bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= 1.01 && bounds.maxY <= 1.01
    }
    public var hasPose: Bool {
        guard let yaw, let pitch else { return false }
        return yaw.isFinite && pitch.isFinite && abs(yaw) <= .pi / 2 && abs(pitch) <= .pi / 2
    }
}

/// Geometry tracks expire quickly and never constitute identity verification.
public struct FaceTracks {
    private struct Track { var bounds: CGRect; var seen: TimeInterval }
    private var tracks: [Int: Track] = [:]
    private var nextID = 0
    public init() {}
    public mutating func update(_ faces: [CameraFace], at time: TimeInterval) -> [Int] {
        tracks = tracks.filter { time - $0.value.seen <= 0.65 }
        var ids = Array(repeating: -1, count: faces.count)
        var candidates: [(Double, Int, Int)] = []
        for (index, face) in faces.enumerated() where face.valid {
            for (id, track) in tracks {
                let intersection = face.bounds.intersection(track.bounds)
                let area = intersection.isNull ? 0 : intersection.width * intersection.height
                let union = face.bounds.width * face.bounds.height + track.bounds.width * track.bounds.height - area
                let overlap = union > 0 ? area / union : 0
                if overlap >= 0.25 { candidates.append((overlap, index, id)) }
            }
        }
        var used = Set<Int>()
        for (_, index, id) in candidates.sorted(by: { $0.0 > $1.0 }) where ids[index] == -1 && !used.contains(id) {
            ids[index] = id; used.insert(id)
        }
        for (index, face) in faces.enumerated() where face.valid {
            if ids[index] == -1 { ids[index] = nextID; nextID += 1 }
            tracks[ids[index]] = Track(bounds: face.bounds, seen: time)
        }
        return ids
    }
}

public struct NearbyAttentionPolicy {
    private var tracks = FaceTracks()
    private var primaryID: Int?
    private var candidates: [Int: TimeInterval] = [:]
    private var lastTime: TimeInterval?
    public init() {}

    /// A forward-facing extra face must persist. Unknown pose uses a longer,
    /// conservative dwell rather than silently assuming the person is harmless.
    public mutating func observe(_ faces: [CameraFace], ownerIndex: Int? = nil, at time: TimeInterval) -> Bool {
        guard time.isFinite, lastTime.map({ time > $0 }) ?? true else { return false }
        if let lastTime, time - lastTime > 0.6 { candidates = [:]; tracks = FaceTracks(); primaryID = nil }
        lastTime = time
        let ids = tracks.update(faces, at: time)
        if let ownerIndex, ids.indices.contains(ownerIndex) { primaryID = ids[ownerIndex] }
        else if faces.count == 1, let id = ids.first, id >= 0 { primaryID = id }
        else if primaryID == nil {
            // Without recognition, a clearly dominant central face is only a
            // working-person heuristic. Ambiguous crowds stay conservative.
            let ranked = faces.indices.filter { faces[$0].valid }.sorted {
                faces[$0].bounds.width * faces[$0].bounds.height > faces[$1].bounds.width * faces[$1].bounds.height
            }
            if ranked.count >= 2 {
                let first = faces[ranked[0]].bounds, second = faces[ranked[1]].bounds
                if (0.2...0.8).contains(first.midX), first.width * first.height >= second.width * second.height * 1.5 {
                    primaryID = ids[ranked[0]]
                }
            }
        }
        var next: [Int: TimeInterval] = [:]
        var attention = false
        for (index, face) in faces.enumerated() where face.valid && ids[index] >= 0 && ids[index] != primaryID {
            let known = face.hasPose
            let facing = !known || (abs(face.yaw!) <= 0.61 && abs(face.pitch!) <= 0.52)
            guard facing else { continue }
            let id = ids[index], start = candidates[id] ?? time
            next[id] = start
            if time - start >= (known ? 0.7 : 1.2) { attention = true }
        }
        candidates = next
        return attention
    }
}

public struct CameraHeadPolicy {
    public private(set) var calibrated = false
    public private(set) var calibrating = true
    public private(set) var progress = 0.0
    public private(set) var coverage = 0.0
    public private(set) var offset = HeadOffset(yaw: 0, pitch: 0)
    public private(set) var hasFace = false
    private var tracks = FaceTracks()
    private var primaryID: Int?
    private var primaryBounds: CGRect?
    private var center: (yaw: Double, pitch: Double)?
    private var calibrationStart: TimeInterval?
    private var calibrationSamples: [(Double, Double)] = []
    private var lastFrame: TimeInterval?
    private var lastPose: TimeInterval?
    private var awaySince: TimeInterval?
    private var returnSince: TimeInterval?
    public init() {}

    public mutating func beginCalibration(keepCovered: Bool = false) {
        self = CameraHeadPolicy()
        coverage = keepCovered ? 1 : 0
    }
    public mutating func observe(_ faces: [CameraFace], at time: TimeInterval, comfort: Double, transition: Double) {
        guard time.isFinite, lastFrame.map({ time > $0 }) ?? true else { return }
        if let lastFrame, time - lastFrame > 0.4 {
            calibrationStart = nil; calibrationSamples = []; progress = 0
            awaySince = nil; returnSince = nil
        }
        lastFrame = time
        let ids = tracks.update(faces, at: time)
        let index: Int?
        if calibrating { index = faces.count == 1 ? 0 : nil }
        else if let primaryID, let tracked = ids.firstIndex(of: primaryID) { index = tracked }
        else {
            // Reacquire only a single centered face. With owner recognition
            // enabled, its independent protection still requires verification.
            if faces.count == 1 && (0.2...0.8).contains(faces[0].bounds.midX) { index = 0 }
            else if let primaryBounds {
                let candidates = faces.indices.filter {
                    let overlap = faces[$0].bounds.intersection(primaryBounds)
                    guard !overlap.isNull else { return false }
                    return overlap.width * overlap.height / (primaryBounds.width * primaryBounds.height) >= 0.6
                }
                index = candidates.count == 1 ? candidates.first : nil
            } else { index = nil }
        }
        guard let index, faces[index].valid, faces[index].hasPose else {
            hasFace = false; calibrationStart = nil; calibrationSamples = []; progress = 0
            awaySince = nil; returnSince = nil
            tick(at: time); return
        }
        let face = faces[index], yaw = face.yaw!, pitch = face.pitch!
        if calibrating, let primaryID, primaryID != ids[index] {
            calibrationStart = nil; calibrationSamples = []; progress = 0
        }
        primaryID = ids[index]; primaryBounds = face.bounds; hasFace = true; lastPose = time
        if calibrating {
            guard abs(yaw) < 0.45, abs(pitch) < 0.45 else { calibrationStart = nil; calibrationSamples = []; progress = 0; return }
            if let first = calibrationSamples.first, abs(yaw - first.0) > 0.07 || abs(pitch - first.1) > 0.07 {
                calibrationStart = nil; calibrationSamples = []
            }
            if calibrationStart == nil { calibrationStart = time }
            calibrationSamples.append((yaw, pitch))
            progress = min(1, (time - calibrationStart!) / 1.2)
            guard progress >= 1, calibrationSamples.count >= 8 else { return }
            let count = Double(calibrationSamples.count)
            center = (calibrationSamples.map(\.0).reduce(0,+) / count, calibrationSamples.map(\.1).reduce(0,+) / count)
            calibrated = true; calibrating = false; coverage = 0
            calibrationSamples = []; return
        }
        guard let center else { return }
        let raw = HeadOffset(yaw: (yaw - center.yaw) * 180 / .pi, pitch: (pitch - center.pitch) * 180 / .pi)
        offset = HeadOffset(yaw: offset.yaw * 0.4 + raw.yaw * 0.6, pitch: offset.pitch * 0.4 + raw.pitch * 0.6)
        let threshold = max(2, min(30, comfort))
        if offset.angle > threshold {
            returnSince = nil
            if awaySince == nil { awaySince = time }
            if time - awaySince! >= 0.3 {
                coverage = max(0.01, min(1, (offset.angle - threshold) / max(5, min(30, transition))))
            }
        } else if offset.angle < max(1, threshold - 3) {
            awaySince = nil
            if returnSince == nil { returnSince = time }
            if time - returnSince! >= 0.4 { coverage = 0 }
        } else { awaySince = nil; returnSince = nil }
    }
    public mutating func tick(at time: TimeInterval) {
        guard time.isFinite else { return }
        if let lastPose, time - lastPose >= 0.65 {
            hasFace = false
            if calibrated { coverage = 1 }
        }
    }
    public mutating func fail() {
        hasFace = false
        if calibrated { coverage = 1 }
    }
}
