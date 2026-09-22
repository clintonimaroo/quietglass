// Clinton Imaro was here 20/09/2026.

import AppKit
import Combine
import SwiftUI
import ShieldCore

private final class SettingsWindowState: ObservableObject {
    @Published var fullScreen = false
    @Published var presentation = 0
    @Published var profileRequest = 0
    @Published var nearbyRequest = 0
    @Published var maintenanceRequest = 0
    @Published var sidebarToggleRequest = 0
}

@MainActor
final class PrivacySettingsController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var observation: AnyCancellable?
    private var needsInitialFrame = true
    private let windowState = SettingsWindowState()

    init(model: AppModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1112, height: 828),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        super.init()
        window.title = "QuietGlass Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 620)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        let content = NSHostingController(rootView: PrivacySettingsView(model: model, privacy: model.privacy, windowState: windowState))
        content.sizingOptions = []
        window.contentViewController = content
        window.delegate = self
        window.center()
        positionWindowControls()
        observation = model.privacy.$instant.sink { [weak self] active in
            if active { self?.window.orderOut(nil); NSApp.setActivationPolicy(.accessory) }
        }
    }

    func show() {
        windowState.presentation += 1
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if needsInitialFrame, let bounds = window.screen?.visibleFrame {
            needsInitialFrame = false
            let size = NSSize(width: min(1112, bounds.width - 32), height: min(850, bounds.height))
            window.setFrame(NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
    }

    func toggleSidebar() {
        if !window.isVisible { show() }
        windowState.sidebarToggleRequest += 1
    }

    func showProfiles() {
        windowState.profileRequest += 1
        show()
    }

    func showNearbyPeople() {
        windowState.nearbyRequest += 1
        show()
    }
    func showUpdates() { windowState.maintenanceRequest += 1; show() }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }
    func windowWillEnterFullScreen(_ notification: Notification) { windowState.fullScreen = true }
    func windowWillExitFullScreen(_ notification: Notification) { windowState.fullScreen = false }
    func windowDidExitFullScreen(_ notification: Notification) { positionWindowControls() }
    func windowDidResize(_ notification: Notification) { positionWindowControls() }

    private func positionWindowControls() {
        guard !windowState.fullScreen else { return }
        for (index, type) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(type), let parent = button.superview else { continue }
            button.setFrameOrigin(NSPoint(x: 23 + CGFloat(index) * 23 - button.frame.width / 2,
                                          y: parent.bounds.height - 23 - button.frame.height / 2))
        }
    }

    func hideForAreaSelection() {
        window.orderOut(nil)
        NSApp.setActivationPolicy(.accessory)
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if NSApp.activationPolicy() != .regular { NSApp.setActivationPolicy(.regular) }
    }
}

private enum SettingsPalette {
    static let background = Color(red: 24 / 255, green: 24 / 255, blue: 24 / 255)
    static let card = Color(red: 35 / 255, green: 35 / 255, blue: 35 / 255)
    static let border = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)
    static let text = Color(white: 0.88)
    static let secondary = Color(white: 0.58)
    static let accent = Color(red: 0.94, green: 0.68, blue: 0.91)
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case general = "General"
    case protection = "Protection"
    case appRules = "App rules"
    case headTracking = "Head tracking"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .protection: return "lock.shield"
        case .appRules: return "app.badge.checkmark"
        case .headTracking: return "airpodspro"
        }
    }
    var searchTerms: String {
        switch self {
        case .general: return "profile home office public focus full screen demo recording shortcut privacy appearance blur strength preview launch login updates"
        case .protection: return "window area saved remember sensitive text phrases keys email card camera nearby people coverage test side preview"
        case .appRules: return "applications rules stronger pause automatic windows"
        case .headTracking: return "airpods motion setup recenter calibration learning sensitivity monitor external displays screen head position"
        }
    }
}

private struct PrivacySettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var privacy: PrivacyController
    @ObservedObject var windowState: SettingsWindowState
    @State private var editingPhrases = false
    @State private var settingUpOwner = false
    @State private var testingProtection = false
    @State private var showingOwnerDeletion = false
    @State private var phraseDraft = ""
    @State private var page: SettingsPage = .general
    @State private var sidebarPinned = false
    @State private var sidebarRevealed = false
    @State private var hoveredPage: SettingsPage?
    @State private var hoveringSidebarToggle = false
    @State private var sidebarDismissal: Task<Void, Never>?
    @State private var navigationQuery = ""
    @State private var backHistory: [SettingsPage] = []
    @State private var forwardHistory: [SettingsPage] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var sidebarVisible: Bool { sidebarPinned || sidebarRevealed }
    private var navigationAnimation: Animation? { reduceMotion ? nil : .easeInOut(duration: 0.2) }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
            ScrollViewReader { scroll in
            ScrollView {
                VStack(alignment: .leading, spacing: 42) {
                    pageHeading(page.rawValue)
                    VStack(alignment: .leading, spacing: 52) { pageContent }
                }
                .frame(maxWidth: 768, alignment: .leading)
                .padding(.horizontal, 32)
                .padding(.top, 116)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .id(page)
            .onChange(of: windowState.nearbyRequest) { _, _ in
                if page != .protection { backHistory.append(page); forwardHistory.removeAll() }
                page = .protection
                Task { @MainActor in
                    await Task.yield()
                    scroll.scrollTo("nearbyPeople", anchor: .top)
                }
            }
            .onChange(of: windowState.maintenanceRequest) { _, _ in
                if page != .general { backHistory.append(page); forwardHistory.removeAll() }
                page = .general
                Task { @MainActor in await Task.yield(); scroll.scrollTo("maintenance", anchor: .top) }
            }
            }
            .padding(.leading, sidebarPinned && geometry.size.width >= 1040 ? 275 : 0)
            .animation(navigationAnimation, value: sidebarPinned)
            .transition(.opacity)

            if sidebarVisible {
                navigationSidebar
                    .transition(.move(edge: .leading).combined(with: .opacity))
                    .zIndex(1)
            }

            HStack(spacing: 2) {
                sidebarToggle
                if sidebarVisible {
                    Button {
                        guard let previous = backHistory.popLast() else { return }
                        forwardHistory.append(page)
                        withAnimation(navigationAnimation) { page = previous }
                    } label: { Image(systemName: "arrow.left").font(.system(size: 15)).frame(width: 30, height: 30) }
                    .disabled(backHistory.isEmpty).accessibilityLabel("Go back")
                    Button {
                        guard let next = forwardHistory.popLast() else { return }
                        backHistory.append(page)
                        withAnimation(navigationAnimation) { page = next }
                    } label: { Image(systemName: "arrow.right").font(.system(size: 15)).frame(width: 30, height: 30) }
                    .disabled(forwardHistory.isEmpty).accessibilityLabel("Go forward")
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(SettingsPalette.secondary)
            .padding(.leading, windowState.fullScreen ? 7 : 87)
            .padding(.top, 8)
            .animation(navigationAnimation, value: windowState.fullScreen)
            .zIndex(2)
            }
        }
        .frame(minWidth: 716, minHeight: 554)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SettingsPalette.background)
        .ignoresSafeArea(.container, edges: .top)
        .foregroundStyle(SettingsPalette.text)
        .font(.system(size: 14))
        .buttonStyle(QuietGlassButtonStyle())
        .toggleStyle(SettingsSwitchStyle())
        .controlSize(.regular)
        .tint(SettingsPalette.accent)
        .disabled(model.headSetupActive)
        .preferredColorScheme(.dark)
        .onDisappear { sidebarDismissal?.cancel() }
        .onChange(of: windowState.presentation) { _, _ in
            sidebarDismissal?.cancel()
            sidebarPinned = false
            sidebarRevealed = false
            hoveringSidebarToggle = false
            navigationQuery = ""
        }
        .onChange(of: windowState.sidebarToggleRequest) { _, _ in toggleSidebar() }
        .onChange(of: windowState.profileRequest) { _, _ in
            if page != .general { backHistory.append(page); forwardHistory.removeAll() }
            page = .general
        }
        .sheet(isPresented: $editingPhrases) { phraseEditor }
        .sheet(isPresented: $settingUpOwner) { OwnerEnrollmentView(owner: model.nearby.owner) }
        .sheet(isPresented: $testingProtection) {
            ProtectionCheckView(check: model.protectionCheck, cameraID: model.nearby.selectedCameraID,
                                response: model.nearby.response, canBlur: model.screenPermission)
        }
    }

    private var sidebarToggle: some View {
        Button(action: toggleSidebar) {
                Image(systemName: "sidebar.left").font(.system(size: 14, weight: .regular))
                    .foregroundStyle(sidebarVisible ? SettingsPalette.text : SettingsPalette.secondary)
                    .frame(width: 30, height: 30)
                    .background(hoveringSidebarToggle ? Color.white.opacity(0.06) : .clear, in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hoveringSidebarToggle = $0; revealSidebar($0) }
            .accessibilityLabel(sidebarPinned ? "Collapse sidebar" : "Expand sidebar")
            .accessibilityHint("Command S. Hover to preview navigation, or click to keep it open.")
            .overlay(alignment: .topLeading) {
                if hoveringSidebarToggle {
                    HStack(spacing: 9) {
                        Text("Toggle sidebar").font(.system(size: 13))
                        Text("⌘S")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SettingsPalette.accent)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(.white.opacity(0.12), in: Capsule())
                    }
                    .foregroundStyle(SettingsPalette.text)
                    .padding(.leading, 12).padding(.trailing, 7).padding(.vertical, 6)
                    .background(SettingsPalette.background, in: Capsule())
                    .overlay(Capsule().strokeBorder(SettingsPalette.border, lineWidth: 1))
                    .fixedSize()
                    .offset(y: 35)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transition(.opacity)
                }
            }
            .animation(navigationAnimation, value: hoveringSidebarToggle)
    }

    private func toggleSidebar() {
        sidebarDismissal?.cancel()
        withAnimation(navigationAnimation) {
            sidebarPinned.toggle()
            sidebarRevealed = false
        }
    }

    private var phraseEditor: some View {
            VStack(alignment: .leading, spacing: 18) {
                Text("Custom phrases").font(.system(size: 23, weight: .semibold))
                Text("Add one phrase per line. Matches ignore capitalization. Up to 50 phrases, stored only on this Mac.")
                    .foregroundStyle(SettingsPalette.secondary)
                TextEditor(text: $phraseDraft)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Phrases to protect")
                Text("Text recognition can miss matches, especially across line breaks.")
                    .font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                Button("Save phrases") { privacy.savePhrases(phraseDraft); editingPhrases = false }
                    .buttonStyle(QuietGlassButtonStyle())
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(28).frame(width: 460, height: 380)
            .background(SettingsPalette.background).preferredColorScheme(.dark)
    }

    private var navigationSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { model.onOpenControls?() } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.left").font(.system(size: 15)).frame(width: 16)
                    Text("Back to controls")
                    Spacer()
                }
                .padding(.horizontal, 8)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(SettingsPalette.secondary)
                TextField("Search", text: $navigationQuery)
                    .textFieldStyle(.plain)
                    .accessibilityLabel("Search settings")
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(white: 56 / 255), in: Capsule())
            .padding(.top, 12)
            Text("Preferences")
                .font(.system(size: 14))
                .foregroundStyle(SettingsPalette.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
                .padding(.bottom, 8)
            VStack(spacing: 2) {
                ForEach(filteredPages) { item in
                    Button {
                        sidebarDismissal?.cancel()
                        withAnimation(navigationAnimation) {
                            if page != item {
                                backHistory.append(page)
                                forwardHistory.removeAll()
                                page = item
                            }
                            sidebarRevealed = false
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: item.symbol).font(.system(size: 15, weight: .regular)).frame(width: 16, height: 16)
                            Text(item.rawValue)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 8)
                        .frame(height: 30)
                        .background(page == item ? Color(white: 56 / 255) : hoveredPage == item ? Color.white.opacity(0.04) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hoveredPage = $0 ? item : nil }
                    .accessibilityLabel(item.rawValue)
                    .accessibilityAddTraits(page == item ? [.isSelected] : [])
                }
            }
            if filteredPages.isEmpty {
                Text("No matching settings")
                    .font(.system(size: 13)).foregroundStyle(SettingsPalette.secondary)
                    .padding(8)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 48)
        .frame(width: 275)
        .frame(maxHeight: .infinity)
        .background(Color(white: 39 / 255))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.white.opacity(0.045)).frame(width: 1) }
        .shadow(color: .black.opacity(sidebarPinned ? 0 : 0.2), radius: 12, x: 5)
        .onHover(perform: revealSidebar)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings navigation")
    }

    private var filteredPages: [SettingsPage] {
        let query = navigationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return SettingsPage.allCases.filter { query.isEmpty || ($0.rawValue + " " + $0.searchTerms).localizedCaseInsensitiveContains(query) }
    }

    private func revealSidebar(_ inside: Bool) {
        sidebarDismissal?.cancel()
        guard !sidebarPinned else { return }
        if inside {
            withAnimation(navigationAnimation) { sidebarRevealed = true }
        } else {
            sidebarDismissal = Task { @MainActor in
                do { try await Task.sleep(nanoseconds: 220_000_000) } catch { return }
                withAnimation(navigationAnimation) { sidebarRevealed = false }
            }
        }
    }

    @ViewBuilder private var pageContent: some View {
        switch page {
        case .general:
            profiles
            instantProtection
            appearanceSettings
            focusSettings
            protectionStatus
            maintenanceSettings.id("maintenance")
        case .protection:
            windowProtection
            sensitiveProtection
            nearbySettings.id("nearbyPeople")
            protectionStatus
        case .appRules:
            appRules
        case .headTracking:
            calibration
            displaySettings
        }
    }

    private var profiles: some View {
        section("Protection profile") {
            row("Profile", detail: profileDescription) {
                HStack(spacing: 8) {
                    Text(model.currentProfile?.title ?? "Custom").foregroundStyle(SettingsPalette.accent)
                    Image(systemName: "chevron.down").font(.system(size: 10)).foregroundStyle(SettingsPalette.secondary)
                }
                .font(.system(size: 13))
                .frame(minWidth: 74)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
                .overlay(ProfilePickerTrigger(model: model))
                .fixedSize()
            }
            if !model.enabled, !privacy.focusEnabled {
                divider
                row("Head tracking is paused", detail: "Your profile applies when tracking starts. Manual blur stays available.") {
                    Button("Start tracking") { model.start() }
                }
            }
        }
    }

    private var maintenanceSettings: some View {
        section("Everyday use") {
            row("Launch at login", detail: "Keep QuietGlass ready when you sign in to your Mac.") {
                Toggle("Launch at login", isOn: Binding(get: { model.loginPreference.enabled }, set: { model.loginPreference.setEnabled($0) })).labelsHidden()
            }
            if model.loginPreference.needsApproval {
                row("Approve QuietGlass in Login Items") { Button("Open Settings") { model.loginPreference.openSettings() } }
            }
            if let message = model.loginPreference.message { note(message, warning: true) }
            divider
            row("Check for updates", detail: model.updates.message) {
                Button(model.updates.checking ? "Checking…" : "Check now") { Task { await model.updates.check() } }
                    .disabled(model.updates.checking)
                if let page = model.updates.downloadPage { Button("View download") { NSWorkspace.shared.open(page) } }
            }
            divider
            row("Check automatically", detail: "Check GitHub for a public release once a day while QuietGlass is open. Downloads and installation stay under your control.") {
                Toggle("Check automatically", isOn: Binding(get: { model.updates.automatic }, set: { model.updates.automatic = $0 })).labelsHidden()
            }
        }
    }

    private var profileDescription: String {
        switch model.currentProfile {
        case .home: return "More room for natural head movement."
        case .office: return "Balanced sensitivity for everyday work."
        case .publicSpace: return "Blur sooner with stronger protection."
        case .focus: return "Keep your active window clear and soften the rest."
        case nil: return "Using your own blur strength and sensitivity."
        }
    }

    @ViewBuilder private var focusSettings: some View {
        section("Focus") {
            row("Keep your active window clear", detail: "Blur distractions around the window you are using. Turning this on pauses head tracking.") {
                Toggle("Focus mode", isOn: Binding(get: { privacy.focusEnabled }, set: { model.setFocus($0) })).labelsHidden()
            }
        }
    }

    @ViewBuilder private var nearbySettings: some View {
        section("Nearby people") {
            row("Camera", detail: "Choose the camera with the best view of you and the people beside you.") {
                CameraChoicePicker(cameras: model.nearby.cameras, selection: model.nearby.selectedCameraID,
                                   select: model.nearby.selectCamera, refresh: model.nearby.refreshCameras)
                .disabled(model.nearby.owner.busy || model.nearby.owner.enrolling)
            }
            divider
            row("Test my protection", detail: "Preview camera coverage, check both sides, and try your warning or blur.") {
                Button("Run check") { testingProtection = true }
                    .disabled(model.nearby.owner.busy || model.nearby.owner.enrolling)
            }
            divider
            row("Detect additional faces", detail: "Uses your camera while you work. AirPods are not required.") {
                Toggle("Nearby people", isOn: Binding(get: { model.nearby.wantsMonitoring }, set: { model.setNearbyPeople($0) }))
                    .labelsHidden()
                    .disabled(model.nearby.owner.busy || model.nearby.owner.enrolling)
            }
            divider
            row("Recognize me", detail: "Checks your saved face with a small head turn and a look back at the camera before clearing the response.") {
                if model.nearby.owner.enrolled || model.nearby.owner.enabled {
                    Toggle("Recognize me", isOn: Binding(get: { model.nearby.owner.enabled }, set: { value in
                        model.nearby.stop()
                        model.nearby.owner.setEnabled(value)
                    })).labelsHidden().disabled(model.nearby.owner.busy)
                } else {
                    Button("Set up my face") { model.nearby.stop(); settingUpOwner = true }
                        .disabled(model.nearby.owner.busy)
                }
            }
            if model.nearby.owner.enrolled || model.nearby.owner.enabled || showingOwnerDeletion {
                divider
                row("Saved face", detail: "Stored in this Mac’s Keychain. Touch ID or your Mac password is required when monitoring starts.") {
                    HStack(spacing: 8) {
                        Button("Set up again") { model.nearby.stop(); settingUpOwner = true }
                            .disabled(showingOwnerDeletion)
                        InlineDeleteButton(
                            isBusy: model.nearby.owner.busy,
                            isDeleted: !model.nearby.owner.enrolled && !model.nearby.owner.enabled,
                            onConfirm: {
                                showingOwnerDeletion = true
                                model.nearby.stop()
                                model.nearby.owner.deleteEnrollment()
                            },
                            onFinished: { showingOwnerDeletion = false }
                        )
                    }
                }.disabled(model.nearby.owner.busy)
            }
            if let error = model.nearby.owner.error {
                divider
                note(error)
            }
            divider
            row("Camera response", detail: model.nearby.response == .warning ? "Warns beside the notch first, then blurs if the warning is still unresolved." : "Blurs every display when another face appears or your saved face needs verification. Escape clears it and stops the camera.") {
                CameraResponsePicker(selection: Binding(
                    get: { model.nearby.response },
                    set: { model.setNearbyResponse($0) }
                ))
            }
            if model.nearby.response == .warning {
                divider
                row("Blur after", detail: "Time to respond before automatic blur. Clearing the alert cancels the timer; Escape stops monitoring.") {
                    WarningDurationPicker(duration: Binding(
                        get: { model.nearby.warningDelay },
                        set: { model.nearby.setWarningDelay($0) }
                    ))
                }
            }
            divider
            row("Play warning sound", detail: "Plays a short sound once when a warning appears beside the notch.") {
                Toggle("Play warning sound", isOn: Binding(
                    get: { model.nearby.warningSoundEnabled },
                    set: { model.nearby.setWarningSoundEnabled($0) }
                )).labelsHidden()
            }
            if model.nearby.enabled || model.nearby.requesting || model.nearby.message != "Off" {
                divider
                row(model.nearby.message) {
                    if model.nearby.temporarilyPaused {
                        Button("Resume") { model.nearby.resumeNow() }
                    } else if model.nearby.canRetry {
                        if model.nearby.status == .unavailable(.screenPermission) {
                            Button("Open Screen Settings") { model.requestScreenPermission() }
                        }
                        if model.nearby.needsCameraPermission {
                            Button("Camera Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")!)
                            }
                        }
                        Button("Retry") { model.retryNearbyPeople() }
                    } else if model.nearby.enabled {
                        HStack(spacing: 8) {
                            if model.nearby.needsAttention && !model.nearby.covered {
                                Button("Blur now") { model.blurNearbyNow() }
                            }
                            Button("Pause 5 min") { model.nearby.pauseForFiveMinutes() }
                        }
                    }
                }
            }
            divider
            if model.nearbyBlurUnavailable {
                row("Privacy blur unavailable", detail: privacy.notice ?? "Screen capture needs attention.") {
                    Button("Restore blur") { model.retryNearbyBlur() }
                }
                divider
            }
            note("Detection works within your camera’s view. Poor light, glasses, or an obstructed face can cause misses. Recognize me checks your saved face before clearing the response; without it, any steady single face can clear it. Recognition can be fooled by photos or video and does not replace locking your Mac. Camera images are never saved. Your detection setting is remembered, monitoring pauses while your Mac is inactive, and Escape turns it off.", finePrint: true)
        }
    }

    @ViewBuilder private var displaySettings: some View {
        section("Connected displays") {
            ForEach(Array(privacy.displayNames.enumerated()), id: \.offset) { index, name in
                if index > 0 { divider }
                row(name, detail: "Included in full-screen blur and nearby-person protection.") {
                    Text("Included").font(.system(size: 12)).foregroundStyle(SettingsPalette.secondary)
                }
            }
            divider
            row("Separate head position for each display", detail: "Calibrate each display to keep the one you face clear and blur the others.") {
                Toggle("Per-display head tracking", isOn: $model.perDisplayTracking).labelsHidden()
                    .disabled(model.connectedDisplays.count < 2)
            }
            if model.connectedDisplays.count < 2 {
                divider
                note("Connect another display to set a separate head position for each screen.")
            }
            if model.perDisplayTracking {
                if !model.enabled {
                    divider
                    row("Start head tracking first", detail: "Connect your AirPods, then center each display.") {
                        Button("Start tracking") { model.start() }
                    }
                }
                ForEach(model.connectedDisplays, id: \.id) { display in
                    divider
                    row(display.name, detail: model.displayCalibrationIDs.contains(display.id) ? "Centered for this session" : "Click Center, then face this display within three seconds.") {
                        Button("Center") { model.calibrateDisplay(display.id) }.disabled(!model.canRecenter)
                    }
                }
                if let message = model.displayCalibrationNotice { divider; note(message) }
            }
            divider
            note("Head direction is estimated from AirPods motion, not eye tracking. Recenter each display after reconnecting AirPods or changing your sitting position.")
        }
    }

    @ViewBuilder private var instantProtection: some View {
        section("Full-screen privacy") {
            row("Blur every display", detail: "Keep your screen blurred until you clear it. AirPods are not required.") {
                Button(privacy.instant ? "Clear blur" : "Blur screen now") { model.toggleInstantShield() }
            }
            divider
            row("Show blur in recordings", detail: "Include blur in screenshots and recordings of your entire display.") {
                Toggle("Show blur in recordings", isOn: $model.demoMode).labelsHidden()
                    .help("Allow screen captures to include QuietGlass blur. Record the entire display, not an individual app window.")
            }
            if model.demoMode {
                divider
                note("Record your entire display to show the blur. A recording of one app window can bypass it.")
            }
            divider
            row("Instant privacy shortcut", detail: "Press again to clear. Escape clears all protection.") {
                shortcut("⌃⌥⌘P")
            }
            divider
            row("Hold to peek", detail: "Release the shortcut to blur your screen again.") {
                shortcut("⌃⌥⌘Space")
            }
            if let error = model.privacyShortcutError {
                divider
                note(error, warning: true)
            }
        }
    }

    @ViewBuilder private var windowProtection: some View {
        section("Selected window") {
            row("Protect a window", detail: "Blur one window while the rest of your desktop stays clear.") {
                Button("Choose window…") { privacy.chooseWindow() }.disabled(!privacy.canPickWindow)
            }
            divider
            row("Use the active window", detail: "Protect the last window you used outside QuietGlass.") {
                Button("Protect active window") { privacy.protectFrontWindow() }
            }
            divider
            row("Protect part of a window", detail: "Drag over a conversation, sidebar, or other area in the active window.") {
                shortcut(model.areaShortcutLabel)
                Button("Choose area…") { privacy.chooseArea() }
            }
            if let error = model.areaShortcutError {
                divider
                note(error, warning: true)
            }
            ForEach(privacy.protectedAreas) { area in
                divider
                row("Area in \(area.window.name)", detail: "Follows the window when it moves or resizes.") {
                    Button("Remember") { privacy.rememberArea(area) }
                    Button("Remove") { privacy.removeArea(area.id) }
                        .accessibilityLabel("Remove area in \(area.window.name)")
                }
                    .contextMenu { Button("Remove area", role: .destructive) { privacy.removeArea(area.id) } }
            }
            if !privacy.protectedAreas.isEmpty {
                divider
                row("Clear selected areas", detail: "Escape also removes all selected areas.") {
                    Button("Remove all areas") { privacy.removeAllAreas() }
                }
            }
            ForEach(privacy.savedAreas) { area in
                divider
                row("Saved area in \(area.appName)", detail: "Restores when this app opens a window with the same title, including after relaunch.") {
                    InlineDeleteButton(itemName: "saved area", confirmationHelp: "Forget this area and stop restoring its blur",
                                       isBusy: false, isDeleted: false,
                                       onConfirm: { privacy.removeSavedArea(area.id) }, onFinished: {})
                }
            }
            if let window = privacy.selectedWindow {
                divider
                row(window.name.isEmpty ? "Selected window" : window.name,
                    detail: "Protection follows this window until you remove it or close it.") {
                    Button("Remove") { privacy.removeWindow() }
                }
            }
            if !privacy.canPickWindow {
                divider
                note("Activate a window first, then choose Protect active window.")
            }
        }
    }

    @ViewBuilder private var sensitiveProtection: some View {
        section("Sensitive text") {
            row("Blur detected sensitive text", detail: "Find and blur sensitive areas using recognition on your Mac.") {
                Toggle("Blur detected sensitive text", isOn: $privacy.scanEnabled).labelsHidden()
            }
            if privacy.scanEnabled {
                divider
                row("Credentials and API keys") {
                    Toggle("Credentials and API keys", isOn: option(.credentials)).labelsHidden()
                }
                divider
                row("Email addresses") {
                    Toggle("Email addresses", isOn: option(.emailAddresses)).labelsHidden()
                }
                divider
                row("Payment card numbers") {
                    Toggle("Payment card numbers", isOn: option(.paymentCards)).labelsHidden()
                }
                divider
                row("Custom phrases", detail: privacy.customPhrases.isEmpty ? "Choose words or phrases you want to keep private." : "\(privacy.customPhrases.count) phrases saved on this Mac.") {
                    Button("Edit phrases…") { phraseDraft = privacy.customPhrases.joined(separator: "\n"); editingPhrases = true }
                }
                divider
                row("Detected regions") {
                    Text("\(privacy.detectedCount)").monospacedDigit().foregroundStyle(SettingsPalette.secondary)
                }
            }
            divider
            note("Screen content stays on your Mac. Recognized text is never saved. Detection can miss text or react after it appears.")
        }
    }

    @ViewBuilder private var appearanceSettings: some View {
        section("Blur appearance") {
            BlurStrengthControl(strength: $model.blur, accent: SettingsPalette.accent)
        }
    }

    private var protectionStatus: some View {
        VStack(alignment: .leading, spacing: 16) {
            if (privacy.selectedWindow != nil || !privacy.protectedAreas.isEmpty || privacy.hasAutomaticProtection || privacy.scanEnabled || privacy.focusEnabled || privacy.nearbyMonitoring) && !privacy.fullScreen {
                section("Protection status") {
                    row(privacy.captureUnavailable ? "Capture needs attention" : privacy.paused ? "Protection paused" : "Protection active",
                        detail: "Pause clears window, text, and Focus protection. Turn Nearby people off separately.") {
                        if privacy.paused || privacy.captureUnavailable {
                            Button("Resume") { privacy.resume() }
                        } else {
                            Button("Pause protection") { privacy.pauseProtection() }
                        }
                    }
                }
            }
            if !model.screenPermission || privacy.notice != nil {
                section(model.screenPermission ? "Protection notice" : "Screen access") {
                    if !model.screenPermission {
                        row("Allow screen access", detail: "QuietGlass needs screen access to create the blur effect.") {
                            Button("Set up…") { model.requestScreenPermission() }
                        }
                    }
                    if let notice = privacy.notice {
                        if !model.screenPermission { divider }
                        note(notice, warning: true)
                    }
                }
            }
            Text("Blur provides visual protection on your displays. It does not lock your Mac or guarantee protection in recordings or screen sharing.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder private var appRules: some View {
        section("App protection") {
            row("Add the active app", detail: "Choose head sensitivity or automatically blur this app’s windows.") {
                Button("Add \(privacy.frontAppName)") { privacy.addActiveApp() }
                    .disabled(privacy.frontBundleID == nil)
                    .lineLimit(1)
                    .frame(maxWidth: 220)
            }
            divider
            row("Choose another app", detail: "Create a rule for an app installed on your Mac.") {
                Button("Choose app…") { privacy.chooseApp() }
            }
        }
        VStack(alignment: .leading, spacing: 16) {
            section("Your app rules") {
                if privacy.rules.isEmpty {
                    row("No app rules yet", detail: "All apps use your standard sensitivity. Add an app to give it its own behavior.") { EmptyView() }
                }
                ForEach(Array(privacy.rules.enumerated()), id: \.element.id) { index, rule in
                    if index > 0 { divider }
                    row(rule.name) {
                        appRuleSlider(rule)
                        InlineDeleteButton(
                            itemName: "\(rule.name) rule",
                            confirmationHelp: "Remove saved app protection and restore standard head tracking for \(rule.name)",
                            isBusy: false,
                            isDeleted: false,
                            onConfirm: { privacy.removeRule(rule.id) },
                            onFinished: {}
                        )
                    }
                    row("Automatically protect windows", detail: "Blur \(rule.name)’s visible windows whenever they open. Pause protection or press Escape to clear them.") {
                        Toggle("Automatically protect \(rule.name)", isOn: Binding(
                            get: { rule.protectWindows },
                            set: { privacy.setAutomaticWindowProtection(rule.id, enabled: $0) }
                        )).labelsHidden()
                    }
                }
            }
            Text("Stronger starts blurring sooner and increases blur. Pause head blur keeps manual, window, and text protection available.")
                .font(.system(size: 12))
                .foregroundStyle(SettingsPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func appRuleSlider(_ rule: AppPrivacyRule) -> some View {
        let modes: [AppProtectionMode] = [.pause, .standard, .stronger]
        let value = Binding<Double>(
            get: { Double(modes.firstIndex(of: rule.mode) ?? 1) },
            set: { privacy.setRule(rule.id, mode: modes[min(2, max(0, Int($0.rounded())))]) }
        )
        return VStack(spacing: 5) {
            PrivacyLevelSlider(value: value, accent: SettingsPalette.accent,
                               label: "\(rule.name) head blur", valueLabel: rule.mode.title, range: 0...2,
                               minimumLabel: "Pause head blur for \(rule.name)",
                               maximumLabel: "Use stronger head blur for \(rule.name)", showsEndpoints: false)
            HStack {
                ForEach(Array(modes.enumerated()), id: \.element.id) { index, mode in
                    if index > 0 { Spacer(minLength: 0) }
                    Text(mode == .pause ? "Paused" : mode.title)
                        .foregroundStyle(rule.mode == mode ? SettingsPalette.accent : SettingsPalette.secondary)
                }
            }
            .font(.system(size: 10))
            .accessibilityHidden(true)
        }
        .frame(width: 280)
    }

    @ViewBuilder private var calibration: some View {
        section("AirPods") {
            row(model.enabled ? "Head tracking is on" : "Start head tracking",
                detail: "Connect your AirPods, then face the screen to get ready.") {
                Button(model.enabled ? "Pause" : "Start tracking") { model.setEnabled(!model.enabled) }
            }
            divider
            row("Guided setup", detail: "Check your motion, learn a comfortable range, and try your blur.") {
                Button(model.hasCompletedHeadSetup ? "Recalibrate…" : "Set up…") { model.onRequestHeadSetup?() }
                    .disabled(privacy.instant)
            }
        }
        section("Learn your normal movement") {
            row("Calibrate your start angle", detail: "Read normally for eight seconds, making small, comfortable movements while looking at your screen.") {
                if model.learning {
                    Button("Cancel") { model.cancelLearning(); model.recenter() }
                        .accessibilityLabel("Cancel calibration")
                } else {
                    Button("Learn for 8 seconds") { model.learnMovement() }
                        .disabled(!model.canRecenter || privacy.instant)
                }
            }
            if model.learning {
                divider
                ProgressView(value: model.learningProgress)
                    .accessibilityLabel("Calibration progress")
                    .padding(16)
            }
            divider
            note(model.canRecenter
                 ? "Head blur pauses while learning. Window and text protection continue. Review the suggested angle before applying it."
                 : "Connect your AirPods and start tracking to calibrate.")
        }
        section("Sensitivity") {
            row("Current start angle") {
                Text("\(Int(model.comfort))°").monospacedDigit().foregroundStyle(SettingsPalette.secondary)
            }
            if let angle = model.suggestedComfort {
                divider
                row("Suggested start angle", detail: "Apply this suggestion when it feels right for you.") {
                    Button("Use \(Int(angle))°") { model.applyCalibration() }
                }
            }
            if let message = model.learningNotice {
                divider
                note(message)
            }
            divider
            note("Learning uses head motion only. It does not store a motion history or change sensitivity in the background.")
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.system(size: 14)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SettingsPalette.border, lineWidth: 1))
        }
    }

    private func pageHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .regular))
            .accessibilityAddTraits(.isHeader)
    }

    private func row<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(SettingsPalette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            control().fixedSize(horizontal: true, vertical: false)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 15)
    }

    private var divider: some View {
        Rectangle().fill(SettingsPalette.border.opacity(0.7)).frame(height: 1).padding(.horizontal, 16)
    }

    private func note(_ text: String, warning: Bool = false, finePrint: Bool = false) -> some View {
        Text(text)
            .font(.system(size: finePrint ? 11 : 13))
            .foregroundStyle(warning ? Color.orange : finePrint ? Color(white: 0.55) : SettingsPalette.secondary)
            .lineSpacing(finePrint ? 2 : 0)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
    }

    private func shortcut(_ title: String) -> some View {
        Text(title).font(.system(size: 12, design: .monospaced)).foregroundStyle(SettingsPalette.accent)
    }

    private func option(_ value: SensitiveTextOptions) -> Binding<Bool> {
        Binding(get: { privacy.scanOptions.contains(value) }, set: { enabled in
            if enabled { privacy.scanOptions.insert(value) } else { privacy.scanOptions.remove(value) }
        })
    }
}

private struct SettingsSwitchStyle: ToggleStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            Capsule()
                .fill(configuration.isOn ? SettingsPalette.accent : Color(white: 0.21))
                .overlay {
                    Circle().fill(.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.12), radius: 0.5, y: 0.5)
                        .offset(x: configuration.isOn ? 6 : -6)
                }
                .frame(width: 32, height: 20)
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: configuration.isOn)
        .accessibilityRepresentation {
            Toggle(isOn: configuration.$isOn) { configuration.label }.toggleStyle(.switch)
        }
    }
}
