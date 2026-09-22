import SwiftUI
import AVFoundation

struct OwnerEnrollmentView: View {
    @ObservedObject var owner: OwnerRecognition
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        OwnerEnrollmentScreen(
            scanning: owner.enrolling && !owner.readyToSave, ready: owner.readyToSave,
            busy: owner.busy, prompt: owner.prompt, progress: owner.enrollmentProgress, error: owner.error,
            previewSession: owner.previewSession,
            cancel: { owner.cancelEnrollment(); dismiss() },
            action: { owner.readyToSave ? owner.saveEnrollment() : owner.beginEnrollment() }
        )
        .interactiveDismissDisabled(owner.busy && owner.readyToSave)
        .onChange(of: owner.prompt) { _, value in
            if value == "Your face is saved securely" { dismiss() }
        }
        .onDisappear { owner.cancelEnrollment() }
    }
}

/// Presentation stays independent of camera access, including visual previews.
struct OwnerEnrollmentScreen: View {
    let scanning: Bool
    let ready: Bool
    let busy: Bool
    let prompt: String
    let progress: Double
    let error: String?
    var previewSession: AVCaptureSession? = nil
    var cancel: () -> Void
    var action: () -> Void
    @State private var showingDetails = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.94, green: 0.68, blue: 0.91)

    private var title: String {
        if ready { return "Ready when you are" }
        if scanning { return prompt }
        if busy { return "Confirm it’s you" }
        return error == nil ? "Recognize me" : "Let’s try that again"
    }
    private var subtitle: String {
        if ready { return "Save your face to use owner recognition.\nYour camera is now off." }
        if scanning { return "A small head turn is enough. Blink naturally." }
        if busy { return "Use Touch ID or your Mac password\nto continue securely." }
        return "Set up your face so QuietGlass can check\nit’s you before clearing protection."
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: cancel) {
                    Image(systemName: "xmark").font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(width: 24, height: 24)
                        .background(ControlAppearance.fill, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel setup").disabled(busy && ready)
            }
            .padding(.top, 16).padding(.horizontal, 16)

            VStack(spacing: 0) {
                OwnerFaceGuide(progress: progress, scanning: scanning, ready: ready,
                               turn: scanning && prompt.contains("Turn") ? (prompt.contains("left") ? -1 : 1) : 0,
                               previewSession: previewSession)
                    .frame(width: scanning ? 204 : 144, height: scanning ? 204 : 144)
                    .padding(.top, 8).padding(.bottom, 24).accessibilityHidden(true)
                Text(title).font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92)).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.updatesFrequently)
                Text(subtitle).font(.system(size: 13)).foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(4).multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 10)
                if scanning {
                    HStack(spacing: 6) {
                        ForEach(0..<3) { step in
                            Capsule().fill(Double(step) / 3 < progress ? accent : Color.white.opacity(0.10))
                                .frame(width: 42, height: 3)
                        }
                    }
                    .padding(.top, 22).accessibilityElement(children: .ignore)
                    .accessibilityLabel("Face setup progress").accessibilityValue("\(Int(progress * 100)) percent")
                }
                if let error {
                    Text(error).font(.system(size: 12)).foregroundStyle(.orange).multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true).padding(.top, 16)
                }
                VStack(spacing: 8) {
                    Label("Processed privately on your Mac", systemImage: "lock")
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.50))
                    Button {
                        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) { showingDetails.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("Privacy & limitations")
                            Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
                                .rotationEffect(.degrees(showingDetails ? 180 : 0))
                        }
                        .font(.system(size: 11)).foregroundStyle(.white.opacity(0.50))
                        .padding(.vertical, 3).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).accessibilityValue(showingDetails ? "Expanded" : "Collapsed")
                    if showingDetails {
                        Text("No photos or video are saved. Your face template is encrypted in Keychain and can be deleted in Settings. Recognition can make mistakes or be fooled by a photo or video. Lock your Mac when you leave it.")
                            .font(.system(size: 11)).lineSpacing(3).foregroundStyle(.white.opacity(0.52))
                            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 3)
                    }
                }
                .padding(.top, 26).padding(.bottom, 22)
                if scanning {
                    Text("Follow the prompt to continue").font(.system(size: 12)).foregroundStyle(.white.opacity(0.50))
                        .frame(maxWidth: .infinity, minHeight: 36)
                } else {
                    Button(action: action) {
                        HStack(spacing: 8) {
                            if busy { ProgressView().controlSize(.mini).tint(.white) }
                            Text(busy ? (ready ? "Saving…" : "Waiting for confirmation…") : (ready ? "Save my face" : "Get started"))
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(Color.white.opacity(0.88)).frame(maxWidth: .infinity, minHeight: 36)
                        .background(ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 9))
                        .opacity(busy ? 0.6 : 1)
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain).disabled(busy).keyboardShortcut(.defaultAction)
                }
                Text("Lock your Mac when you leave it unattended")
                    .font(.system(size: 11)).foregroundStyle(.white.opacity(0.48)).multilineTextAlignment(.center)
                    .padding(.top, 12).padding(.bottom, 28)
            }
            .padding(.horizontal, 36)
        }
        .frame(width: 404).background(Color(white: 0.105)).preferredColorScheme(.dark)
    }
}

private struct OwnerFaceGuide: View {
    let progress: Double
    let scanning: Bool
    let ready: Bool
    let turn: Double
    let previewSession: AVCaptureSession?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let accent = Color(red: 0.94, green: 0.68, blue: 0.91)
    var body: some View {
        GeometryReader { geometry in
        let diameter = geometry.size.width
        ZStack {
            ForEach(0..<60) { tick in
                Capsule()
                    .fill(ready || scanning && Double(tick) / 60 < progress ? accent : Color.white.opacity(0.20))
                    .frame(width: 2, height: scanning ? 8 : 6)
                    .offset(y: -diameter / 2 + 5)
                    .rotationEffect(.degrees(Double(tick) * 6))
            }
            if let previewSession, scanning {
                OwnerCameraPreview(session: previewSession)
                    .frame(width: diameter - 30, height: diameter - 30)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.1), lineWidth: 0.5))
                    .accessibilityLabel("Live camera preview of your face")
            } else
            if ready {
                Image(systemName: "checkmark").font(.system(size: 32, weight: .light)).foregroundStyle(accent)
            } else {
                FaceOutline()
                    .stroke(accent.opacity(0.9), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                    .frame(width: 62, height: 74)
                    .rotation3DEffect(.degrees(turn * 24), axis: (x: 0, y: 1, z: 0))
            }
        }
        .frame(width: diameter, height: diameter)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: progress)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: turn)
        }
    }
}

/// AVFoundation displays the enrollment session directly; no preview frames are
/// copied into app state, written to disk, or retained after setup ends.
private struct OwnerCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    func makeNSView(context: Context) -> OwnerCameraPreviewView { OwnerCameraPreviewView(session: session) }
    func updateNSView(_ view: OwnerCameraPreviewView, context: Context) {
        if view.preview.session !== session { view.preview.session = session }
        view.needsLayout = true
    }
    static func dismantleNSView(_ view: OwnerCameraPreviewView, coordinator: ()) { view.preview.session = nil }
}

private final class OwnerCameraPreviewView: NSView {
    let preview: AVCaptureVideoPreviewLayer
    init(session: AVCaptureSession) {
        preview = AVCaptureVideoPreviewLayer(session: session)
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor(white: 0.13, alpha: 1).cgColor
        layer?.masksToBounds = true
        preview.videoGravity = .resizeAspectFill
        layer?.addSublayer(preview)
    }
    required init?(coder: NSCoder) { nil }
    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        preview.frame = bounds
        layer?.cornerRadius = min(bounds.width, bounds.height) / 2
        if let connection = preview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = true
        }
        CATransaction.commit()
    }
}

private struct FaceOutline: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()
        p.move(to: CGPoint(x: w*0.08, y: h*0.30))
        p.addCurve(to: CGPoint(x: w*0.92, y: h*0.30), control1: CGPoint(x: w*0.04, y: -h*0.06), control2: CGPoint(x: w*0.96, y: -h*0.06))
        p.move(to: CGPoint(x: w*0.07, y: h*0.50))
        p.addCurve(to: CGPoint(x: w*0.93, y: h*0.50), control1: CGPoint(x: w*0.06, y: h*1.14), control2: CGPoint(x: w*0.94, y: h*1.14))
        for x in [0.30, 0.70] {
            p.move(to: CGPoint(x: w*x, y: h*0.35))
            p.addLine(to: CGPoint(x: w*x, y: h*0.43))
        }
        p.move(to: CGPoint(x: w*0.51, y: h*0.43))
        p.addLine(to: CGPoint(x: w*0.51, y: h*0.60))
        p.addQuadCurve(to: CGPoint(x: w*0.43, y: h*0.63), control: CGPoint(x: w*0.51, y: h*0.64))
        p.move(to: CGPoint(x: w*0.37, y: h*0.75))
        p.addQuadCurve(to: CGPoint(x: w*0.63, y: h*0.75), control: CGPoint(x: w*0.50, y: h*0.80))
        return p
    }
}
