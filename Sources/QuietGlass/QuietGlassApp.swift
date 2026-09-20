// Clinton Imaro was here 20/09/2026.

import AppKit
import Combine

@main
struct QuietGlassApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var statusItem: NSStatusItem!
    private var notch: NotchBarController!
    private var privacySettings: PrivacySettingsController!
    private var headSetup: HeadSetupController!
    private var keyMonitor: Any?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        notch = NotchBarController(model: model)
        privacySettings = PrivacySettingsController(model: model)
        headSetup = HeadSetupController(model: model)
        model.onOpenPrivacySettings = { [weak self] in self?.showPrivacySettings() }
        model.onRequestHeadSetup = { [weak self] in self?.notch.closeControls(); self?.headSetup.show() }
        model.onCancelHeadSetup = { [weak self] in self?.headSetup.close() }
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem()
        let applicationMenu = NSMenu(title: "QuietGlass")
        item("Settings…", #selector(showPrivacySettings), in: applicationMenu, key: ",")
        applicationMenu.addItem(.separator())
        item("Quit QuietGlass", #selector(quit), in: applicationMenu, key: "q")
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let fullScreen = NSMenuItem(title: "Enter Full Screen", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.control, .command]
        viewMenu.addItem(fullScreen)
        viewItem.submenu = viewMenu
        mainMenu.addItem(viewItem)
        NSApp.mainMenu = mainMenu
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = AppIcon.view.image()
        statusItem.button?.setAccessibilityLabel("QuietGlass")
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        buildMenu(menu)
        observation = model.$coverage.combineLatest(model.privacy.$instant).sink { [weak self] value, instant in
            self?.statusItem.button?.image = (value > 0 || instant ? AppIcon.viewOff : .view).image()
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.model.recordingShortcut {
                self.model.recordShortcut(event)
                return nil
            }
            if event.keyCode == 53, self.model.headSetupActive {
                self.headSetup.close()
                return nil
            }
            if event.keyCode == 53, self.model.coverage > 0 || self.model.privacy.wantsProtection {
                self.model.dismissShield()
                return nil
            }
            if event.keyCode == 53 { self.notch.closeControls() }
            return event
        }
        notch.show()
        privacySettings.show()
        if UserDefaults.standard.bool(forKey: "showControlsAfterRelaunch") {
            UserDefaults.standard.removeObject(forKey: "showControlsAfterRelaunch")
            notch.showControls()
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) { buildMenu(menu) }

    func applicationDidResignActive(_ notification: Notification) {
        if NSApp.activationPolicy() == .regular { NSApp.setActivationPolicy(.accessory) }
    }

    private func buildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let title = NSMenuItem(title: "QuietGlass · \(model.status)", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)
        menu.addItem(.separator())
        item("Control", #selector(showControls), in: menu)
        item("Settings…", #selector(showPrivacySettings), in: menu)
        item(notch.isVisible ? "Hide Notch" : "Show Notch", #selector(toggleNotch), in: menu)
        item("Move Notch Down", #selector(resetNotch), in: menu)
        menu.addItem(.separator())
        item(model.privacy.instant ? "Clear Privacy Blur" : "Blur Screen", #selector(togglePrivacy), in: menu, shortcut: "⌃⌥⌘P")
        item(model.enabled ? "Pause Head Tracking" : "Start Head Tracking", #selector(toggleTracking), in: menu)
        let center = item("Center My Gaze", #selector(recenter), in: menu, shortcut: model.shortcutLabel)
        center.isEnabled = model.canRecenter
        item(model.previewing ? "Clear Preview" : "Preview Blur for 5 Seconds", #selector(preview), in: menu)
        item("Clear Screen", #selector(clear), in: menu)
        menu.addItem(.separator())
        item("Quit QuietGlass", #selector(quit), in: menu, key: "q")
    }

    @discardableResult private func item(_ title: String, _ action: Selector, in menu: NSMenu,
                                        key: String = "", shortcut: String? = nil) -> NSMenuItem {
        let displayTitle = shortcut.map { "\(title)    \($0)" } ?? title
        let entry = NSMenuItem(title: displayTitle, action: action, keyEquivalent: key)
        entry.target = self
        menu.addItem(entry)
        return entry
    }

    @objc private func showControls() { notch.showControls() }
    @objc private func showPrivacySettings() { notch.closeControls(); privacySettings.show() }
    @objc private func togglePrivacy() { model.toggleInstantShield() }
    @objc private func toggleNotch() { notch.toggleVisibility() }
    @objc private func resetNotch() { notch.resetPosition(); notch.show() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { privacySettings.show(); notch.show(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        model.shutdown()
        notch.shutdown()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
    }

    @objc private func toggleTracking() { model.setEnabled(!model.enabled) }
    @objc private func recenter() { model.recenter() }
    @objc private func preview() { notch.preview() }
    @objc private func clear() { model.dismissShield() }
    @objc private func quit() { NSApplication.shared.terminate(nil) }
}
