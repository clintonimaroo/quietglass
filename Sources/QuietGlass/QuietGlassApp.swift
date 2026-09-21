// Clinton Imaro was here 20/09/2026.

import AppKit
import Combine
import ShieldCore

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
    private var profilePicker: ProfilePickerController!
    private var keyMonitor: Any?
    private var observation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        QuietGlassIntentBridge.model = model
        if Bundle.main.url(forResource: "Metadata", withExtension: "appintents") != nil {
            QuietGlassShortcuts.updateAppShortcutParameters()
        }
        notch = NotchBarController(model: model)
        privacySettings = PrivacySettingsController(model: model)
        headSetup = HeadSetupController(model: model)
        profilePicker = ProfilePickerController(model: model)
        model.onShowProfiles = { [weak self] anchor, fromControls in
            guard let self else { return }
            if fromControls { self.notch.showProfiles(self.profilePicker) }
            else { self.profilePicker.show(relativeTo: anchor, fromControls: false) }
        }
        model.privacy.onPrepareAreaSelection = { [weak self] in
            self?.notch.closeControls()
            self?.privacySettings.hideForAreaSelection()
        }
        model.onOpenPrivacySettings = { [weak self] in self?.showPrivacySettings() }
        model.onOpenProfileSettings = { [weak self] in self?.notch.closeControls(); self?.privacySettings.showProfiles() }
        model.onOpenNearbySettings = { [weak self] in self?.notch.closeControls(); self?.privacySettings.showNearbyPeople() }
        model.onOpenControls = { [weak self] in
            self?.privacySettings.hideForAreaSelection()
            self?.notch.showControls()
        }
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
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu
        mainMenu.addItem(editItem)
        let viewItem = NSMenuItem(title: "View", action: nil, keyEquivalent: "")
        let viewMenu = NSMenu(title: "View")
        let sidebar = item("Toggle Sidebar", #selector(toggleSettingsSidebar), in: viewMenu, key: "s")
        sidebar.keyEquivalentModifierMask = [.command]
        viewMenu.addItem(.separator())
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
        let profiles = NSMenuItem(title: "Profile", action: nil, keyEquivalent: "")
        let profileMenu = NSMenu(title: "Profile")
        for profile in PrivacyProfile.allCases {
            let entry = item(profile.title, #selector(selectProfile(_:)), in: profileMenu)
            entry.representedObject = profile.rawValue
            entry.state = model.currentProfile == profile ? .on : .off
        }
        profiles.submenu = profileMenu
        menu.addItem(profiles)
        item("Control", #selector(showControls), in: menu)
        item("Settings…", #selector(showPrivacySettings), in: menu)
        item(notch.isVisible ? "Hide Notch" : "Show Notch", #selector(toggleNotch), in: menu)
        item("Move Notch Down", #selector(resetNotch), in: menu)
        menu.addItem(.separator())
        item(model.privacy.instant ? "Clear Privacy Blur" : "Blur Screen", #selector(togglePrivacy), in: menu, shortcut: "⌃⌥⌘P")
        item("Blur an Area", #selector(chooseArea), in: menu, shortcut: model.areaShortcutLabel)
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

    @objc private func selectProfile(_ sender: NSMenuItem) {
        if let raw = sender.representedObject as? String, let profile = PrivacyProfile(rawValue: raw) { model.applyProfile(profile) }
    }

    @objc private func toggleSettingsSidebar() { privacySettings.toggleSidebar() }
    @objc private func showControls() { notch.showControls() }
    @objc private func showPrivacySettings() { notch.closeControls(); privacySettings.show() }
    @objc private func togglePrivacy() { model.toggleInstantShield() }
    @objc private func chooseArea() { model.privacy.chooseArea() }
    @objc private func toggleNotch() { notch.toggleVisibility() }
    @objc private func resetNotch() { notch.resetPosition(); notch.show() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { privacySettings.show(); notch.show(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        profilePicker.hide()
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
