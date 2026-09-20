//  Created by Clinton Imaro on 20/09/2026.

import AppKit
import SwiftUI
import ShieldCore

final class HeadSetupPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 420, height: 520)
        contentMaxSize = contentMinSize
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    func installContent(_ controller: NSViewController) {
        contentViewController = controller
        setContentSize(NSSize(width: 420, height: 520))
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

@MainActor
final class HeadSetupController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let window = HeadSetupPanel()

    init(model: AppModel) {
        self.model = model
        super.init()
        window.title = "QuietGlass Head Tracking"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(white: 0.095, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
        window.delegate = self
    }

    func show() {
        if model.headSetupActive {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        guard model.beginHeadSetup() else { return }
        let content = NSHostingController(rootView: HeadSetupView(model: model) { [weak self] completed in
            self?.close(completed: completed)
        })
        content.sizingOptions = []
        window.installContent(content)
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close(completed: Bool = false) {
        model.finishHeadSetup(completed: completed)
        window.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) { model.finishHeadSetup(completed: false) }
}

private enum HeadSetupPhase: Equatable {
    case welcome, connection, center, movement, readyToLearn, learning, review, test
}

private struct HeadSetupView: View {
    @ObservedObject var model: AppModel
    let close: (Bool) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = HeadSetupPhase.welcome
    @State private var movement = HeadSetupProgress()
    @State private var testResponse = ShieldResponse()
    @State private var testCoverage = 0.0
    @State private var testedAway = false
    @State private var testedCenter = false
    @State private var message: String?
    private let pink = Color(red: 0.94, green: 0.68, blue: 0.91)
    private static let image = Bundle.main.url(forResource: "BlurPreview", withExtension: "png").flatMap { NSImage(contentsOf: $0) }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Head tracking").font(.system(size: 13, weight: .medium))
                Spacer()
                Text("Step \(stepLabel)").font(.system(size: 11)).monospacedDigit()
            }
            .foregroundStyle(.secondary)
            .padding(.bottom, 22)
            ring
                .padding(.bottom, 20)
            VStack(spacing: 9) {
                Text(title).font(.system(size: 22, weight: .semibold)).contentTransition(.opacity)
                Text(instructions)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(height: 94, alignment: .top)
            status
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.white.opacity(0.035), in: Capsule())
                .frame(height: 44)
            Spacer(minLength: 12)
            HStack(spacing: 10) {
                if phase == .review {
                    Button("Keep \(Int(model.comfort))°") { beginTest() }
                        .buttonStyle(HeadSetupButtonStyle(primary: false))
                        .frame(width: 86)
                }
                Button(primaryLabel, action: advance)
                    .buttonStyle(HeadSetupButtonStyle(primary: true))
                    .disabled(!canAdvance)
                    .keyboardShortcut(.defaultAction)
            }
            Text("AirPods motion · On your Mac · No camera")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
                .padding(.top, 14)
        }
        .padding(.horizontal, 28)
        .padding(.top, 18)
        .padding(.bottom, 22)
        .frame(width: 420, height: 520)
        .background(Color(white: 0.095))
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: phase)
        .onChange(of: model.canRecenter) { _, ready in
            if ready, phase == .connection { phase = .center; message = nil }
            if !ready, phase != .welcome, phase != .connection {
                model.cancelLearning()
                movement = HeadSetupProgress()
                phase = .connection
                message = "Motion was interrupted. Reconnect your AirPods to continue."
            }
        }
        .onChange(of: model.calibrated) { _, calibrated in
            if !calibrated, model.canRecenter, phase != .welcome, phase != .connection, phase != .center {
                movement = HeadSetupProgress()
                phase = .center
                message = "Your motion reference changed. Face the screen and set center again."
            }
        }
        .onChange(of: model.offset) { _, offset in
            if phase == .movement {
                movement.record(offset, at: ProcessInfo.processInfo.systemUptime)
            } else if phase == .test {
                testCoverage = testResponse.coverage(angle: offset.angle)
                if testCoverage > 0.02 { testedAway = true }
                if testedAway, offset.angle < 5 { testedCenter = true }
            }
        }
        .onChange(of: model.learning) { _, learning in
            guard !learning, phase == .learning else { return }
            if model.suggestedComfort != nil { phase = .review }
            else { message = model.learningNotice; phase = .readyToLearn }
        }
        .onChange(of: model.privacy.instant) { _, active in if active { close(false) } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if phase == .connection, model.status == "Motion permission needed" { model.start() }
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(.white.opacity(0.025))
                .overlay(Circle().strokeBorder(.white.opacity(0.05)))
                .frame(width: 150, height: 150)
            ForEach(0..<48, id: \.self) { index in
                Capsule()
                    .fill(segmentLit(index) ? pink : .white.opacity(0.18))
                    .frame(width: 3, height: 9)
                    .offset(y: -88)
                    .rotationEffect(.degrees(Double(index) * 7.5))
            }
            if phase == .test, let image = Self.image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 146, height: 146)
                    .blur(radius: testCoverage * model.blur / 3)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(.white.opacity(0.15)))
                    .accessibilityLabel("Sample protection test")
                    .accessibilityValue(testCoverage > 0.02 ? "Blurred" : "Clear")
            } else {
                head
            }
        }
        .frame(width: 190, height: 190)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: movement.completed)
    }

    private var head: some View {
        ZStack {
            Ellipse().stroke(.white.opacity(0.8), lineWidth: 2.5).frame(width: 82, height: 104)
            HStack(spacing: 25) {
                Capsule().frame(width: 4, height: 9)
                Capsule().frame(width: 4, height: 9)
            }.offset(y: -12)
            Path { path in
                path.move(to: CGPoint(x: 8, y: 0))
                path.addLine(to: CGPoint(x: 8, y: 18))
                path.addQuadCurve(to: CGPoint(x: 0, y: 21), control: CGPoint(x: 6, y: 24))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 10, height: 24)
            .offset(x: 1, y: -2)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 26, y: 0), control: CGPoint(x: 13, y: 12))
            }
            .stroke(style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 26, height: 10)
            .offset(y: 26)
        }
        .foregroundStyle(.white.opacity(0.8))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : -headYaw), axis: (x: 0, y: 1, z: 0))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : headPitch), axis: (x: 1, y: 0, z: 0))
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.9), value: headYaw)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.22, dampingFraction: 0.9), value: headPitch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live head position")
        .accessibilityValue("Horizontal \(Int(headYaw)) degrees, vertical \(Int(headPitch)) degrees")
    }

    @ViewBuilder private var status: some View {
        if let message {
            Text(message).font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        } else if phase == .connection {
            HStack(spacing: 9) {
                if model.enabled { ProgressView().controlSize(.small) }
                Text(model.enabled ? "Waiting for live motion…" : model.status).font(.system(size: 12))
            }.foregroundStyle(.secondary)
        } else if phase == .movement {
            Text(movement.isComplete ? "All directions checked" : "\(movement.completed.count) of 4 directions checked")
                .font(.system(size: 12, weight: .medium)).foregroundStyle(pink)
        } else if phase == .learning {
            Text("\(max(0, Int(ceil(8 * (1 - model.learningProgress))))) seconds remaining")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(pink)
        } else if phase == .review, let angle = model.suggestedComfort {
            Text("Suggested start angle: \(Int(angle))°")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(pink)
        } else if phase == .test {
            Text(testedCenter && isCentered ? "Motion check complete" : testedAway ? "Face forward to clear the sample" : "Turn until the sample begins to blur")
                .font(.system(size: 12)).foregroundStyle(pink).multilineTextAlignment(.center)
        } else {
            Label(model.connected ? "AirPods connected" : "Compatible AirPods required", systemImage: "airpodspro")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        }
    }

    private func segmentLit(_ index: Int) -> Bool {
        switch phase {
        case .movement:
            let sector = (index + 6) % 48
            let direction = HeadSetupDirection.allCases[sector / 12]
            return Double(sector % 12) < movement.fraction(for: direction) * 12
        case .learning: return Double(index) < model.learningProgress * 48
        case .review: return true
        case .test: return testedCenter || Double(index) < testCoverage * 48
        default: return false
        }
    }

    private var stepLabel: String {
        switch phase {
        case .welcome, .connection, .center: return "1 of 4"
        case .movement: return "2 of 4"
        case .readyToLearn, .learning, .review: return "3 of 4"
        case .test: return "4 of 4"
        }
    }

    private var title: String {
        switch phase {
        case .welcome: return model.hasCompletedHeadSetup ? "Recalibrate head tracking" : "Set up head tracking"
        case .connection: return "Connect your AirPods"
        case .center: return "Face your screen"
        case .movement: return movement.isComplete ? "Movement looks good" : "Follow the ring"
        case .readyToLearn, .learning: return "Find your comfortable range"
        case .review: return "Choose your sensitivity"
        case .test: return testedCenter && isCentered ? "You're ready" : "Try your blur"
        }
    }

    private var instructions: String {
        switch phase {
        case .welcome: return "A quick motion check will help QuietGlass recognize when you look away. Head blur pauses during setup."
        case .connection: return "Wear at least one AirPod connected to this Mac. Keep it in while you complete setup."
        case .center: return "Sit comfortably and look at the middle of your screen. This will be your forward position."
        case .movement: return movement.isComplete
            ? "Your motion is responding well. Next, we'll find a comfortable range for everyday use."
            : "Slowly look left, right, up, and down. Pause briefly in each direction to fill the ring."
        case .readyToLearn, .learning: return "Look at your screen and read normally for eight seconds. Small, natural movements help set your sensitivity."
        case .review: return "Use the suggested angle or keep your current setting. You can adjust it later."
        case .test: return testedCenter && isCentered
            ? "The sample blurred when you looked away and cleared when you returned. You're all set."
            : "Look away to blur the sample, then face forward to clear it. Only this preview will change."
        }
    }

    private var primaryLabel: String {
        switch phase {
        case .welcome: return "Begin setup"
        case .connection: return model.enabled ? "Waiting for AirPods…" : model.status == "Motion permission needed" ? "Open Motion Settings" : "Try again"
        case .center: return "Set center"
        case .movement: return "Continue"
        case .readyToLearn: return "Learn for 8 seconds"
        case .learning: return "Learning…"
        case .review: return "Use \(Int(model.suggestedComfort ?? model.comfort))°"
        case .test: return !model.screenPermission ? "Allow screen access" : "Finish setup"
        }
    }

    private var canAdvance: Bool {
        switch phase {
        case .welcome: return true
        case .connection: return !model.enabled
        case .center: return model.canRecenter
        case .movement: return movement.isComplete && model.canRecenter
        case .readyToLearn, .review: return model.canRecenter
        case .learning: return false
        case .test: return model.canRecenter && ((testedCenter && isCentered) || !model.screenPermission)
        }
    }

    private func advance() {
        message = nil
        switch phase {
        case .welcome, .connection:
            if model.status == "Motion permission needed" { model.openMotionSettings(); return }
            model.start()
            phase = model.canRecenter ? .center : .connection
        case .center:
            model.recenter()
            if model.calibrated { movement = HeadSetupProgress(); phase = .movement }
        case .movement: phase = .readyToLearn
        case .readyToLearn:
            model.learnMovement()
            if model.learning { phase = .learning }
        case .learning: break
        case .review:
            model.applyCalibration()
            beginTest()
        case .test:
            if !model.screenPermission { model.requestScreenPermission() }
            else { close(true) }
        }
    }

    private func beginTest() {
        model.recenter()
        testResponse = ShieldResponse(comfort: model.comfort, transition: model.transition)
        testCoverage = 0
        testedAway = false
        testedCenter = false
        phase = .test
    }

    private var isCentered: Bool { model.offset.angle.isFinite && model.offset.angle < 5 }
    private var headYaw: Double { model.calibrated && model.offset.yaw.isFinite ? max(-30, min(30, model.offset.yaw)) : 0 }
    private var headPitch: Double { model.calibrated && model.offset.pitch.isFinite ? max(-25, min(25, model.offset.pitch)) : 0 }
}

private struct HeadSetupButtonStyle: ButtonStyle {
    let primary: Bool
    @Environment(\.isEnabled) private var isEnabled
    private let pink = Color(red: 0.94, green: 0.68, blue: 0.91)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(primary && isEnabled ? Color.black : Color.white.opacity(isEnabled ? 0.8 : 0.4))
            .background(primary && isEnabled ? pink : Color(white: 0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(primary && isEnabled ? 0 : 0.07)))
            .opacity(configuration.isPressed ? 0.8 : 1)
            .contentShape(Capsule())
    }
}
