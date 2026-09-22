import AppKit
import ShieldCore

enum DockGeometry {
    static func visibleTop(on screen: NSScreen) -> CGFloat {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]],
              let desktopTop = NSScreen.screens.first?.frame.maxY else {
            return screen.visibleFrame.minY
        }
        let frames: [CGRect] = windows.compactMap { window in
            guard (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value == dock.processIdentifier,
                  (window[kCGWindowLayer as String] as? NSNumber)?.intValue == Int(CGWindowLevelForKey(.dockWindow)),
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { return nil }
            return CGRect(x: bounds.minX, y: desktopTop - bounds.maxY, width: bounds.width, height: bounds.height)
        }
        return NotchDocking.visibleDockTop(in: screen.frame, visibleFrame: screen.visibleFrame, dockFrames: frames)
    }
}
