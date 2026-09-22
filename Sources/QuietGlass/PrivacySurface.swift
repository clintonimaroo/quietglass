//  Created by Clinton Imaro on 20/09/2026.

import AppKit

@MainActor
final class PrivacySurface {
    let panel: ShieldPanel
    private let root = CALayer()
    private let image = CALayer()
    private let windowMask = CAShapeLayer()
    private(set) var hasImage = false

    init(screen: NSScreen, includeInCaptures: Bool = false) {
        panel = ShieldPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "QuietGlass Privacy"
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.screenSaver.rawValue + 2)
        panel.collectionBehavior = [.canJoinAllSpaces, .canJoinAllApplications, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.animationBehavior = .none
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.sharingType = includeInCaptures ? .readOnly : .none
        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = root
        panel.contentView = view
        image.contentsGravity = .resize
        image.mask = windowMask
        root.addSublayer(image)
        resize(to: screen.frame)
    }

    func resize(to frame: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if panel.frame != frame { panel.setFrame(frame, display: true) }
        root.frame = CGRect(origin: .zero, size: frame.size)
        for layer in [image, windowMask] { layer.frame = root.bounds }
        CATransaction.commit()
    }

    func setImage(_ value: CGImage) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        image.contents = value
        image.backgroundColor = nil
        hasImage = true
        CATransaction.commit()
    }

    func update(windows: [CGRect], sensitive: [CGRect], fullScreen: Bool, peeking: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        windowMask.path = path(for: fullScreen ? [panel.frame] : windows + sensitive)
        image.backgroundColor = hasImage ? nil : DisplayCapture.background
        CATransaction.commit()
        if peeking || (!fullScreen && windows.isEmpty && sensitive.isEmpty) { panel.orderOut(nil) }
        else { panel.orderFrontRegardless() }
    }

    private func path(for regions: [CGRect]) -> CGPath {
        let path = CGMutablePath()
        for region in regions {
            let local = region.intersection(panel.frame).offsetBy(dx: -panel.frame.minX, dy: -panel.frame.minY)
            if !local.isNull, !local.isEmpty { path.addRect(local) }
        }
        return path
    }

    func clear() {
        panel.orderOut(nil)
        image.contents = nil
        image.backgroundColor = nil
        windowMask.path = nil
        hasImage = false
    }
}
