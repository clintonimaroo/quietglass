// Clinton Imaro was here 20/09/2026.

import AppKit
import Combine
import SwiftUI
import ShieldCore

@MainActor
final class PrivacySettingsController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var observation: AnyCancellable?
    private var needsInitialFrame = true

    init(model: AppModel) {
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1106, height: 828),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        super.init()
        window.title = "QuietGlass Settings"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = NSColor(srgbRed: 24 / 255, green: 24 / 255, blue: 24 / 255, alpha: 1)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 760, height: 620)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        let content = NSHostingController(rootView: PrivacySettingsView(model: model, privacy: model.privacy))
        content.sizingOptions = []
        window.contentViewController = content
        window.delegate = self
        window.center()
        observation = model.privacy.$instant.sink { [weak self] active in
            if active { self?.window.orderOut(nil); NSApp.setActivationPolicy(.accessory) }
        }
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        if needsInitialFrame, let bounds = window.screen?.visibleFrame {
            needsInitialFrame = false
            let size = NSSize(width: min(1106, bounds.width - 32), height: min(850, bounds.height))
            window.setFrame(NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
    }

    func windowWillClose(_ notification: Notification) { NSApp.setActivationPolicy(.accessory) }

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

private struct PrivacySettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var privacy: PrivacyController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                protection
                pageHeading("App rules")
                appRules
                pageHeading("Calibration")
                calibration
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 58)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .frame(minWidth: 716, minHeight: 554)
        .background(SettingsPalette.background)
        .foregroundStyle(SettingsPalette.text)
        .font(.system(size: 13))
        .buttonStyle(SettingsButtonStyle())
        .toggleStyle(.switch)
        .controlSize(.regular)
        .tint(SettingsPalette.accent)
        .disabled(model.headSetupActive)
        .preferredColorScheme(.dark)
    }

    @ViewBuilder private var protection: some View {
        section("Full-screen privacy") {
            row("Blur every display", detail: "Keep your screen blurred until you clear it. AirPods are not required.") {
                Button(privacy.instant ? "Clear blur" : "Blur screen now") { model.toggleInstantShield() }
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

        section("Selected window") {
            row("Protect a window", detail: "Blur one window while the rest of your desktop stays clear.") {
                Button("Choose window…") { privacy.chooseWindow() }.disabled(!privacy.canPickWindow)
            }
            divider
            row("Use the active window", detail: "Protect the last window you used outside QuietGlass.") {
                Button("Protect active window") { privacy.protectFrontWindow() }
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
                row("Detected regions") {
                    Text("\(privacy.detectedCount)").monospacedDigit().foregroundStyle(SettingsPalette.secondary)
                }
            }
            divider
            note("Screen content stays on your Mac. Recognized text is never saved. Detection can miss text or react after it appears.")
        }

        section("Blur appearance") {
            BlurStrengthControl(strength: $model.blur, accent: SettingsPalette.accent)
        }

        if (privacy.selectedWindow != nil || privacy.scanEnabled) && !privacy.instant {
            section("Protection status") {
                row(privacy.captureUnavailable ? "Capture needs attention" : privacy.paused ? "Protection paused" : "Protection active",
                    detail: "Applies to selected-window and sensitive-text blur.") {
                    if privacy.paused || privacy.captureUnavailable {
                        Button("Resume") { privacy.resume() }
                    } else {
                        Button("Pause protection") { privacy.dismissAll() }
                    }
                }
            }
        }
        if !model.screenPermission || privacy.notice != nil {
            section("Screen access") {
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

    @ViewBuilder private var appRules: some View {
        section("Automatic head blur") {
            row("Add the active app", detail: "Set how head blur behaves while this app is in use.") {
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
        section("Your app rules") {
            if privacy.rules.isEmpty {
                row("No app rules yet", detail: "All apps use your standard sensitivity. Add an app to give it its own behavior.") { EmptyView() }
            }
            ForEach(Array(privacy.rules.enumerated()), id: \.element.id) { index, rule in
                if index > 0 { divider }
                row(rule.name) {
                    appRuleSlider(rule)
                }
                .contextMenu {
                    Button("Remove rule", role: .destructive) { privacy.removeRule(rule.id) }
                }
            }
        }
        Text("Stronger starts blurring sooner and increases blur. Pause head blur keeps manual, window, and text protection available.")
            .font(.system(size: 12))
            .foregroundStyle(SettingsPalette.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
        section("Head tracking") {
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
            Text(title).font(.system(size: 13, weight: .medium)).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0, content: content)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SettingsPalette.card, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(SettingsPalette.border, lineWidth: 1))
        }
    }

    private func pageHeading(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 23, weight: .regular))
            .accessibilityAddTraits(.isHeader)
            .padding(.top, 16)
    }

    private func row<Content: View>(_ title: String, detail: String? = nil, @ViewBuilder control: () -> Content) -> some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).fixedSize(horizontal: false, vertical: true)
                if let detail {
                    Text(detail)
                        .font(.system(size: 12))
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

    private func note(_ text: String, warning: Bool = false) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(warning ? Color.orange : SettingsPalette.secondary)
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

private struct SettingsButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color(white: configuration.isPressed ? 0.23 : 0.18), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.white.opacity(0.06), lineWidth: 1))
            .opacity(isEnabled ? 1 : 0.4)
    }
}
