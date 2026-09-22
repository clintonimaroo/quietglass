import Foundation
import Combine
import AVFoundation
import LocalAuthentication
import Security
import ShieldCore

enum OwnerSetupError: LocalizedError {
    case authentication, cancelled, missingTemplate, invalidTemplate, keychain(OSStatus), camera, model
    var errorDescription: String? {
        switch self {
        case .authentication: return "Authenticate with Touch ID or your Mac password to continue."
        case .cancelled: return "Setup cancelled. No face data was saved."
        case .missingTemplate: return "Your saved face is unavailable. Set up owner recognition again."
        case .invalidTemplate: return "Your saved face cannot be used with this model. Set it up again."
        case .keychain: return "Keychain could not securely access your face data. Try again after unlocking your Mac."
        case .camera: return "Camera access is required for owner setup. Allow it in System Settings."
        case .model: return "The recognition model is unavailable. Reinstall QuietGlass; protection will stay on."
        }
    }
}

protocol OwnerTemplateStoring {
    var containsTemplate: Bool { get }
    func read(context: LAContext) throws -> OwnerTemplate
    func write(_ template: OwnerTemplate, context: LAContext) throws
    func delete(context: LAContext) throws
}

struct OwnerTemplateStore: OwnerTemplateStoring {
    // QuietGlass local builds have no Apple provisioning profile. The Data
    // Protection keychain requires provisioned access-group entitlements, so
    // use the encrypted macOS login keychain with an explicit app ACL. Local
    // Authentication is enforced by OwnerRecognition before every operation.
    // Do not claim Secure Enclave storage or hardware-bound user presence.
    var keychain: SecKeychain? = nil
    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "local.clinton.QuietGlass.owner",
         kSecAttrAccount as String: "sface-template-v1",
         kSecUseDataProtectionKeychain as String: false]
    }
    private func scopedQuery() throws -> [String: Any] {
        var selected = keychain
        if selected == nil {
            let status = SecKeychainCopyDefault(&selected)
            guard status == errSecSuccess else { throw OwnerSetupError.keychain(status) }
        }
        guard let selected else { throw OwnerSetupError.missingTemplate }
        var q = query
        q[kSecMatchSearchList as String] = [selected]
        return q
    }
    var containsTemplate: Bool {
        guard var q = try? scopedQuery() else { return false }
        q[kSecReturnAttributes as String] = true
        let context = LAContext()
        context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        defer { context.invalidate() }
        let status = SecItemCopyMatching(q as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed || status == errSecAuthFailed
    }
    func read(context: LAContext) throws -> OwnerTemplate {
        var q = try scopedQuery()
        q[kSecReturnData as String] = true
        q[kSecUseAuthenticationContext as String] = context
        var result: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &result)
        guard status != errSecItemNotFound else { throw OwnerSetupError.missingTemplate }
        guard status == errSecSuccess, var data = result as? Data else { throw OwnerSetupError.keychain(status) }
        defer { data.resetBytes(in: 0..<data.count) }
        guard data.count < 16_384, let template = try? JSONDecoder().decode(OwnerTemplate.self, from: data), template.isValid else {
            throw OwnerSetupError.invalidTemplate
        }
        return template
    }
    func write(_ template: OwnerTemplate, context: LAContext) throws {
        guard template.isValid else { throw OwnerSetupError.invalidTemplate }
        var data = try JSONEncoder().encode(template)
        defer { data.resetBytes(in: 0..<data.count) }
        var q = try scopedQuery()
        q[kSecUseAuthenticationContext as String] = context
        // Update in place: a failed replacement must not delete the existing face.
        let update = SecItemUpdate(q as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw OwnerSetupError.keychain(update) }
        var trusted: SecTrustedApplication?
        var access: SecAccess?
        let trustedStatus = SecTrustedApplicationCreateFromPath(nil, &trusted)
        guard trustedStatus == errSecSuccess, let trusted else { throw OwnerSetupError.keychain(trustedStatus) }
        let accessStatus = SecAccessCreate("QuietGlass owner face" as CFString, [trusted] as CFArray, &access)
        guard accessStatus == errSecSuccess, let access else { throw OwnerSetupError.keychain(accessStatus) }
        q[kSecAttrAccess as String] = access
        q[kSecUseKeychain as String] = (q.removeValue(forKey: kSecMatchSearchList as String) as? [SecKeychain])?.first
        q.removeValue(forKey: kSecUseAuthenticationContext as String)
        q[kSecValueData as String] = data
        q[kSecAttrLabel as String] = "QuietGlass owner face"
        let status = SecItemAdd(q as CFDictionary, nil)
        guard status == errSecSuccess else { throw OwnerSetupError.keychain(status) }
    }
    func delete(context: LAContext) throws {
        var q = try scopedQuery()
        q[kSecUseAuthenticationContext as String] = context
        let status = SecItemDelete(q as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw OwnerSetupError.keychain(status) }
    }
}

@MainActor
final class OwnerRecognition: ObservableObject {
    @Published private(set) var enabled: Bool
    @Published private(set) var enrolled: Bool
    @Published private(set) var busy = false
    @Published private(set) var enrolling = false
    @Published private(set) var readyToSave = false
    @Published private(set) var enrollmentProgress = 0.0
    @Published private(set) var previewSession: AVCaptureSession?
    @Published private(set) var prompt = "Set up your face"
    @Published private(set) var error: String?
    private(set) var template: OwnerTemplate?
    private let preferences: UserDefaults
    private let store: OwnerTemplateStoring
    private let authenticate: (String) async throws -> LAContext
    private let cameraAccess: () async -> Bool
    private let makeCamera: (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession
    private var context: LAContext?
    private var camera: NearbyCameraSession?
    private var enrollment = OwnerEnrollment(turnPositive: Bool.random())
    private var token = 0
    private var watchdog: Timer?
    private var lastFrame: TimeInterval = 0
    private let clock: () -> TimeInterval
    private var lastAccepted: TimeInterval = 0
    private var saving = false

    init(preferences: UserDefaults = .standard, store: OwnerTemplateStoring = OwnerTemplateStore(),
         authenticate: @escaping (String) async throws -> LAContext = OwnerRecognition.authenticateUser,
         cameraAccess: @escaping () async -> Bool = NearbyPeople.requestCameraAccess,
         makeCamera: @escaping (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession = { FaceCamera(recognition: true, completion: $0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.preferences = preferences; self.store = store; self.authenticate = authenticate
        self.cameraAccess = cameraAccess; self.makeCamera = makeCamera; self.clock = clock
        enrolled = store.containsTemplate
        // Do not silently fall back to count-only when a saved template disappears.
        enabled = preferences.bool(forKey: "ownerRecognitionEnabled")
    }

    nonisolated static func authenticateUser(_ reason: String) async throws -> LAContext {
        let context = LAContext()
        context.touchIDAuthenticationAllowableReuseDuration = 0
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { throw OwnerSetupError.authentication }
        guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) else { throw OwnerSetupError.authentication }
        return context
    }

    func setEnabled(_ value: Bool) {
        guard !busy, !enrolling, !value || enrolled else { return }
        enabled = value
        preferences.set(value, forKey: "ownerRecognitionEnabled")
        template = nil
    }

    func prepareForMonitoring() async throws {
        guard enabled else { return }
        token += 1
        let current = token
        error = nil
        do {
            let context = try await authenticate("Use your saved face for this QuietGlass session.")
            defer { context.invalidate() }
            guard current == token else { throw OwnerSetupError.cancelled }
            let store = self.store
            let loaded = try await Task.detached { try store.read(context: context) }.value
            guard current == token else { throw OwnerSetupError.cancelled }
            guard loaded.isValid else { throw OwnerSetupError.invalidTemplate }
            template = loaded
        } catch {
            if current == token { self.error = error.localizedDescription }
            throw error
        }
    }

    func endMonitoring() {
        if saving { template = nil; return }
        token += 1
        template = nil
        if enrolling || busy { cancelEnrollment() }
    }

    func beginEnrollment() {
        guard !busy, !enrolling else { return }
        token += 1
        let current = token
        error = nil; busy = true; readyToSave = false
        enrollmentProgress = 0
        prompt = "Authenticate to set up your face"
        enrollment = OwnerEnrollment(turnPositive: Bool.random())
        Task {
            do {
                let context = try await authenticate("Set up the face that can clear QuietGlass protection.")
                guard current == token else { context.invalidate(); return }
                self.context = context
                guard await cameraAccess() else { throw OwnerSetupError.camera }
                guard current == token else { return }
                busy = false; enrolling = true; lastFrame = clock(); lastAccepted = 0
                prompt = enrollment.prompt
                let camera = makeCamera { [weak self] result in
                    Task { @MainActor in
                        guard let self, self.token == current, self.enrolling else { return }
                        switch result {
                        case .failure(let failure): self.failEnrollment(failure.title)
                        case .success(let sample): self.receiveEnrollment(sample)
                        }
                    }
                }
                self.camera = camera
                camera.configureDevice(preferences.string(forKey: CameraSelection.preferenceKey))
                previewSession = camera.previewSession
                camera.start()
                let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.enrolling, self.clock() - self.lastFrame > 4 else { return }
                        self.failEnrollment("Camera stopped responding. Try setup again.")
                    }
                }
                watchdog = timer; RunLoop.main.add(timer, forMode: .common)
            } catch {
                guard current == token else { return }
                failEnrollment(error.localizedDescription)
            }
        }
    }

    private func receiveEnrollment(_ sample: NearbyFaceSample) {
        guard !readyToSave else { return }
        let now = clock()
        guard sample.capturedAt.isFinite, sample.capturedAt > lastAccepted,
              sample.capturedAt <= now, now - sample.capturedAt <= 1 else { return }
        lastFrame = now; lastAccepted = sample.capturedAt
        enrollment.observe(vector: sample.vector, pose: sample.pose, faceCount: sample.count, at: sample.capturedAt)
        if enrollmentProgress != enrollment.progress { enrollmentProgress = enrollment.progress }
        let next = sample.count != 1 ? "Only your face should be in view" : sample.vector == nil ? "Face the camera in good light" : enrollment.prompt
        if prompt != next { prompt = next }
        if enrollment.template != nil {
            readyToSave = true
            previewSession = nil
            camera?.stop(); camera = nil
            watchdog?.invalidate(); watchdog = nil
            prompt = "Your face is ready to save"
        }
    }

    func saveEnrollment() {
        guard readyToSave, !busy, let template = enrollment.template, let context else { return }
        busy = true
        saving = true
        let current = token
        let store = self.store
        Task {
            do {
                try await Task.detached { try store.write(template, context: context) }.value
                saving = false
                guard current == token else { return }
                enrolled = true
                enabled = true
                preferences.set(true, forKey: "ownerRecognitionEnabled")
                cancelEnrollment()
                prompt = "Your face is saved securely"
            } catch {
                saving = false
                guard current == token else { return }
                failEnrollment(error.localizedDescription)
            }
        }
    }

    func deleteEnrollment() {
        guard !busy, !enrolling else { return }
        token += 1
        let current = token
        busy = true; error = nil
        Task {
            do {
                let context = try await authenticate("Delete your saved QuietGlass face.")
                defer { context.invalidate() }
                guard current == token else { return }
                let store = self.store
                try await Task.detached { try store.delete(context: context) }.value
                guard current == token else { return }
                enabled = false; enrolled = false; template = nil; busy = false
                preferences.set(false, forKey: "ownerRecognitionEnabled")
            } catch {
                guard current == token else { return }
                busy = false; self.error = error.localizedDescription
            }
        }
    }

    func cancelEnrollment() {
        guard !saving else { return } // A confirmed Keychain commit is atomic.
        token += 1
        camera?.stop(); camera = nil
        previewSession = nil
        watchdog?.invalidate(); watchdog = nil
        context?.invalidate(); context = nil
        enrollment.reset()
        enrollmentProgress = 0
        enrolling = false; readyToSave = false; busy = false
    }

    private func failEnrollment(_ message: String) {
        cancelEnrollment()
        error = message
        prompt = "Try setup again"
    }
}
