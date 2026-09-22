import AVFoundation
import SwiftUI

@MainActor
final class ProtectionCheck: ObservableObject {
    @Published private(set) var session: AVCaptureSession?
    @Published private(set) var running = false
    @Published private(set) var message = "Face the camera, then ask someone to enter from either side."
    @Published private(set) var faces: [CGRect] = []
    @Published private(set) var sawCenter = false
    @Published private(set) var sawLeft = false
    @Published private(set) var sawRight = false
    @Published private(set) var demoSeconds: Int?
    @Published private(set) var demoBlurred = false
    @Published private(set) var demonstrated = false
    var onBegin: (() -> Void)?
    var onEnd: (() -> Void)?
    var onDemoCoverage: ((Bool) -> Void)?
    var demoAvailable: (() -> Bool)?
    private let access: () async -> Bool
    private let makeCamera: (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession
    private let clock: () -> TimeInterval
    private var camera: NearbyCameraSession?
    private var generation = 0
    private var lastFrame: TimeInterval = 0
    private var timer: Timer?
    private var demoStart: TimeInterval?
    private var demoResponse = NearbyResponse.warning
    private var began = false

    init(access: @escaping () async -> Bool = NearbyPeople.requestCameraAccess,
         makeCamera: @escaping (@escaping (Result<NearbyFaceSample, NearbyCameraFailure>) -> Void) -> NearbyCameraSession = { FaceCamera(completion: $0) },
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.access = access; self.makeCamera = makeCamera; self.clock = clock
    }

    private func begin() {
        if !began { began = true; onBegin?() }
        if timer == nil {
            let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            self.timer = timer; RunLoop.main.add(timer, forMode: .common)
        }
    }

    func startCamera(id: String) {
        guard !running else { return }
        begin(); generation += 1
        let token = generation
        running = true; message = "Starting camera…"; lastFrame = clock()
        Task { [weak self] in
            guard let self else { return }
            let allowed = await access()
            guard generation == token, running else { return }
            guard allowed else { fail(.permission); return }
            let camera = makeCamera { [weak self] result in
                Task { @MainActor in
                    guard let self, self.generation == token, self.running else { return }
                    switch result {
                    case .success(let sample): self.receive(sample)
                    case .failure(let failure): self.fail(failure)
                    }
                }
            }
            self.camera = camera; session = camera.previewSession
            camera.configureDevice(id); camera.start()
        }
    }

    private func receive(_ sample: NearbyFaceSample) {
        guard sample.count >= 0, sample.capturedAt.isFinite, sample.capturedAt >= lastFrame,
              sample.capturedAt <= clock(), clock() - sample.capturedAt <= 1 else { return }
        lastFrame = sample.capturedAt
        faces = sample.bounds.filter { !$0.isEmpty && $0.minX >= 0 && $0.minY >= 0 && $0.maxX <= 1 && $0.maxY <= 1 }
        message = sample.count == 0 ? "No faces in view" : sample.count == 1 ? "One face in view" : "\(sample.count) faces in view"
        if sample.count == 1, let face = faces.first, (0.33...0.67).contains(face.midX) { sawCenter = true }
        if sawCenter, faces.count > 1 {
            // The maker stays in the center while the second person enters each edge.
            // Preview is mirrored, so camera-right appears on the preview's left.
            if faces.contains(where: { $0.midX > 0.67 }) { sawLeft = true }
            if faces.contains(where: { $0.midX < 0.33 }) { sawRight = true }
        }
    }

    private func fail(_ failure: NearbyCameraFailure) {
        generation += 1; camera?.stop(); camera = nil; session = nil
        running = false; faces = []; message = failure.title + ". Check the camera and try again."
    }

    func demonstrate(_ response: NearbyResponse) {
        begin(); stopDemonstration()
        demoResponse = response; demoStart = clock(); tick()
    }

    func tick() {
        if running, camera != nil, clock() - lastFrame > 4 { fail(.stalled) }
        guard let start = demoStart else { return }
        let warning = demoResponse == .warning ? 3.0 : 0
        let elapsed = clock() - start
        if elapsed >= warning + 3 {
            let succeeded = demoAvailable?() ?? true
            stopDemonstration(); demonstrated = succeeded
            if !succeeded { message = "Blur could not start. Check Screen Recording access and try again." }
            return
        }
        if elapsed < warning { demoSeconds = max(1, Int(ceil(warning - elapsed))) }
        else if !demoBlurred { demoSeconds = nil; demoBlurred = true; onDemoCoverage?(true) }
    }

    func stopDemonstration() {
        demoStart = nil; demoSeconds = nil; demoBlurred = false; onDemoCoverage?(false)
    }

    func close() {
        generation += 1; camera?.stop(); camera = nil; session = nil; running = false
        timer?.invalidate(); timer = nil; stopDemonstration(); faces = []
        sawCenter = false; sawLeft = false; sawRight = false; demonstrated = false
        message = "Face the camera, then ask someone to enter from either side."
        if began { began = false; onEnd?() }
    }
}

struct ProtectionCheckView: View {
    @ObservedObject var check: ProtectionCheck
    let cameraID: String
    let response: NearbyResponse
    let canBlur: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingDetails = false
    @State private var previewAspectRatio: CGFloat = 16.0 / 9.0
    private let accent = Color(red: 0.94, green: 0.68, blue: 0.91)
    private let secondary = Color(white: 0.58)

    private var demonstrating: Bool { check.demoSeconds != nil || check.demoBlurred }
    private var coverageInstruction: String {
        if !check.running { return "Only faces inside the camera’s view can be detected." }
        if !check.sawCenter { return "First, face the camera on your own." }
        if !check.sawLeft { return "Stay centered. Ask someone to enter from the left." }
        if !check.sawRight { return "Now ask them to enter from the right." }
        return "Both sides detected. People outside this view cannot be seen."
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            VStack(spacing: 12) {
                cameraStage
                if check.running {
                    HStack(spacing: 8) {
                        result("You", number: "1", observed: check.sawCenter)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 18, height: 1).accessibilityHidden(true)
                        result("Left", number: "2", observed: check.sawLeft)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 18, height: 1).accessibilityHidden(true)
                        result("Right", number: "3", observed: check.sawRight)
                    }
                    .padding(.horizontal, 24).padding(.top, 4)
                    Text(coverageInstruction)
                        .font(.system(size: 12)).foregroundStyle(secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
            }
            Divider().opacity(0.3)
            responsePreview
            privacyDetails
        }
        .padding(24).frame(width: 440)
        .foregroundStyle(Color.white.opacity(0.9))
        .background(Color(white: 24 / 255))
        .buttonStyle(QuietGlassButtonStyle()).preferredColorScheme(.dark)
        .onDisappear { check.close() }
        .onExitCommand { dismiss() }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            Text("Test my protection").font(.system(size: 20, weight: .semibold))
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 0)
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .medium))
                    .foregroundStyle(secondary).frame(width: 24, height: 24)
                    .background(ControlAppearance.fill, in: Circle()).contentShape(Circle())
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            .accessibilityLabel("Close protection check")
        }
    }

    @ViewBuilder private var cameraStage: some View {
        if let session = check.session {
            CoverageCameraPreview(session: session, faces: check.faces, aspectRatio: $previewAspectRatio)
                .aspectRatio(previewAspectRatio, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .background(.black)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .accessibilityLabel("Live camera coverage")
                .overlay(alignment: .bottomLeading) {
                    HStack(spacing: 6) {
                        Circle().fill(check.faces.isEmpty ? secondary : accent).frame(width: 5, height: 5)
                        Text(check.message).font(.system(size: 11, weight: .medium))
                    }
                        .foregroundStyle(.white).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(.black.opacity(0.6), in: Capsule()).padding(10)
                        .allowsHitTesting(false)
                }
        } else {
            VStack(spacing: 12) {
                CoverageGuide(accent: accent).frame(width: 224, height: 132)
                    .padding(.bottom, 4).accessibilityHidden(true)
                VStack(spacing: 8) {
                    Text(check.running ? "Starting camera…" : "Check the space around you")
                        .font(.system(size: 16, weight: .medium))
                    Text(check.running ? "Your preview will appear here." : check.message)
                        .font(.system(size: 12)).foregroundStyle(secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 280)
                }
                if check.running {
                    ProgressView().controlSize(.small)
                } else {
                    Button { check.startCamera(id: cameraID) } label: {
                        Label("Start camera", systemImage: "video").frame(width: 142, height: 20)
                    }
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, 12)
        }
    }

    private func result(_ label: String, number: String, observed: Bool) -> some View {
        HStack(spacing: 8) {
            ZStack {
                Circle().fill(observed ? accent : ControlAppearance.fill)
                if observed {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(Color(white: 0.12))
                } else {
                    Text(number).font(.system(size: 10, weight: .medium)).foregroundStyle(secondary)
                }
            }
            .frame(width: 18, height: 18)
            Text(label).font(.system(size: 12, weight: .medium))
                .foregroundStyle(observed ? Color.white.opacity(0.9) : secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label).accessibilityValue(observed ? "Detected" : "Not checked")
    }

    private var responsePreview: some View {
        HStack(spacing: 12) {
            Image(systemName: check.demonstrated && !demonstrating ? "checkmark.circle" : response == .warning ? "bell" : "eye.slash")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(check.demonstrated && !demonstrating ? accent : secondary)
                .frame(width: 22).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(demonstrating ? "Preview in progress" : check.demonstrated ? "Preview complete" : response == .warning ? "Warning and blur" : "Automatic blur")
                    .font(.system(size: 13, weight: .medium))
                Text(responseDetail).font(.system(size: 11)).foregroundStyle(secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(demonstrating ? "Stop" : check.demonstrated ? "Replay" : "Try it") {
                if demonstrating { check.stopDemonstration() }
                else { check.demonstrate(response) }
            }
            .disabled(!canBlur && !demonstrating)
            .accessibilityLabel(demonstrating ? "Stop preview" : "Preview \(response == .warning ? "warning and blur" : "automatic blur")")
        }
        .padding(.vertical, 2)
    }

    private var responseDetail: String {
        if let seconds = check.demoSeconds { return "Blur starts in \(seconds) seconds." }
        if check.demoBlurred { return "Blur clears automatically after 3 seconds." }
        if !canBlur { return "Allow Screen Recording to try this." }
        if check.demonstrated { return "Your warning delay hasn’t changed." }
        return response == .warning ? "3-second warning, then 3-second blur." : "Blurs for 3 seconds, then clears."
    }

    private var privacyDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("On your Mac. No images saved.", systemImage: "lock")
                    .font(.system(size: 11)).foregroundStyle(secondary)
                Spacer(minLength: 8)
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showingDetails.toggle() }
                } label: {
                    HStack(spacing: 4) {
                        Text("Details")
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
                            .rotationEffect(.degrees(showingDetails ? 180 : 0))
                    }
                    .font(.system(size: 11)).foregroundStyle(secondary)
                    .padding(.vertical, 3).contentShape(Rectangle())
                }
                .buttonStyle(.plain).accessibilityLabel("About this check")
                .accessibilityValue(showingDetails ? "Expanded" : "Collapsed")
            }
            if showingDetails {
                Text("Only people inside the camera’s view can be detected. Nearby monitoring pauses during a test and resumes when you close this check. Your saved warning delay stays unchanged. This checks coverage, not your identity.")
                    .font(.system(size: 11)).foregroundStyle(secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct CoverageGuide: View {
    let accent: Color
    var body: some View {
        VStack(spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(white: 0.115))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                Circle().fill(accent.opacity(0.75))
                    .frame(width: 3, height: 3).offset(y: -46)
                HStack(spacing: 22) {
                    Image(systemName: "person").font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.32))
                    ZStack {
                        RoundedRectangle(cornerRadius: 15).fill(accent.opacity(0.045))
                        FaceOutline().stroke(accent, style: StrokeStyle(lineWidth: 1.1, lineCap: .round, lineJoin: .round))
                            .frame(width: 31, height: 38)
                        CoverageCorners().stroke(accent.opacity(0.7), style: StrokeStyle(lineWidth: 1, lineCap: .round))
                    }
                    .frame(width: 55, height: 64)
                    Image(systemName: "person").font(.system(size: 24, weight: .ultraLight))
                        .foregroundStyle(.white.opacity(0.32))
                }
                .offset(y: 4)
            }
            .frame(width: 202, height: 112)
            Capsule().fill(.white.opacity(0.18)).frame(height: 2)
        }
    }
}

private struct CoverageCorners: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 17, radius: CGFloat = 9
        for (x, y, dx, dy) in [(rect.minX, rect.minY, 1.0, 1.0), (rect.maxX, rect.minY, -1.0, 1.0),
                               (rect.minX, rect.maxY, 1.0, -1.0), (rect.maxX, rect.maxY, -1.0, -1.0)] {
            path.move(to: CGPoint(x: x, y: y + dy * length))
            path.addLine(to: CGPoint(x: x, y: y + dy * radius))
            path.addQuadCurve(to: CGPoint(x: x + dx * radius, y: y), control: CGPoint(x: x, y: y))
            path.addLine(to: CGPoint(x: x + dx * length, y: y))
        }
        return path
    }
}

private struct CoverageCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    let faces: [CGRect]
    @Binding var aspectRatio: CGFloat
    func makeNSView(context: Context) -> CoveragePreview { CoveragePreview(session: session) }
    func updateNSView(_ view: CoveragePreview, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
        view.onAspectRatio = { aspectRatio = $0 }
        view.faces = faces; view.needsLayout = true
    }
    static func dismantleNSView(_ view: CoveragePreview, coordinator: ()) {
        view.onAspectRatio = nil
        view.preview.session = nil
    }
}

private final class CoveragePreview: NSView {
    let preview: AVCaptureVideoPreviewLayer
    let boxes = CAShapeLayer()
    var faces: [CGRect] = []
    var onAspectRatio: ((CGFloat) -> Void)?
    private var reportedAspectRatio: CGFloat = 0
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero); wantsLayer = true
        preview.videoGravity = .resizeAspect
        layer?.masksToBounds = true
        layer?.addSublayer(preview); layer?.addSublayer(boxes)
        boxes.fillColor = nil
        boxes.strokeColor = NSColor(calibratedRed: 0.94, green: 0.68, blue: 0.91, alpha: 0.9).cgColor
        boxes.lineWidth = 1.5
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout(); CATransaction.begin(); CATransaction.setDisableActions(true)
        preview.frame = bounds; boxes.frame = bounds
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false; connection.isVideoMirrored = true
        }
        // Match the actual preview image, including the camera's clean aperture,
        // instead of cropping the edges that this coverage check is testing.
        let videoRect = preview.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        let ratio = videoRect.width / videoRect.height
        if ratio.isFinite, ratio > 0, abs(ratio - reportedAspectRatio) > 0.001 {
            reportedAspectRatio = ratio
            DispatchQueue.main.async { [weak self] in self?.onAspectRatio?(ratio) }
        }
        let path = CGMutablePath()
        for face in faces {
            let metadata = CGRect(x: face.minX, y: 1 - face.maxY, width: face.width, height: face.height)
            path.addRoundedRect(in: preview.layerRectConverted(fromMetadataOutputRect: metadata), cornerWidth: 8, cornerHeight: 8)
        }
        boxes.path = path; CATransaction.commit()
    }
}
