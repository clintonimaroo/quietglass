// Clinton Imaro was here 20/09/2026.

import AppKit
import SwiftUI
import ShieldCore

extension PrivacyProfile {
    var symbol: String {
        switch self {
        case .home: return "house.fill"
        case .office: return "briefcase.fill"
        case .publicSpace: return "person.2.fill"
        case .focus: return "moon.fill"
        }
    }

    var explanation: String {
        switch self {
        case .home: return "More room for natural head movement."
        case .office: return "Balanced sensitivity for everyday work."
        case .publicSpace: return "Blur sooner with stronger protection."
        case .focus: return "Keep your active window clear and soften the rest."
        }
    }
}

struct ProfilePickerView: View {
    @ObservedObject var model: AppModel
    var back: (() -> Void)? = nil
    var settings: (() -> Void)? = nil
    @State private var hovered: PrivacyProfile?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let pink = Color(red: 0.94, green: 0.68, blue: 0.91)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let back {
                Button(action: back) {
                    HStack(spacing: 7) {
                        Image(systemName: "chevron.left").font(.system(size: 12, weight: .medium))
                        Text("Profiles").font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .foregroundStyle(.secondary)
                    .frame(height: 28)
                    .padding(.horizontal, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to controls")
                .padding(.bottom, 4)
            }
            ForEach(PrivacyProfile.allCases) { profile in
                let selected = model.currentProfile == profile
                Button { model.applyProfile(profile) } label: {
                    HStack(spacing: 10) {
                        Image(systemName: profile.symbol)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(selected ? Color.black.opacity(0.85) : Color.white.opacity(0.82))
                            .frame(width: 26, height: 26)
                            .background(selected ? pink : Color.white.opacity(0.10), in: Circle())
                            .accessibilityHidden(true)
                        Text(profile.title).font(.system(size: 14))
                        Spacer(minLength: 12)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(pink)
                            .opacity(selected ? 1 : 0)
                            .accessibilityHidden(true)
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 32)
                    .background(hovered == profile ? Color.white.opacity(0.06) : .clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? profile : nil }
                .accessibilityLabel("\(profile.title) profile")
                .accessibilityAddTraits(selected ? [.isSelected] : [])
                .help(profile.explanation)
            }
            if let settings {
                Divider().overlay(.white.opacity(0.06)).padding(.horizontal, 8).padding(.vertical, 7)
                Button(action: settings) {
                    Text("Profile settings…")
                        .font(.system(size: 14))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 28)
                        .padding(.horizontal, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(12)
        .frame(width: 220)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(Color.white.opacity(0.88))
        .preferredColorScheme(.dark)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: model.currentProfile)
    }
}

struct ProfilePickerTrigger: NSViewRepresentable {
    @ObservedObject var model: AppModel
    var fromControls = false

    func makeCoordinator() -> Coordinator { Coordinator(model: model, fromControls: fromControls) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel("Choose profile")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.model = model
        button.setAccessibilityValue(model.currentProfile?.title ?? "Custom")
    }

    final class Coordinator: NSObject {
        var model: AppModel
        let fromControls: Bool
        init(model: AppModel, fromControls: Bool) { self.model = model; self.fromControls = fromControls }
        @MainActor @objc func open(_ sender: NSButton) { model.onShowProfiles?(sender, fromControls) }
    }
}

@MainActor
final class ProfilePickerController {
    private let model: AppModel
    private let panel = ProfilePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var localMonitor: Any?
    private var globalMonitor: Any?
    private var parentObservers: [NSObjectProtocol] = []
    private var onDismiss: (() -> Void)?
    var isVisible: Bool { panel.isVisible }

    init(model: AppModel) {
        self.model = model
        panel.title = "QuietGlass Profiles"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show(relativeTo anchor: NSView, fromControls: Bool,
              placement: ((NSSize) -> NSRect)? = nil, onDismiss: (() -> Void)? = nil) {
        guard let window = anchor.window else { return }
        let source = window.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: source.midX, y: source.midY)) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? source.insetBy(dx: -300, dy: -300)
        hide()
        self.onDismiss = onDismiss
        let view = ProfilePickerView(model: model,
            back: fromControls ? { [weak self] in self?.hide(); self?.model.onOpenControls?() } : nil,
            settings: fromControls ? { [weak self] in self?.hide(); self?.model.onOpenProfileSettings?() } : nil)
        let host = NSHostingView(rootView: view)
        let size = host.fittingSize
        let frame = NSRect(origin: .zero, size: size)
        host.frame = frame
        host.autoresizingMask = [.width, .height]
        let material = NSVisualEffectView(frame: frame)
        material.material = .hudWindow
        material.blendingMode = .behindWindow
        material.state = .active
        let mask = NSImage(size: NSSize(width: 37, height: 37), flipped: false) { bounds in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: 18, yRadius: 18).fill()
            return true
        }
        mask.capInsets = NSEdgeInsets(top: 18, left: 18, bottom: 18, right: 18)
        mask.resizingMode = .stretch
        material.maskImage = mask
        material.wantsLayer = true
        material.layer?.cornerRadius = 18
        material.layer?.masksToBounds = true
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView(frame: frame)
            glass.style = .clear
            glass.cornerRadius = 18
            glass.contentView = host
            glass.autoresizingMask = [.width, .height]
            material.addSubview(glass)
        } else {
            material.addSubview(host)
        }
        panel.contentView = material
        var origin = NSPoint(x: source.maxX - size.width, y: source.minY - size.height - 8)
        if origin.y < bounds.minY + 8 { origin.y = source.maxY + 8 }
        origin.x = min(max(origin.x, bounds.minX + 8), bounds.maxX - size.width - 8)
        origin.y = min(max(origin.y, bounds.minY + 8), bounds.maxY - size.height - 8)
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.popUpMenu.rawValue, window.level.rawValue + 1))
        panel.setFrame(placement?(size) ?? NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 1 : 0
        window.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        for name in [NSWindow.willCloseNotification, NSWindow.didMiniaturizeNotification] {
            parentObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.hide() }
            })
        }
        if panel.alphaValue == 0 {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.14
                panel.animator().alphaValue = 1
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53 { self.hide(); return nil }
            if event.type != .keyDown, event.window !== self.panel { self.hide() }
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.hide() }
        }
    }

    func hide() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
        if let localMonitor { NSEvent.removeMonitor(localMonitor); self.localMonitor = nil }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor); self.globalMonitor = nil }
        for observer in parentObservers { NotificationCenter.default.removeObserver(observer) }
        parentObservers.removeAll()
        let dismissed = onDismiss
        onDismiss = nil
        dismissed?()
    }
}

private final class ProfilePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
