import AppKit
import SwiftUI

private final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class HintPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

private final class NotchState: ObservableObject {
    @Published var expanded = false
}

private enum NotchAction { case tracking, recenter, preview }

@MainActor
final class NotchBarController: NSObject, NSWindowDelegate, NSPopoverDelegate, NSMenuDelegate {
    private let model: AppModel
    private let state = NotchState()
    private let panel: NotchPanel
    private let hintPanel: HintPanel
    private let canvas = NSView()
    private var hostedBar: NSView!
    private let popover = NSPopover()
    private var screenObserver: NSObjectProtocol?
    private var contextMonitor: Any?
    private var collapseTask: Task<Void, Never>?
    private var snoozeTimer: Timer?
    private var anchor = NSPoint.zero
    private var dragOrigin: (mouse: NSPoint, anchor: NSPoint)?
    private var lastDragEnded = -Double.infinity
    private var contextMenuOpen = false
    private var usesExpandedBounds = false
    private var expansionGeneration = 0
    private var hintGeneration = 0
    private var hintedAction: NotchAction?
    private var followsDock = true
    var isVisible: Bool { panel.isVisible }

    init(model: AppModel) {
        self.model = model
        panel = NotchPanel(contentRect: NSRect(x: 0, y: 0, width: 44, height: 12),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        hintPanel = HintPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        configure(panel, title: "QuietGlass")
        configure(hintPanel, title: "QuietGlass hint")
        hintPanel.ignoresMouseEvents = true
        hintPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        panel.appearance = NSAppearance(named: .aqua)
        panel.delegate = self
        hostedBar = NSHostingView(rootView: NotchBarView(
            model: model, state: state,
            hover: { [weak self] in self?.hover($0) },
            hint: { [weak self] in self?.showHint($0) },
            action: { [weak self] in self?.perform($0) },
            drag: { [weak self] in self?.drag(ended: $0) }))
        canvas.wantsLayer = true
        canvas.layer?.masksToBounds = true
        canvas.addSubview(hostedBar)
        panel.contentView = canvas

        popover.behavior = .transient
        popover.delegate = self
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.contentViewController = NSHostingController(rootView: NotchControlsView(
            model: model, close: { [weak self] in self?.closeControls() },
            preview: { [weak self] in self?.preview() }))

        let preferences = UserDefaults.standard
        // Old builds remembered temporary development positions as the default.
        // Start at the Dock until the user explicitly drags this version elsewhere.
        if preferences.bool(forKey: "notchUsesCustomPosition"), preferences.object(forKey: "notchAnchorX") != nil {
            followsDock = false
            anchor = NSPoint(x: preferences.double(forKey: "notchAnchorX"), y: preferences.double(forKey: "notchAnchorY"))
            constrainToScreen()
        } else { resetPosition() }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.followsDock { self.resetPosition() } else { self.constrainToScreen() }
            }
        }
        contextMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            self.showContextMenu(event)
            return nil
        }
    }

    private func configure(_ window: NSPanel, title: String) {
        window.title = title
        window.isFloatingPanel = true
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    }

    func show() {
        snoozeTimer?.invalidate(); snoozeTimer = nil
        panel.orderFrontRegardless()
    }

    func toggleVisibility() {
        if panel.isVisible { hide() } else { show() }
    }

    private func hide() {
        closeControls()
        collapseTask?.cancel()
        showHint(nil)
        setExpanded(false)
        panel.orderOut(nil)
    }

    private func hover(_ entered: Bool) {
        collapseTask?.cancel()
        if entered {
            setExpanded(true)
            let x = NSEvent.mouseLocation.x - (anchor.x - 24)
            showHint(x < 50 ? .tracking : x < 84 ? .recenter : .preview)
        }
        else { scheduleCollapse() }
    }

    private func scheduleCollapse() {
        collapseTask?.cancel()
        collapseTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 120_000_000) } catch { return }
            guard let self, !self.popover.isShown, !self.contextMenuOpen, self.dragOrigin == nil,
                  !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
            self.showHint(nil)
            self.setExpanded(false)
        }
    }

    private func setExpanded(_ expanded: Bool) {
        guard state.expanded != expanded else { return }
        expansionGeneration += 1
        let generation = expansionGeneration
        if expanded {
            // Grow the transparent drawing area first without moving the artwork.
            usesExpandedBounds = true
            layoutPanel()
        }
        let animation: Animation? = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .smooth(duration: 0.3)
        withAnimation(animation, completionCriteria: .removed) {
            state.expanded = expanded
        } completion: { [weak self] in
            guard let self, !expanded, !self.state.expanded, self.expansionGeneration == generation else { return }
            // Shrinking earlier clips the closing animation. An interrupted close
            // must also never shrink a newly opened notch.
            self.usesExpandedBounds = false
            self.layoutPanel()
        }
    }

    private func layoutPanel() {
        let size = usesExpandedBounds ? NSSize(width: 116, height: 30) : NSSize(width: 44, height: 12)
        let primaryCenter: CGFloat = usesExpandedBounds ? 24 : 22
        panel.setFrame(NSRect(x: anchor.x - primaryCenter, y: anchor.y - size.height / 2,
                              width: size.width, height: size.height), display: true)
        // Keep one persistent 116 × 30 canvas at the same screen coordinates.
        // Only the window's transparent margin changes, after motion has finished.
        hostedBar.frame = NSRect(x: primaryCenter - 24, y: size.height / 2 - 15, width: 116, height: 30)
    }

    private func perform(_ action: NotchAction) {
        guard ProcessInfo.processInfo.systemUptime - lastDragEnded > 0.2 else { return }
        guard state.expanded else { hover(true); return }
        switch action {
        case .tracking:
            if model.previewing { model.dismissShield() }
            else if model.enabled { model.setEnabled(false) }
            else if !model.screenPermission || model.status == "Motion permission needed" { showControls() }
            else { model.setEnabled(true) }
        case .recenter:
            if model.canRecenter { model.recenter() } else { showControls() }
        case .preview:
            if !model.screenPermission { showControls() } else { preview() }
        }
        showHint(action)
    }

    private func drag(ended: Bool) {
        let mouse = NSEvent.mouseLocation
        if let origin = dragOrigin {
            anchor = NSPoint(x: origin.anchor.x + mouse.x - origin.mouse.x, y: origin.anchor.y + mouse.y - origin.mouse.y)
            layoutPanel()
        } else if !ended {
            dragOrigin = (mouse, anchor)
            showHint(nil)
        }
        if ended {
            dragOrigin = nil
            lastDragEnded = ProcessInfo.processInfo.systemUptime
            followsDock = false
            constrainToScreen()
            savePosition()
            scheduleCollapse()
        }
    }

    private func showHint(_ action: NotchAction?) {
        hintGeneration += 1
        let generation = hintGeneration
        guard let action, state.expanded, !popover.isShown, !contextMenuOpen, dragOrigin == nil else {
            hintedAction = nil
            guard hintPanel.isVisible else { return }
            NSAnimationContext.runAnimationGroup { context in
                context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
                hintPanel.animator().alphaValue = 0
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    guard let self, self.hintGeneration == generation else { return }
                    self.hintPanel.orderOut(nil)
                }
            }
            return
        }
        if hintedAction == action, hintPanel.isVisible {
            hintPanel.animator().alphaValue = 1
            return
        }
        hintedAction = action
        let view = NSHostingView(rootView: NotchHintView(model: model, action: action))
        let size = view.fittingSize
        hintPanel.contentView = view
        let center: CGFloat = action == .tracking ? 24 : action == .recenter ? 67 : 101
        var x = panel.frame.minX + center - size.width / 2
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        x = min(max(x, visible.minX + 8), visible.maxX - size.width - 8)
        let y = panel.frame.maxY + 5 + size.height <= visible.maxY
            ? panel.frame.maxY + 5 : panel.frame.minY - size.height - 5
        hintPanel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if !hintPanel.isVisible { hintPanel.alphaValue = 0; hintPanel.orderFrontRegardless() }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            hintPanel.animator().alphaValue = 1
        }
    }

    func showControls() {
        show()
        setExpanded(true)
        showHint(nil)
        guard !popover.isShown, let content = panel.contentView else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: content.bounds, of: content, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
    }

    func closeControls() { popover.performClose(nil) }

    func preview() {
        closeControls()
        showHint(nil)
        if model.previewing { model.dismissShield() } else { model.previewShield() }
    }

    func resetPosition() {
        closeControls()
        guard let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        followsDock = true
        let dock = UserDefaults(suiteName: "com.apple.dock")
        let bottomDock = (dock?.string(forKey: "orientation") ?? "bottom") == "bottom"
        let tileSize = dock?.object(forKey: "tilesize") == nil ? 64 : dock!.double(forKey: "tilesize")
        // visibleFrame can briefly include the Dock while Spaces are changing or
        // the Dock is hidden. Keep the default out of its normal icon area then.
        let dockTop = bottomDock ? screen.frame.minY + max(16, min(128, tileSize)) + 20 : screen.frame.minY
        anchor = NSPoint(x: screen.frame.midX, y: max(screen.visibleFrame.minY, dockTop) + 20)
        layoutPanel()
        savePosition()
    }

    private func constrainToScreen() {
        closeControls()
        guard let screen = NSScreen.screens.first(where: { $0.visibleFrame.contains(anchor) }) else {
            resetPosition(); return
        }
        let visible = screen.visibleFrame.insetBy(dx: 10, dy: 10)
        anchor.x = min(max(anchor.x, visible.minX + 24), visible.maxX - 92)
        anchor.y = min(max(anchor.y, visible.minY + 15), visible.maxY - 15)
        layoutPanel()
    }

    private func savePosition() {
        UserDefaults.standard.set(!followsDock, forKey: "notchUsesCustomPosition")
        UserDefaults.standard.set(anchor.x, forKey: "notchAnchorX")
        UserDefaults.standard.set(anchor.y, forKey: "notchAnchorY")
    }

    private func showContextMenu(_ event: NSEvent) {
        guard let content = panel.contentView else { return }
        closeControls()
        showHint(nil)
        setExpanded(true)
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        menu.minimumWidth = 230
        menuItem("Hide for 1 hour", icon: .clock, action: #selector(snooze), in: menu)
        menuItem("Settings…", icon: .settings, action: #selector(openSettings), in: menu)
        menu.addItem(.separator())
        menuItem(model.enabled ? "Pause tracking" : "Start tracking", icon: model.enabled ? .pause : .play, action: #selector(toggleTracking), in: menu)
        let center = menuItem("Recenter    \(model.shortcutLabel)", icon: .target, action: #selector(recenter), in: menu)
        center.isEnabled = model.canRecenter
        menu.addItem(.separator())
        menuItem("Preview blur", icon: .viewOff, action: #selector(previewFromMenu), in: menu)
        menuItem("Clear screen", icon: .view, action: #selector(clear), in: menu)
        menu.update()
        // Context-menu placement follows the pointer and can cover the notch.
        // Pin the menu's bottom above the entire control row instead.
        let size = menu.size
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let above = panel.frame.maxY + 8 + size.height
        let top = above <= visible.maxY - 8 ? above : panel.frame.minY - 8
        let point = content.convert(panel.convertPoint(fromScreen: NSPoint(x: x, y: top)), from: nil)
        menu.popUp(positioning: nil, at: point, in: content)
    }

    @discardableResult private func menuItem(_ title: String, icon: HugeIcon, action: Selector, in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = icon.image(size: 17)
        menu.addItem(item)
        return item
    }

    func menuWillOpen(_ menu: NSMenu) { contextMenuOpen = true; collapseTask?.cancel() }
    func menuDidClose(_ menu: NSMenu) { contextMenuOpen = false; scheduleCollapse() }
    func popoverDidClose(_ notification: Notification) { model.recordingShortcut = false; scheduleCollapse() }

    @objc private func openSettings() { showControls() }
    @objc private func toggleTracking() { model.setEnabled(!model.enabled) }
    @objc private func recenter() { model.recenter() }
    @objc private func previewFromMenu() { perform(.preview) }
    @objc private func clear() { model.dismissShield() }
    @objc private func snooze() {
        hide()
        snoozeTimer?.invalidate()
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.show() }
        }
    }

    func shutdown() {
        hide()
        snoozeTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let contextMonitor { NSEvent.removeMonitor(contextMonitor) }
        hintPanel.close()
        panel.close()
    }
}

private struct NotchBarView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchState
    let hover: (Bool) -> Void
    let hint: (NotchAction?) -> Void
    let action: (NotchAction) -> Void
    let drag: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .leading) {
            control(.preview, icon: .viewOff, width: 30)
                .scaleEffect(state.expanded ? 1 : 0.45)
                .opacity(state.expanded ? 1 : 0)
                .offset(x: state.expanded ? 86 : 20)
                .allowsHitTesting(state.expanded)
                .accessibilityHidden(!state.expanded)
            control(.recenter, icon: .target, width: 30)
                .scaleEffect(state.expanded ? 1 : 0.45)
                .opacity(state.expanded ? 1 : 0)
                .offset(x: state.expanded ? 52 : 10)
                .allowsHitTesting(state.expanded)
                .accessibilityHidden(!state.expanded)
            control(.tracking, icon: model.previewing ? .cancel : model.enabled ? .pause : .view, width: 48)
        }
        .frame(width: 116, height: 30, alignment: .leading)
        .contentShape(Rectangle())
        .onHover(perform: hover)
        .simultaneousGesture(DragGesture(minimumDistance: 4)
            .onChanged { _ in drag(false) }
            .onEnded { _ in drag(true) })
    }

    private func control(_ item: NotchAction, icon: HugeIcon, width: CGFloat) -> some View {
        let primary = item == .tracking
        return Button { action(item) } label: {
            ZStack {
                Capsule()
                    .fill(.black.opacity(primary && !state.expanded ? 0.58 : 1))
                    .overlay(Capsule().strokeBorder(.white.opacity(primary && !state.expanded ? 0.55 : 0.25), lineWidth: 0.8))
                    .frame(width: primary && !state.expanded ? 40 : width,
                           height: primary && !state.expanded ? 8 : 30)
                HugeIconView(icon: icon, size: 18)
                    .foregroundStyle(.white)
                    .opacity(state.expanded ? 1 : 0)
                    .scaleEffect(state.expanded ? 1 : 0.7)
            }
            .frame(width: width, height: 30)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(primary && !state.expanded ? "QuietGlass notch" : label(item))
        .accessibilityHint(primary && !state.expanded ? "Hover to reveal controls, or right-click for settings" : "")
        .onHover { hint($0 && state.expanded ? item : nil) }
    }

    private func label(_ item: NotchAction) -> String {
        switch item {
        case .tracking:
            if model.previewing { return "Clear preview" }
            if model.enabled { return "Pause tracking" }
            if !model.screenPermission || model.status == "Motion permission needed" { return "Set up screen blur" }
            return "Start tracking"
        case .recenter: return "Recenter"
        case .preview: return "Preview blur"
        }
    }
}

private struct NotchHintView: View {
    @ObservedObject var model: AppModel
    let action: NotchAction

    var body: some View {
        HStack(spacing: 5) {
            Text(label)
            if action == .recenter {
                Text(model.shortcutLabel).foregroundStyle(Color(red: 0.94, green: 0.68, blue: 0.91))
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(white: 0.25), lineWidth: 0.7))
        .fixedSize()
    }

    private var label: String {
        switch action {
        case .tracking:
            if model.previewing { return "Clear preview" }
            if model.enabled { return "Pause tracking" }
            if !model.screenPermission || model.status == "Motion permission needed" { return "Set up screen blur" }
            return "Start tracking"
        case .recenter: return "Recenter"
        case .preview: return "Preview blur"
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
