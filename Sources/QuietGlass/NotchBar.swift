import AppKit
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// A small, nonactivating utility panel. The desktop remains the main workspace.
@MainActor
final class NotchBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let model: AppModel
    private let panel: NotchPanel
    private let popover = NSPopover()
    private var screenObserver: NSObjectProtocol?
    private let frameName = "QuietGlassFloatingBar"
    var isVisible: Bool { panel.isVisible }

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 154, height: 34),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        panel.title = "QuietGlass"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: NotchBarView(model: model, showControls: { [weak self] in
            self?.toggleControls()
        }))

        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: NotchControlsView(
            model: model, close: { [weak self] in self?.closeControls() },
            preview: { [weak self] in self?.preview() }))

        if !panel.setFrameUsingName(frameName) { resetPosition() }
        constrainToScreen()
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.constrainToScreen() }
        }
    }

    func show() { panel.orderFrontRegardless() }

    func toggleVisibility() {
        if panel.isVisible { closeControls(); panel.orderOut(nil) }
        else { show() }
    }

    func showControls() {
        show()
        guard !popover.isShown, let content = panel.contentView else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: content.bounds, of: content, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.level = panel.level
    }

    private func toggleControls() {
        if popover.isShown { closeControls() } else { showControls() }
    }

    func closeControls() { popover.performClose(nil) }

    func preview() {
        closeControls()
        if model.previewing { model.dismissShield() } else { model.previewShield() }
    }

    func resetPosition() {
        closeControls()
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let visible = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: visible.midX - panel.frame.width / 2, y: visible.minY + 12))
        panel.saveFrame(usingName: frameName)
    }

    private func constrainToScreen() {
        closeControls()
        let frame = panel.frame
        guard let screen = NSScreen.screens.max(by: {
            $0.visibleFrame.intersection(frame).area < $1.visibleFrame.intersection(frame).area
        }) else { return }
        let visible = screen.visibleFrame.insetBy(dx: 8, dy: 8)
        if !visible.intersects(frame) { resetPosition(); return }
        panel.setFrameOrigin(NSPoint(
            x: min(max(frame.minX, visible.minX), visible.maxX - frame.width),
            y: min(max(frame.minY, visible.minY), visible.maxY - frame.height)))
    }

    func windowDidMove(_ notification: Notification) { panel.saveFrame(usingName: frameName) }
    func popoverDidClose(_ notification: Notification) { model.recordingShortcut = false }

    func shutdown() {
        closeControls()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        panel.close()
    }
}

private extension NSRect {
    var area: CGFloat { isNull ? 0 : width * height }
}

private struct NotchBarView: View {
    @ObservedObject var model: AppModel
    let showControls: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if model.previewing { model.dismissShield() }
                else { model.setEnabled(!model.enabled) }
            } label: {
                HugeIconView(icon: model.previewing ? .cancel : model.enabled ? .pause : .play, size: 15)
                    .foregroundStyle(model.enabled || model.previewing ? .white : .white.opacity(0.7))
                    .frame(width: 31, height: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.previewing ? "Clear preview" : model.enabled ? "Pause head tracking" : "Start head tracking")
            .help(model.previewing ? "Clear preview" : model.enabled ? "Pause head tracking" : "Start head tracking")

            Rectangle().fill(.white.opacity(0.13)).frame(width: 1, height: 13)

            Button(action: showControls) {
                HStack(spacing: 7) {
                    HugeIconView(icon: model.coverage > 0 ? .viewOff : .view, size: 15)
                        .foregroundStyle(indicatorColor)
                    Text(barLabel).font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.leading, 10)
                .frame(width: 101, height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("QuietGlass controls, \(barLabel)")
            .help("Open QuietGlass controls")

            DragHandle().frame(width: 19, height: 32)
                .help("Drag to move")
                .accessibilityLabel("Drag to move QuietGlass")
        }
        .frame(width: 152, height: 32)
        .background {
            Capsule().fill(Color(red: 0.065, green: 0.065, blue: 0.075))
                .overlay(Capsule().fill(LinearGradient(colors: [.white.opacity(0.055), .clear], startPoint: .top, endPoint: .bottom)))
        }
        .overlay(Capsule().strokeBorder(.white.opacity(0.16), lineWidth: 0.7))
        .clipShape(Capsule())
        .padding(1)
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: barLabel)
    }

    private var barLabel: String {
        if !model.screenPermission || model.captureNotice != nil || model.status == "Motion permission needed" { return "Set up" }
        if model.previewing { return "Preview" }
        if !model.enabled { return "Paused" }
        if !model.connected { return "AirPods" }
        if !model.calibrated { return "Center" }
        if model.coverage > 0 { return "Blurred" }
        return "Ready"
    }

    private var indicatorColor: Color {
        if !model.screenPermission || model.captureNotice != nil || model.status == "Motion permission needed" { return .orange }
        if model.coverage > 0 { return Color(red: 0.68, green: 0.64, blue: 1) }
        if model.calibrated { return Color(red: 0.55, green: 0.87, blue: 0.74) }
        return .white.opacity(0.5)
    }
}

private struct DragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> HandleView { HandleView() }
    func updateNSView(_ view: HandleView, context: Context) {}

    final class HandleView: NSView {
        override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }
        override func mouseDown(with event: NSEvent) {
            NSCursor.closedHand.push()
            window?.performDrag(with: event)
            NSCursor.pop()
        }
        override func draw(_ dirtyRect: NSRect) {
            let image = HugeIcon.drag.image(size: 12)
            image.isTemplate = false
            let tinted = NSImage(size: image.size, flipped: false) { bounds in
                image.draw(in: bounds)
                NSColor.white.setFill()
                bounds.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: 0, y: 10, width: 12, height: 12), from: .zero, operation: .sourceOver, fraction: 0.35)
        }
    }
}

private struct NotchControlsView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    let preview: () -> Void
    @State private var advanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Text("QuietGlass").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(action: close) { HugeIconView(icon: .cancel, size: 14) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Close controls")
            }
            Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(model.enabled ? "Pause" : "Start") { model.setEnabled(!model.enabled) }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.18))
                Button("Recenter") { model.recenter() }
                    .buttonStyle(.bordered).disabled(!model.canRecenter)
                Spacer()
                if model.connected { HugeIconView(icon: .airpods, size: 19).foregroundStyle(.secondary) }
            }

            if !model.screenPermission {
                Button("Enable screen blur") { model.requestScreenPermission() }.buttonStyle(.bordered)
            }
            if model.status == "Motion permission needed" {
                Button("Open Motion Settings") { model.openMotionSettings() }.buttonStyle(.bordered)
            }
            if let notice = model.captureNotice {
                Text(notice).font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider().overlay(.white.opacity(0.06))
            adjustment("Blur strength", value: $model.blur, range: 10...70, suffix: "")
            adjustment("Start blurring", value: $model.comfort, range: 2...30, suffix: "°")

            Button { advanced.toggle() } label: {
                HStack(spacing: 5) {
                    HugeIconView(icon: .chevronDown, size: 12).rotationEffect(.degrees(advanced ? 0 : -90))
                    Text("More")
                    Spacer()
                }.contentShape(Rectangle())
            }
            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            .accessibilityLabel(advanced ? "Hide more controls" : "Show more controls")
            if advanced {
                VStack(spacing: 10) {
                    adjustment("Transition", value: $model.transition, range: 5...30, suffix: "°")
                    HStack {
                        Text("Recenter").font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button(model.recordingShortcut ? "Press keys…" : model.shortcutLabel) {
                            model.recordingShortcut.toggle()
                        }.font(.system(size: 11, design: .monospaced))
                    }
                    if let error = model.shortcutError {
                        Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    }
                }
            }

            HStack {
                Button(action: preview) {
                    HStack(spacing: 5) {
                        HugeIconView(icon: model.previewing ? .cancel : .play, size: 14)
                        Text(model.previewing ? "Clear preview" : "Preview blur")
                    }
                }.buttonStyle(.plain).font(.system(size: 11))
                Spacer()
                Text("esc to clear").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }
        .padding(16)
        .frame(width: 276)
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.dark)
        .tint(Color(red: 0.76, green: 0.74, blue: 0.93))
    }

    private var hint: String {
        if model.status == "Motion permission needed" { return "Allow AirPods motion to start." }
        if !model.screenPermission { return "Allow screen access for the blur effect." }
        if model.previewing { return "Preview clears after five seconds." }
        if !model.enabled { return "Put on your AirPods, then tap Start." }
        if !model.connected { return "Waiting for your AirPods to connect…" }
        if !model.calibrated { return "Face your screen, then tap Recenter." }
        return model.status
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(title)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix)").monospacedDigit().foregroundStyle(.secondary)
            }.font(.system(size: 11))
            Slider(value: value, in: range, step: 1).controlSize(.small).accessibilityLabel(title)
        }
    }
}
