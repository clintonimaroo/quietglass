import Foundation

/// Serializes production camera ownership. Frames/embeddings are never persisted.
final class SharedFaceCamera: NearbyCameraSession {
    private let id = UUID()
    private let hub: FaceCameraHub
    private let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    private var recognition = false
    private var deviceID = ""
    init(hub: FaceCameraHub = .shared, completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) {
        self.hub = hub; self.completion = completion
    }
    func configureRecognition(_ enabled: Bool) { recognition = enabled }
    func configureDevice(_ id: String?) { deviceID = id ?? "" }
    func start() { hub.add(id, device: deviceID, recognition: recognition, completion: completion) }
    func stop() { hub.remove(id) }
    deinit { hub.remove(id) }
}

final class FaceCameraHub {
    static let shared = FaceCameraHub()
    private struct Client {
        let recognition: Bool
        let completion: (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void
    }
    private let queue = DispatchQueue(label: "local.clinton.QuietGlass.camera-sharing")
    private var clients: [UUID: Client] = [:]
    private var camera: NearbyCameraSession?
    private var device = ""
    private var generation = 0
    private let makeCamera: (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession
    init(makeCamera: @escaping (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession = { FaceCamera(completion: $0) }) {
        self.makeCamera = makeCamera
    }
    func add(_ id: UUID, device: String, recognition: Bool, completion: @escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) {
        queue.async { [self] in
            guard clients.isEmpty || self.device == device else { completion(.failure(.configuration)); return }
            clients[id] = Client(recognition: recognition, completion: completion)
            if camera == nil {
                self.device = device; generation += 1
                let token = generation
                let camera = makeCamera { [weak self] result in
                    guard let self else { return }
                    self.queue.async {
                        guard token == self.generation else { return }
                        for client in self.clients.values { client.completion(result) }
                    }
                }
                self.camera = camera
                camera.configureDevice(device)
                camera.configureRecognition(clients.values.contains(where: \.recognition))
                camera.start()
            } else { camera?.configureRecognition(clients.values.contains(where: \.recognition)) }
        }
    }
    func remove(_ id: UUID) {
        queue.async { [self] in
            guard clients.removeValue(forKey: id) != nil else { return }
            if clients.isEmpty { generation += 1; camera?.stop(); camera = nil }
            else { camera?.configureRecognition(clients.values.contains(where: \.recognition)) }
        }
    }
    func flush() async { await withCheckedContinuation { continuation in queue.async { continuation.resume() } } }
}
