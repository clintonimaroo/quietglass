//  Created by Clinton Imaro on 20/09/2026.

import AppKit
import ScreenCaptureKit
import ShieldCore

struct ProtectedWindow: Equatable {
    let id: CGWindowID
    let owner: pid_t
    let name: String
}

struct ProtectedArea: Identifiable {
    let id = UUID()
    let window: ProtectedWindow
    let rectangle: CGRect
}

@MainActor
final class PrivacyController: NSObject, ObservableObject, SCContentSharingPickerObserver {
    @Published private(set) var instant = false
    @Published private(set) var peeking = false
    @Published private(set) var paused = false
    @Published private(set) var protectedAreas: [ProtectedArea] = []
    private let areaSelector = AreaSelectionController()
    private var areaSelectionTask: Task<Void, Never>?
    var onPrepareAreaSelection: (() -> Void)?
    @Published private(set) var selectedWindow: ProtectedWindow?
    @Published private(set) var notice: String?
    @Published private(set) var detectedCount = 0
    @Published private(set) var captureUnavailable = false
    @Published private(set) var ready = false
    @Published private(set) var rules: [AppPrivacyRule]
    @Published private(set) var frontAppName = "No active app"
    @Published private(set) var frontBundleID: String?
    @Published private(set) var focusEnabled = false
    @Published private(set) var nearbyMonitoring = false
    @Published private(set) var nearbyCovered = false
    @Published private(set) var displayNames = NSScreen.screens.map(\.localizedName)
    @Published private(set) var customPhrases: [String]
    @Published var scanEnabled: Bool {
        didSet { UserDefaults.standard.set(scanEnabled, forKey: "privacyScanEnabled"); paused = false; restartCapture() }
    }
    @Published var scanOptions: SensitiveTextOptions {
        didSet { UserDefaults.standard.set(scanOptions.rawValue, forKey: "privacyScanOptions"); restartCapture() }
    }

    var onRulesChanged: (() -> Void)?
    var onActivityChanged: (() -> Void)?
    var requestEscape: (() -> Bool)?
    var blurRadius = 28.0 {
        didSet { for capture in captures.values { capture.setRadius(blurRadius) } }
    }
    var includeInCaptures = false {
        didSet {
            for surface in surfaces.values {
                surface.panel.sharingType = includeInCaptures ? .readOnly : .none
            }
        }
    }
    private var frontPID: pid_t?
    private var observers: [NSObjectProtocol] = []
    private var timer: Timer?
    private(set) var surfaces: [CGDirectDisplayID: PrivacySurface] = [:]
    private var captures: [CGDirectDisplayID: DisplayCapture] = [:]
    private var analyzers: [CGDirectDisplayID: LocalTextAnalyzer] = [:]
    private var detected: [CGDirectDisplayID: [CGRect]] = [:]
    private var visibleRegions: [CGRect] = []
    private var controlRegions: [CGRect] = []
    private var focusWindow: CGRect?
    private var captureTask: Task<Void, Never>?
    private var generation = 0
    private var captureAllowed = false

    override init() {
        let prefs = UserDefaults.standard
        customPhrases = prefs.stringArray(forKey: "privacyCustomPhrases") ?? []
        scanEnabled = prefs.bool(forKey: "privacyScanEnabled")
        scanOptions = SensitiveTextOptions(rawValue: prefs.object(forKey: "privacyScanOptions") == nil ? 1 : prefs.integer(forKey: "privacyScanOptions"))
        rules = prefs.data(forKey: "privacyAppRules").flatMap { try? JSONDecoder().decode([AppPrivacyRule].self, from: $0) } ?? []
        super.init()
        SCContentSharingPicker.shared.add(self)
        if let app = NSWorkspace.shared.frontmostApplication { activated(app) }
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            Task { @MainActor in self?.activated(app) }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.screenParametersChanged() }
        })
        observers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refreshGeometry() }
        })
    }

    var fullScreen: Bool { instant || nearbyCovered }
    var wantsProtection: Bool { fullScreen || nearbyMonitoring || (!paused && (selectedWindow != nil || !protectedAreas.isEmpty || scanEnabled || focusEnabled)) }

    func setFocus(_ value: Bool) {
        guard value != focusEnabled else { return }
        focusEnabled = value
        paused = false
        restartCapture()
    }

    func setNearbyMonitoring(_ value: Bool) {
        guard value != nearbyMonitoring else { return }
        nearbyMonitoring = value
        if !value { nearbyCovered = false }
        restartCapture()
    }

    func setNearbyCovered(_ value: Bool) {
        guard value != nearbyCovered else { return }
        nearbyCovered = value
        refreshGeometry()
        onActivityChanged?()
    }

    func savePhrases(_ text: String) {
        customPhrases = SensitiveText.cleanPhrases(text.components(separatedBy: .newlines))
        UserDefaults.standard.set(customPhrases, forKey: "privacyCustomPhrases")
        if scanEnabled { restartCapture() }
    }
    var ruleMode: AppProtectionMode { rules.first { $0.bundleID == frontBundleID }?.mode ?? .standard }
    var canPickWindow: Bool { if #available(macOS 15.2, *) { return true }; return false }

    func start() { restartCapture() }

    private func activated(_ app: NSRunningApplication) {
        guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular, let bundle = app.bundleIdentifier else { return }
        frontPID = app.processIdentifier
        frontBundleID = bundle
        frontAppName = app.localizedName ?? bundle
        onRulesChanged?()
        refreshGeometry()
    }

    func addActiveApp() {
        guard let bundle = frontBundleID else { return }
        addRule(bundleID: bundle, name: frontAppName)
    }

    func chooseApp() {
        let chooser = NSOpenPanel()
        chooser.canChooseDirectories = false
        chooser.allowedContentTypes = [.applicationBundle]
        chooser.directoryURL = URL(fileURLWithPath: "/Applications")
        chooser.prompt = "Add app"
        chooser.begin { [weak self] response in
            guard response == .OK, let url = chooser.url, let bundle = Bundle(url: url), let identifier = bundle.bundleIdentifier else { return }
            Task { @MainActor in self?.addRule(bundleID: identifier, name: url.deletingPathExtension().lastPathComponent) }
        }
    }

    private func addRule(bundleID: String, name: String) {
        guard bundleID != Bundle.main.bundleIdentifier, !rules.contains(where: { $0.bundleID == bundleID }) else { return }
        rules.append(AppPrivacyRule(bundleID: bundleID, name: name))
        saveRules()
    }

    func setRule(_ id: String, mode: AppProtectionMode) {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
        rules[index].mode = mode
        saveRules()
    }

    func removeRule(_ id: String) { rules.removeAll { $0.id == id }; saveRules() }

    private func saveRules() {
        if let data = try? JSONEncoder().encode(rules) { UserDefaults.standard.set(data, forKey: "privacyAppRules") }
        onRulesChanged?()
    }

    func toggleInstant() {
        guard instant || requestEscape?() == true else { notice = "Another app reserved Escape. Release that shortcut before shielding."; return }
        instant.toggle()
        peeking = false
        restartCapture()
    }

    func setPeeking(_ value: Bool) {
        guard fullScreen else { return }
        peeking = value
        render()
    }

    func dismissAll() {
        areaSelectionTask?.cancel(); areaSelectionTask = nil
        areaSelector.close()
        protectedAreas.removeAll()
        instant = false
        nearbyCovered = false
        focusEnabled = false
        peeking = false
        paused = true
        restartCapture()
    }

    func resume() { paused = false; restartCapture() }
    func pauseProtection() { paused = true; focusEnabled = false; restartCapture() }

    func removeWindow() { selectedWindow = nil; visibleRegions = []; restartCapture() }

    func chooseArea() {
        areaSelectionTask?.cancel()
        areaSelector.close()
        guard let pid = frontPID, let app = NSRunningApplication(processIdentifier: pid) else {
            notice = "Open the window you want to protect, then choose an area."
            return
        }
        notice = nil
        NSApp.yieldActivation(to: app)
        onPrepareAreaSelection?()
        app.activate(from: .current, options: [])
        areaSelectionTask = Task { [weak self] in
            for _ in 0..<20 {
                do { try await Task.sleep(nanoseconds: 100_000_000) } catch { return }
                guard let self else { return }
                if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid,
                   let item = Self.frontWindowItem(in: self.windowList(onScreen: true), for: pid) {
                    self.showAreaSelector(item: item, pid: pid, name: app.localizedName ?? "Selected window")
                    return
                }
            }
            self?.notice = "Bring the window you want to protect into view, then choose an area again."
        }
    }

    private func showAreaSelector(item: [String: Any], pid: pid_t, name: String) {
        guard
              let number = item[kCGWindowNumber as String] as? NSNumber,
              let bounds = item[kCGWindowBounds as String] as? NSDictionary,
              let quartz = CGRect(dictionaryRepresentation: bounds) else {
            notice = "Open a window first, then choose an area."
            return
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        let frame = CGRect(x: quartz.minX, y: top - quartz.maxY, width: quartz.width, height: quartz.height)
        let window = ProtectedWindow(id: number.uint32Value, owner: pid, name: name)
        areaSelector.show(frame: frame) { [weak self] rectangle in
            self?.protectArea(rectangle, in: window)
        }
    }

    func protectArea(_ rectangle: CGRect, in window: ProtectedWindow) {
        protectedAreas.append(ProtectedArea(window: window, rectangle: rectangle))
        paused = false
        restartCapture()
    }

    func removeArea(_ id: UUID) { protectedAreas.removeAll { $0.id == id }; restartCapture() }
    func removeAllAreas() { protectedAreas.removeAll(); restartCapture() }

    func protectFrontWindow() {
        guard let pid = frontPID else { notice = "Open the window you want to protect first."; return }
        guard let item = Self.frontWindowItem(in: windowList(onScreen: true), for: pid),
              let number = item[kCGWindowNumber as String] as? NSNumber else {
            notice = "No visible window is available for \(frontAppName)."
            return
        }
        select(ProtectedWindow(id: number.uint32Value, owner: pid,
                               name: item[kCGWindowName as String] as? String ?? frontAppName))
    }

    func chooseWindow() {
        guard canPickWindow else { protectFrontWindow(); return }
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = .singleWindow
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "local.clinton.QuietGlass"]
        configuration.allowsChangingSelectedContent = false
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present(using: .window)
    }

    private func select(_ window: ProtectedWindow) {
        guard requestEscape?() == true else { notice = "Escape is in use. Window protection could not start."; return }
        selectedWindow = window
        paused = false
        restartCapture()
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor in picker.isActive = false }
    }

    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in
            picker.isActive = false
            if #available(macOS 15.2, *), let window = filter.includedWindows.first,
               let app = window.owningApplication {
                self?.select(ProtectedWindow(id: window.windowID, owner: app.processID, name: window.title ?? app.applicationName))
            }
        }
    }

    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in
            SCContentSharingPicker.shared.isActive = false
            self?.notice = "Window selection could not open. Try Protect active window instead."
        }
    }

    private func restartCapture() {
        stopCapture(clearSurfaces: !wantsProtection)
        notice = nil
        captureUnavailable = false
        captureAllowed = false
        guard wantsProtection else { onActivityChanged?(); return }
        guard requestEscape?() == true else { paused = true; instant = false; nearbyCovered = false; notice = "Escape is unavailable. Protection is paused."; onActivityChanged?(); return }
        guard CGPreflightScreenCaptureAccess() else {
            paused = true
            instant = false
            nearbyCovered = false
            notice = "Allow screen access in the notch controls to use privacy blur."
            onActivityChanged?()
            return
        }
        captureAllowed = true
        reconcileSurfaces()
        refreshGeometry()
        timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshGeometry() }
        }
        RunLoop.main.add(timer!, forMode: .common)
        onActivityChanged?()
    }

    func screenParametersChanged() {
        displayNames = NSScreen.screens.map(\.localizedName)
        reconcileSurfaces()
        refreshGeometry()
    }

    private func reconcileSurfaces() {
        var live: Set<CGDirectDisplayID> = []
        for screen in NSScreen.screens {
            guard let id = (screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value else { continue }
            live.insert(id)
            if let surface = surfaces[id] {
                if surface.panel.frame != screen.frame {
                    surface.resize(to: screen.frame)
                    captures.removeValue(forKey: id)?.stop()
                    analyzers.removeValue(forKey: id)?.cancel()
                    detected.removeValue(forKey: id)
                }
            }
            else { surfaces[id] = PrivacySurface(screen: screen, includeInCaptures: includeInCaptures) }
        }
        for id in Set(surfaces.keys).subtracting(live) {
            captures.removeValue(forKey: id)?.stop()
            analyzers.removeValue(forKey: id)?.cancel()
            detected.removeValue(forKey: id)
            surfaces.removeValue(forKey: id)?.panel.close()
        }
        detectedCount = detected.values.reduce(0) { $0 + $1.count }
    }

    private func windowList(onScreen: Bool) -> [[String: Any]] {
        CGWindowListCopyWindowInfo(onScreen ? [.optionOnScreenOnly, .excludeDesktopElements] : [.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
    }

    static func frontWindowItem(in items: [[String: Any]], for pid: pid_t) -> [String: Any]? {
        items.first { item in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == pid,
                  (item[kCGWindowLayer as String] as? NSNumber)?.intValue == 0,
                  (item[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let frame = CGRect(dictionaryRepresentation: bounds),
                  frame.width > 80, frame.height > 80 else { return false }
            return frame.height >= 200 || frame.width / frame.height < 6
        }
    }

    private func refreshGeometry() {
        guard wantsProtection else { return }
        visibleRegions = []
        let dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
        let items = windowList(onScreen: true).filter { item in
            guard let dockPID else { return true }
            return (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value != dockPID
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        controlRegions = items.compactMap { item in
            guard (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier,
                  (item[kCGWindowLayer as String] as? Int ?? 0) == 0,
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return CGRect(x: quartz.minX, y: top - quartz.maxY, width: quartz.width, height: quartz.height)
        }
        focusWindow = frontPID.flatMap { Self.frontWindowItem(in: items, for: $0) }.flatMap { item in
            guard
                  let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                  let quartz = CGRect(dictionaryRepresentation: bounds) else { return nil }
            return CGRect(x: quartz.minX, y: top - quartz.maxY, width: quartz.width, height: quartz.height)
        }
        if !fullScreen, !paused, let selected = selectedWindow {
            var occluders: [CGRect] = []
            for item in items {
                guard let number = item[kCGWindowNumber as String] as? NSNumber,
                      let owner = item[kCGWindowOwnerPID as String] as? NSNumber,
                      let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                      let quartz = CGRect(dictionaryRepresentation: bounds),
                      (item[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
                let frame = CGRect(x: quartz.minX, y: top - quartz.maxY, width: quartz.width, height: quartz.height)
                if owner.int32Value == ProcessInfo.processInfo.processIdentifier {
                    if (item[kCGWindowLayer as String] as? Int ?? 0) == 0 { occluders.append(frame) }
                    continue
                }
                if number.uint32Value == selected.id, owner.int32Value == selected.owner {
                    visibleRegions = ScreenRegions.visible(frame, behind: occluders)
                    break
                }
                if (item[kCGWindowLayer as String] as? Int ?? 0) >= 0 { occluders.append(frame) }
            }
            if visibleRegions.isEmpty, !windowList(onScreen: false).contains(where: {
                ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == selected.id &&
                ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == selected.owner
            }) {
                selectedWindow = nil
                notice = "The protected window closed."
                if !wantsProtection { stopCapture(); onActivityChanged?(); return }
            }
        }
        if !fullScreen, !paused, !protectedAreas.isEmpty {
            let existing = windowList(onScreen: false)
            protectedAreas.removeAll { area in
                !existing.contains { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == area.window.id && ($0[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == area.window.owner }
            }
            for area in protectedAreas {
                var occluders: [CGRect] = []
                for item in items {
                    guard let bounds = item[kCGWindowBounds as String] as? NSDictionary,
                          let quartz = CGRect(dictionaryRepresentation: bounds),
                          (item[kCGWindowAlpha as String] as? Double ?? 1) > 0 else { continue }
                    let frame = CGRect(x: quartz.minX, y: top - quartz.maxY, width: quartz.width, height: quartz.height)
                    if (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == ProcessInfo.processInfo.processIdentifier {
                        if (item[kCGWindowLayer as String] as? Int ?? 0) == 0 { occluders.append(frame) }
                        continue
                    }
                    if (item[kCGWindowNumber as String] as? NSNumber)?.uint32Value == area.window.id,
                       (item[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == area.window.owner {
                        visibleRegions += ScreenRegions.visible(ScreenRegions.fromVision(area.rectangle, in: frame), behind: occluders)
                        break
                    }
                    if (item[kCGWindowLayer as String] as? Int ?? 0) >= 0 { occluders.append(frame) }
                }
            }
        }
        guard wantsProtection else { stopCapture(); onActivityChanged?(); return }
        render()
        startCaptureIfNeeded()
    }

    private func render() {
        for (id, surface) in surfaces {
            var regions = visibleRegions.map { $0.intersection(surface.panel.frame) }.filter { !$0.isNull && !$0.isEmpty }
            if focusEnabled, !paused {
                regions += ScreenRegions.visible(surface.panel.frame, behind: controlRegions + (focusWindow.map { [$0] } ?? []))
            }
            let sensitive = (paused ? [] : detected[id] ?? []).flatMap { ScreenRegions.visible(ScreenRegions.fromVision($0, in: surface.panel.frame), behind: controlRegions) }
            surface.update(windows: fullScreen ? [] : regions, sensitive: fullScreen ? [] : sensitive, fullScreen: fullScreen, peeking: peeking && instant && !nearbyCovered)
        }
    }

    private func startCaptureIfNeeded() {
        guard captureAllowed, wantsProtection, captureTask == nil,
              captures.count < surfaces.count else { return }
        let token = generation
        captureTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.generation == token { self.captureTask = nil } }
            do {
                let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
                guard !Task.isCancelled, self.generation == token else { return }
                let own = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
                guard !own.isEmpty else { return }
                for display in content.displays {
                    let id = display.displayID
                    guard self.surfaces[id] != nil, self.captures[id] == nil else { continue }
                    let session = UUID()
                    let config = SCStreamConfiguration()
                    config.width = max(1, display.width)
                    config.height = max(1, display.height)
                    config.minimumFrameInterval = CMTime(value: 1, timescale: (self.fullScreen || self.nearbyMonitoring || self.focusEnabled) ? 30 : (self.selectedWindow == nil && self.protectedAreas.isEmpty) ? 3 : 12)
                    config.queueDepth = 3
                    config.backgroundColor = DisplayCapture.background
                    config.shouldBeOpaque = true
                    config.showsCursor = false
                    config.capturesAudio = false
                    config.pixelFormat = kCVPixelFormatType_32BGRA
                    let filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
                    if #available(macOS 14.2, *) { filter.includeMenuBar = true }
                    let analyzer: LocalTextAnalyzer? = self.scanEnabled && !self.paused && !self.instant ? LocalTextAnalyzer(options: self.scanOptions, phrases: self.customPhrases) { [weak self] result in
                        guard let self, self.generation == token, self.captures[id]?.id == session else { return }
                        switch result {
                        case .success(let regions):
                            self.detected[id] = regions
                            self.detectedCount = self.detected.values.reduce(0) { $0 + $1.count }
                            self.render()
                        case .failure: self.notice = "Text detection is temporarily unavailable. Try pausing and resuming protection."
                        }
                    } : nil
                    self.analyzers[id] = analyzer
                    let capture = DisplayCapture(id: session, filter: filter, configuration: config,
                        radius: self.blurRadius,
                        onFrame: { [weak self] image in
                            guard let self, self.generation == token, self.captures[id]?.id == session else { return }
                            self.surfaces[id]?.setImage(image)
                            self.render()
                            if !self.ready, self.surfaces.values.allSatisfy(\.hasImage) {
                                self.ready = true
                                self.onActivityChanged?()
                            }
                        }, onFailure: { [weak self] error in
                            guard let self, self.generation == token, self.captures[id]?.id == session else { return }
                            self.failed(error)
                        }, onSample: analyzer.map { worker in { buffer in worker.offer(buffer) } })
                    self.captures[id] = capture
                    do { try await capture.start() }
                    catch {
                        guard self.generation == token, self.captures[id]?.id == session else { continue }
                        throw error
                    }
                    guard !Task.isCancelled, self.generation == token,
                          self.captures[id]?.id == session else { capture.stop(); return }
                }
            } catch {
                guard self.generation == token else { return }
                self.failed(error)
            }
        }
    }

    private func failed(_ error: Error) {
        let failure = error as NSError
        let denied = failure.domain == SCStreamErrorDomain && failure.code == SCStreamError.Code.userDeclined.rawValue
        stopCapture(clearSurfaces: false)
        captureAllowed = false
        captureUnavailable = true
        notice = denied ? "Screen access was revoked. Restore it, then click Resume." : "Capture stopped. Click Resume to retry."
        if wantsProtection {
            notice! += " The last available blur is retained until capture resumes."
            refreshGeometry()
            timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.refreshGeometry() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
        onActivityChanged?()
    }

    private func stopCapture(clearSurfaces: Bool = true) {
        generation += 1
        captureTask?.cancel(); captureTask = nil
        timer?.invalidate(); timer = nil
        for capture in captures.values { capture.stop() }
        for analyzer in analyzers.values { analyzer.cancel() }
        captures.removeAll(); analyzers.removeAll()
        if clearSurfaces {
            ready = false
            detected.removeAll()
            detectedCount = 0
            for surface in surfaces.values { surface.clear() }
        }
    }

    func shutdown() {
        areaSelectionTask?.cancel()
        areaSelector.close()
        stopCapture()
        SCContentSharingPicker.shared.remove(self)
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        for surface in surfaces.values { surface.panel.close() }
    }
}
