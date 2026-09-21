//  Created by Clinton Imaro on 20/09/2026.

import AppIntents
import Foundation

@MainActor
enum QuietGlassIntentBridge {
    static weak var model: AppModel?
    static func current() throws -> AppModel {
        guard let model else { throw QuietGlassIntentError.unavailable }
        return model
    }
}

private enum QuietGlassIntentError: LocalizedError {
    case unavailable, screenAccess, protectionUnavailable
    var errorDescription: String? {
        switch self {
        case .unavailable: return "Open QuietGlass, then try again."
        case .screenAccess: return "Allow screen access in QuietGlass Settings, then try again."
        case .protectionUnavailable: return "QuietGlass could not start protection. Open Settings to check screen access and shortcuts."
        }
    }
}

struct BlurScreenIntent: AppIntent {
    static var title: LocalizedStringResource = "Blur Screen"
    static var description = IntentDescription("Turn on QuietGlass blur across your displays.")
    static var openAppWhenRun: Bool = true

    @MainActor func perform() async throws -> some IntentResult {
        let model = try QuietGlassIntentBridge.current()
        guard model.screenPermission else { throw QuietGlassIntentError.screenAccess }
        if !model.privacy.instant { model.toggleInstantShield() }
        guard model.privacy.instant else { throw QuietGlassIntentError.protectionUnavailable }
        return .result()
    }
}

struct PauseQuietGlassIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause QuietGlass"
    static var description = IntentDescription("Clear all blur, stop nearby-person monitoring, and pause head tracking.")
    static var openAppWhenRun: Bool = true

    @MainActor func perform() async throws -> some IntentResult {
        let model = try QuietGlassIntentBridge.current()
        model.dismissShield()
        model.stop()
        return .result()
    }
}

struct FocusQuietGlassIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Focus Mode"
    static var description = IntentDescription("Keep your active window clear and blur distractions around it.")
    static var openAppWhenRun: Bool = true

    @MainActor func perform() async throws -> some IntentResult {
        let model = try QuietGlassIntentBridge.current()
        guard model.screenPermission else { throw QuietGlassIntentError.screenAccess }
        model.applyProfile(.focus)
        guard !model.privacy.paused, !model.privacy.captureUnavailable else { throw QuietGlassIntentError.protectionUnavailable }
        return .result()
    }
}

struct QuietGlassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: BlurScreenIntent(), phrases: ["Blur my screen with \(.applicationName)"], shortTitle: "Blur Screen", systemImageName: "eye.slash")
        AppShortcut(intent: PauseQuietGlassIntent(), phrases: ["Pause \(.applicationName)"], shortTitle: "Pause QuietGlass", systemImageName: "pause")
        AppShortcut(intent: FocusQuietGlassIntent(), phrases: ["Start focus with \(.applicationName)"], shortTitle: "Start Focus", systemImageName: "scope")
    }
}
