import AppKit
import SwiftUI

struct CameraResponsePicker: View {
    @Binding var selection: NearbyResponse

    var body: some View {
        HStack {
            Text(selection.title)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .frame(width: 176, height: 34)
        .background(ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .overlay(CameraResponseMenu(selection: $selection))
    }
}

/// Keep the custom gray label while retaining a native, keyboard-accessible
/// menu. SwiftUI's macOS Menu reduces its label to a system text/image cell.
private struct CameraResponseMenu: NSViewRepresentable {
    @Binding var selection: NearbyResponse

    func makeCoordinator() -> Coordinator { Coordinator(selection: $selection) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel("Camera response")
        button.setAccessibilityHelp("Choose a warning before blur or immediate automatic blur")
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.selection = $selection
        button.setAccessibilityValue(selection.title)
    }

    final class Coordinator: NSObject {
        var selection: Binding<NearbyResponse>
        init(selection: Binding<NearbyResponse>) { self.selection = selection }

        @MainActor @objc func open(_ sender: NSButton) {
            let menu = NSMenu()
            menu.autoenablesItems = false
            menu.minimumWidth = sender.bounds.width
            for response in NearbyResponse.allCases {
                let item = NSMenuItem(title: response.title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = response.rawValue
                item.state = selection.wrappedValue == response ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        }

        @MainActor @objc private func choose(_ sender: NSMenuItem) {
            guard let raw = sender.representedObject as? String, let response = NearbyResponse(rawValue: raw) else { return }
            selection.wrappedValue = response
        }
    }
}
