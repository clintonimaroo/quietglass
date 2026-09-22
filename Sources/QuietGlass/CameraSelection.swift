import AVFoundation
import SwiftUI

struct CameraChoice: Identifiable, Equatable {
    let id: String
    let name: String
}

enum CameraSelection {
    static let preferenceKey = "nearbyCameraID"

    static func devices() -> [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external, .continuityCamera],
                                         mediaType: .video, position: .unspecified).devices
    }

    static func device(id: String?) -> AVCaptureDevice? {
        guard let id, !id.isEmpty else { return AVCaptureDevice.default(for: .video) }
        // A missing selected camera must not silently switch the user's coverage.
        return devices().first { $0.uniqueID == id }
    }
}

struct CameraChoicePicker: View {
    let cameras: [CameraChoice]
    let selection: String
    let select: (String) -> Void
    let refresh: () -> Void

    private var title: String {
        selection.isEmpty ? "Automatic" : cameras.first { $0.id == selection }?.name ?? "Selected camera unavailable"
    }

    var body: some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12).frame(width: 176, height: 34)
        .background(ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .overlay(CameraChoiceMenu(cameras: cameras, selection: selection, title: title, select: select, refresh: refresh))
        .help(title)
    }
}

private struct CameraChoiceMenu: NSViewRepresentable {
    let cameras: [CameraChoice]
    let selection: String
    let title: String
    let select: (String) -> Void
    let refresh: () -> Void
    @Environment(\.isEnabled) private var enabled

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel("Camera")
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.value = self
        button.isEnabled = enabled
        button.setAccessibilityValue(title)
    }

    final class Coordinator: NSObject {
        var value: CameraChoiceMenu?
        @MainActor @objc func open(_ sender: NSButton) {
            guard let value else { return }
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.minimumWidth = sender.bounds.width
            for camera in [CameraChoice(id: "", name: "Automatic")] + value.cameras {
                let item = NSMenuItem(title: camera.name, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = camera.id
                item.state = camera.id == value.selection ? .on : .off
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let refresh = NSMenuItem(title: "Refresh cameras", action: #selector(refreshCameras(_:)), keyEquivalent: "")
            refresh.target = self; menu.addItem(refresh)
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        }
        @MainActor @objc private func choose(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            value?.select(id)
        }
        @MainActor @objc private func refreshCameras(_ sender: NSMenuItem) { value?.refresh() }
    }
}
