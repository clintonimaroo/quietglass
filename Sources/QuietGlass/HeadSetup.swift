//  Created by Clinton Imaro on 20/09/2026.

import AppKit
import SwiftUI
import ShieldCore

final class HeadSetupPanel: NSPanel {
    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 440, height: 568),
                   styleMask: [.titled, .closable], backing: .buffered, defer: false)
        contentMinSize = NSSize(width: 440, height: 568)
        contentMaxSize = contentMinSize
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
    }

    func installContent(_ controller: NSViewController) {
        contentViewController = controller
        setContentSize(NSSize(width: 440, height: 568))
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
                Text(stageName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Spacer()
                HStack(spacing: 5) {
                    ForEach(0..<4) { index in
                        Capsule()
                            .fill(index < stage ? pink : .white.opacity(0.12))
                            .frame(width: index == stage - 1 ? 22 : 12, height: 4)
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(stage) of 4")
            }
            .padding(.bottom, 20)
            illustration
                .frame(height: 196)
                .padding(.bottom, 22)
            VStack(spacing: 10) {
                Text(title)
                    .accessibilityAddTraits(.isHeader)
                    .contentTransition(.opacity)
                    .font(.system(size: 24, weight: .semibold))
                    .tracking(-0.5)
                    .foregroundStyle(.white.opacity(0.94))
                Text(instructions)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineSpacing(3)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 348)
            .frame(height: 86, alignment: .top)
            .id(phase)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 5)))
            status
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .contentTransition(.opacity)
            Spacer(minLength: 16)
            Button(primaryLabel, action: advance)
                .buttonStyle(HeadSetupButtonStyle(primary: true))
                .disabled(!canAdvance)
                .keyboardShortcut(.defaultAction)
            Text("AirPods motion · On your Mac · No camera")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
                .padding(.top, 16)
        }
        .padding(.horizontal, 32)
        .padding(.top, 16)
        .padding(.bottom, 24)
        .frame(width: 440, height: 568)
        .background {
            LinearGradient(colors: [Color(white: 0.115), Color(white: 0.085)],
                           startPoint: .top, endPoint: .bottom)
        }
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: phase)
        .animation(reduceMotion ? nil : .smooth(duration: 0.25), value: movement.completed)
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

    @ViewBuilder private var illustration: some View {
        if phase == .test {
            samplePreview
                .transition(.opacity)
        } else {
            ring
                .transition(.opacity)
        }
    }

    private var ring: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.055), .white.opacity(0.012)],
                                     center: .topLeading, startRadius: 0, endRadius: 160))
                .overlay(Circle().strokeBorder(LinearGradient(
                    colors: [.white.opacity(0.14), .white.opacity(0.02)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.7))
                .frame(width: 154, height: 154)
            ForEach(0..<48, id: \.self) { index in
                Capsule()
                    .fill(segmentLit(index) ? pink : .white.opacity(0.14))
                    .frame(width: 2.5, height: segmentLit(index) ? 10 : 7)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: segmentLit(index))
                    .offset(y: -90)
                    .rotationEffect(.degrees(Double(index) * 7.5))
            }
            if phase == .review, let angle = model.suggestedComfort {
                VStack(spacing: 4) {
                    Text("\(Int(angle))°")
                        .font(.system(size: 42, weight: .light, design: .rounded))
                        .foregroundStyle(pink)
                    Text("Start angle").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .transition(.opacity)
            } else if phase == .learning {
                VStack(spacing: 7) {
                    Text("\(max(0, Int(ceil(8 * (1 - model.learningProgress)))))")
                        .font(.system(size: 42, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: Int(ceil(8 * (1 - model.learningProgress))))
                    Text("seconds remaining").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            } else if phase == .movement, movement.isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(pink)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85).combined(with: .opacity))
                    .accessibilityLabel("All four directions checked")
            } else {
                head
                    .transition(.opacity)
            }
        }
        .frame(width: 196, height: 196)
        .accessibilityElement(children: .contain)
    }

    private var head: some View {
        ZStack {
            HeadOutline()
                .stroke(LinearGradient(colors: [.white.opacity(0.9), .white.opacity(0.5)],
                                       startPoint: .top, endPoint: .bottom),
                        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                .frame(width: 72, height: 92)
            HStack(spacing: 23) {
                Capsule().frame(width: 3.5, height: 7)
                Capsule().frame(width: 3.5, height: 7)
            }.offset(y: -9)
            Path { path in
                path.move(to: CGPoint(x: 7, y: 0))
                path.addLine(to: CGPoint(x: 7, y: 15))
                path.addQuadCurve(to: CGPoint(x: 0, y: 18), control: CGPoint(x: 5, y: 21))
            }
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 8, height: 20)
            .offset(x: 1, y: 2)
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: 18, y: 0), control: CGPoint(x: 9, y: 6))
            }
            .stroke(style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .frame(width: 18, height: 6)
            .offset(y: 24)
            ForEach([-1.0, 1.0], id: \.self) { side in
                Capsule()
                    .fill(model.connected ? pink : Color.white.opacity(0.5))
                    .frame(width: 5, height: 17)
                    .overlay(alignment: .top) {
                        Circle().fill(model.connected ? pink : Color.white.opacity(0.7))
                            .frame(width: 8, height: 8).offset(y: -2)
                    }
                    .offset(x: side * 39, y: 7)
            }
        }
        .foregroundStyle(.white.opacity(0.8))
        .rotation3DEffect(.degrees(reduceMotion ? 0 : -headYaw), axis: (x: 0, y: 1, z: 0), perspective: 0.35)
        .rotation3DEffect(.degrees(reduceMotion ? 0 : headPitch), axis: (x: 1, y: 0, z: 0), perspective: 0.35)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.24, dampingFraction: 0.86), value: headYaw)
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.24, dampingFraction: 0.86), value: headPitch)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Live head position")
        .accessibilityValue("Horizontal \(Int(headYaw)) degrees, vertical \(Int(headPitch)) degrees")
    }

    private var samplePreview: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                ForEach(0..<3) { _ in Circle().fill(.white.opacity(0.2)).frame(width: 5, height: 5) }
                Spacer()
                Image(systemName: "lock.shield").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .frame(height: 26)
            if let image = Self.image {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: 280, height: 148)
                    .blur(radius: testCoverage * model.blur / 3)
                    .clipped()
            }
        }
        .frame(width: 280)
        .background(Color(white: 0.16))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.22), radius: 14, y: 8)
        .animation(reduceMotion ? nil : .smooth(duration: 0.2), value: testCoverage)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sample protection test")
        .accessibilityValue(testCoverage > 0.02 ? "Blurred" : "Clear")
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
            Text("Head blur is paused during setup")
                .font(.system(size: 12)).foregroundStyle(.secondary)
        } else if phase == .review {
            Button("Keep my current \(Int(model.comfort))°") { beginTest() }
                .buttonStyle(.plain)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.6))
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

    private var stage: Int {
        switch phase {
        case .welcome, .connection, .center: return 1
        case .movement: return 2
        case .readyToLearn, .learning, .review: return 3
        case .test: return 4
        }
    }

    private var stageName: String {
        switch stage {
        case 1: return "Get connected"
        case 2: return "Check your motion"
        case 3: return "Find your range"
        default: return "Try your protection"
        }
    }

    private var nextDirection: HeadSetupDirection? {
        [.left, .right, .up, .down].first { !movement.completed.contains($0) }
    }

    private var directionName: String {
        switch nextDirection {
        case .left: return "left"
        case .right: return "right"
        case .up: return "up"
        case .down: return "down"
        case nil: return "forward"
        }
    }

    private var title: String {
        switch phase {
        case .welcome: return model.hasCompletedHeadSetup ? "Recalibrate head tracking" : "Set up head tracking"
        case .connection: return "Connect your AirPods"
        case .center: return "Face your screen"
        case .movement: return movement.isComplete ? "Movement looks good" : "Look gently \(directionName)"
        case .readyToLearn, .learning: return "Find your comfortable range"
        case .review: return "Choose your sensitivity"
        case .test: return testedCenter && isCentered ? "You're ready" : "Try your blur"
        }
    }

    private var instructions: String {
        switch phase {
        case .welcome: return "Teach QuietGlass your natural head movement, then try looking away to blur."
        case .connection: return "Wear your AirPods and connect them to this Mac. Setup continues when motion is ready."
        case .center: return "Sit comfortably and look straight ahead. We’ll use this as your center position."
        case .movement: return movement.isComplete
            ? "All four directions are checked. Next, let’s find your comfortable range."
            : "Turn slowly and hold for a moment. The ring fills as your AirPods detect each direction."
        case .readyToLearn, .learning: return "Read your screen naturally for eight seconds. Small movements help us find the right balance."
        case .review: return "Your screen stays clear within this range. Look further away and the blur begins."
        case .test: return testedCenter && isCentered
            ? "The preview blurred when you looked away and cleared when you returned."
            : "Look away, then face your screen again. Try it safely here before protecting your desktop."
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

private struct HeadOutline: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addCurve(to: CGPoint(x: rect.maxX, y: rect.height * 0.4),
                      control1: CGPoint(x: rect.width * 0.85, y: 0),
                      control2: CGPoint(x: rect.maxX, y: rect.height * 0.18))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.maxY),
                      control1: CGPoint(x: rect.maxX, y: rect.height * 0.76),
                      control2: CGPoint(x: rect.width * 0.76, y: rect.maxY))
        path.addCurve(to: CGPoint(x: rect.minX, y: rect.height * 0.4),
                      control1: CGPoint(x: rect.width * 0.24, y: rect.maxY),
                      control2: CGPoint(x: 0, y: rect.height * 0.76))
        path.addCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                      control1: CGPoint(x: 0, y: rect.height * 0.18),
                      control2: CGPoint(x: rect.width * 0.15, y: 0))
        path.closeSubpath()
        return path
    }
}

private struct HeadSetupButtonStyle: ButtonStyle {
    let primary: Bool
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled
    private let pink = Color(red: 0.94, green: 0.68, blue: 0.91)

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .foregroundStyle(primary && isEnabled ? Color.black : Color.white.opacity(isEnabled ? 0.8 : 0.4))
            .background(primary && isEnabled ? pink : Color(white: 0.14), in: Capsule())
            .overlay(Capsule().strokeBorder(.white.opacity(primary && isEnabled ? 0 : 0.07)))
            .brightness(hovering && isEnabled ? 0.035 : 0)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .contentShape(Capsule())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
    }
}
