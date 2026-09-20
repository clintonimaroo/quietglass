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
final class NotchBarController: NSObject, NSWindowDelegate, NSPopoverDelegate {
    private let model: AppModel
    private let state = NotchState()
    private let panel: NotchPanel
    private let hintPanel: HintPanel
    private let contextPanel: NotchPanel
    private let menuState = NotchMenuState()
    private let canvas = NSView()
    private var hostedBar: NSView!
    private let popover = NSPopover()
    private var screenObserver: NSObjectProtocol?
    private var workspaceObservers: [NSObjectProtocol] = []
    private var dockPositionTimer: Timer?
    private var contextMonitor: Any?
    private var outsideClickMonitor: Any?
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
        contextPanel = NotchPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        super.init()
        configure(panel, title: "QuietGlass")
        configure(hintPanel, title: "QuietGlass hint")
        configure(contextPanel, title: "QuietGlass menu")
        contextPanel.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
        contextPanel.hasShadow = true
        contextPanel.becomesKeyOnlyIfNeeded = false
        contextPanel.appearance = NSAppearance(named: .aqua)
        contextPanel.delegate = self
        contextPanel.contentView = NSHostingView(rootView: NotchContextMenuView(
            model: model, state: menuState, action: { [weak self] in self?.performMenuAction($0) }))
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
                if self.followsDock { self.refreshDockPosition(animated: true) } else { self.constrainToScreen() }
            }
        }
        let workspaceCenter = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didActivateApplicationNotification] {
            workspaceObservers.append(workspaceCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.refreshDockPosition(animated: true) }
            })
        }
        // Space notifications can precede the final Dock geometry. Also follow
        // auto-hide and Dock size changes without requiring an app restart.
        dockPositionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.panel.isVisible else { return }
                self.refreshDockPosition(animated: true)
            }
        }
        dockPositionTimer?.tolerance = 0.1
        contextMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .keyDown]) { [weak self] event in
            guard let self else { return event }
            if self.contextMenuOpen {
                if event.type == .keyDown, self.handleMenuKey(event.keyCode) { return nil }
                if event.type != .keyDown, event.window !== self.contextPanel { self.closeContextMenu() }
            }
            if event.type == .rightMouseDown, event.window === self.panel {
                self.showContextMenu()
                return nil
            }
            return event
        }
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            Task { @MainActor in self?.closeContextMenu() }
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
        refreshDockPosition(animated: false)
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

    private func layoutPanel(animated: Bool = false) {
        let size = usesExpandedBounds ? NSSize(width: 116, height: 30) : NSSize(width: 44, height: 12)
        let primaryCenter: CGFloat = usesExpandedBounds ? 24 : 22
        let frame = NSRect(x: anchor.x - primaryCenter, y: anchor.y - size.height / 2,
                           width: size.width, height: size.height)
        if animated, panel.isVisible, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
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
        closeContextMenu()
        show()
        setExpanded(true)
        showHint(nil)
        guard !popover.isShown, let content = panel.contentView else { return }
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: content.bounds, of: content, preferredEdge: .maxY)
        popover.contentViewController?.view.window?.level = NSWindow.Level(rawValue: panel.level.rawValue + 1)
    }

    func closeControls() { popover.close(); closeContextMenu() }

    func preview() {
        closeControls()
        showHint(nil)
        if model.previewing { model.dismissShield() } else { model.previewShield() }
    }

    func resetPosition() {
        closeControls()
        followsDock = true
        refreshDockPosition(animated: false)
        savePosition()
    }

    private func refreshDockPosition(animated: Bool) {
        guard followsDock, dragOrigin == nil, !popover.isShown, !contextMenuOpen,
              let screen = panel.screen ?? NSScreen.main ?? NSScreen.screens.first else { return }
        let bottom = visibleDockTop(on: screen)
        let target = NSPoint(x: screen.frame.midX, y: bottom + 20)
        guard target != anchor else { return }
        showHint(nil)
        anchor = target
        layoutPanel(animated: animated)
        savePosition()
    }

    private func visibleDockTop(on screen: NSScreen) -> CGFloat {
        let edge = screen.frame.minY
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let desktopTop = NSScreen.screens.first?.frame.maxY else {
            return screen.visibleFrame.minY
        }
        // A background accessory app can keep the desktop's visibleFrame and
        // presentation options in another app's full-screen Space. WindowServer's
        // on-screen Dock bounds reflect whether the Dock actually occupies this
        // display. Only window geometry is read; no screen image is needed.
        var top = edge
        for window in windows {
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.dockWindow)),
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            let frame = NSRect(x: bounds.minX, y: desktopTop - bounds.maxY, width: bounds.width, height: bounds.height)
            let overlap = frame.intersection(screen.frame)
            // Ignore a hidden Dock's activation strip and a Dock on either side.
            guard !overlap.isNull, overlap.height > 4, overlap.width > overlap.height,
                  overlap.minY <= edge + 2 else { continue }
            top = max(top, overlap.maxY)
        }
        guard top > edge else { return edge }
        // visibleFrame gives the normal resting inset without window shadows.
        let inset = screen.visibleFrame.minY
        return inset > edge + 4 ? inset : top
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

    private func showContextMenu() {
        guard let content = contextPanel.contentView else { return }
        closeControls()
        showHint(nil)
        setExpanded(true)
        contextMenuOpen = true
        collapseTask?.cancel()
        menuState.highlighted = nil
        // Measure our actual content, independent of the native menu tracking
        // window that can collapse to a scroll strip beside the Dock.
        let size = content.fittingSize
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let x = min(max(anchor.x - size.width / 2, visible.minX + 8), visible.maxX - size.width - 8)
        let above = panel.frame.maxY + 8
        let y = above + size.height <= visible.maxY - 8 ? above : panel.frame.minY - size.height - 8
        contextPanel.setFrame(NSRect(x: x, y: max(visible.minY + 8, y), width: size.width, height: size.height), display: true)
        contextPanel.makeKeyAndOrderFront(nil)
    }

    private func closeContextMenu() {
        guard contextMenuOpen else { return }
        contextMenuOpen = false
        contextPanel.orderOut(nil)
        menuState.highlighted = nil
        scheduleCollapse()
    }

    private func handleMenuKey(_ code: UInt16) -> Bool {
        if code == 53 { closeContextMenu(); return true }
        let items = NotchMenuAction.allCases.filter { $0 != .recenter || model.canRecenter }
        if code == 125 || code == 126 {
            let step = code == 125 ? 1 : -1
            let index = menuState.highlighted.flatMap { items.firstIndex(of: $0) } ?? (step == 1 ? -1 : 0)
            menuState.highlighted = items[(index + step + items.count) % items.count]
            return true
        }
        if code == 36 || code == 49, let selected = menuState.highlighted {
            performMenuAction(selected)
            return true
        }
        return false
    }

    private func performMenuAction(_ action: NotchMenuAction) {
        closeContextMenu()
        switch action {
        case .snooze: snooze()
        case .settings: showControls()
        case .tracking: perform(.tracking)
        case .recenter: if model.canRecenter { model.recenter() }
        case .preview: perform(.preview)
        case .clear: model.dismissShield()
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === contextPanel { closeContextMenu() }
    }

    func popoverDidClose(_ notification: Notification) { model.recordingShortcut = false; scheduleCollapse() }

    private func snooze() {
        hide()
        snoozeTimer?.invalidate()
        snoozeTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.show() }
        }
    }

    func shutdown() {
        hide()
        snoozeTimer?.invalidate()
        dockPositionTimer?.invalidate()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        for observer in workspaceObservers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        if let contextMonitor { NSEvent.removeMonitor(contextMonitor) }
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        contextPanel.close()
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
            control(.preview, icon: model.previewing ? .cancel : .viewOff, width: 30)
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

    private func control(_ item: NotchAction, icon: AppIcon, width: CGFloat) -> some View {
        let primary = item == .tracking
        return Button { action(item) } label: {
            ZStack {
                Capsule()
                    .fill(.black.opacity(primary && !state.expanded ? 0.58 : 1))
                    .overlay(Capsule().strokeBorder(.white.opacity(primary && !state.expanded ? 0.55 : 0.25), lineWidth: 0.8))
                    .frame(width: primary && !state.expanded ? 40 : width,
                           height: primary && !state.expanded ? 8 : 30)
                AppIconView(icon: icon, size: 18)
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
        case .preview: return model.previewing ? "Clear preview" : "Preview blur"
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
        case .preview: return model.previewing ? "Clear preview" : "Preview blur"
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
                CloseControlsButton(action: close).frame(width: 28, height: 28)
            }
            Text(hint).font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Button(model.enabled ? "Pause" : "Start") { model.setEnabled(!model.enabled) }
                    .buttonStyle(.borderedProminent).tint(.white.opacity(0.18))
                Button("Recenter") { model.recenter() }
                    .buttonStyle(.bordered).disabled(!model.canRecenter)
                Spacer()
                if model.connected {
                    Image(systemName: "airpodspro")
                        .font(.system(size: 18, weight: .regular))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.white)
                        .accessibilityLabel("AirPods connected")
                }
            }

            if !model.screenPermission {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Already enabled? Restart QuietGlass. If this happened after an update, turn its Screen Recording switch off and on first.")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Button("Screen Settings") { model.requestScreenPermission() }
                        Button(model.restarting ? "Restarting…" : "Restart QuietGlass") { model.restartForScreenPermission() }
                            .disabled(model.restarting)
                    }.buttonStyle(.bordered).controlSize(.small)
                }
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
                    AppIconView(icon: .chevronDown, size: 12).rotationEffect(.degrees(advanced ? 0 : -90))
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
                        AppIconView(icon: model.previewing ? .cancel : .play, size: 14)
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
        if model.previewing { return "Click Clear preview or press Escape to clear." }
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

private final class FirstClickCloseButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct CloseControlsButton: NSViewRepresentable {
    let action: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    func makeNSView(context: Context) -> NSButton {
        let button = FirstClickCloseButton()
        button.title = ""
        button.image = AppIcon.cancel.image(size: 14)
        button.imagePosition = .imageOnly
        button.contentTintColor = .secondaryLabelColor
        button.isBordered = false
        button.setButtonType(.momentaryChange)
        button.target = context.coordinator
        button.action = #selector(Coordinator.close)
        button.setAccessibilityLabel("Close controls")
        button.toolTip = "Close controls"
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) { context.coordinator.action = action }

    final class Coordinator: NSObject {
        var action: () -> Void
        init(action: @escaping () -> Void) { self.action = action }
        @objc func close() { action() }
    }
}
