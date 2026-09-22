import AppKit
import SwiftUI

/// The same filled menu appearance as the existing camera selector.
struct TrackingChoicePicker: View {
    let label: String
    let options: [(id: String, title: String)]
    let selection: String
    let select: (String) -> Void
    private var title: String { options.first { $0.id == selection }?.title ?? "" }
    var body: some View {
        HStack {
            Text(title).lineLimit(1)
            Spacer(minLength: 8)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 12).frame(width: 176, height: 34)
        .background(ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityHidden(true)
        .overlay(TrackingChoiceMenu(label: label, options: options, selection: selection, title: title, select: select))
    }
}

private struct TrackingChoiceMenu: NSViewRepresentable {
    let label: String
    let options: [(id: String, title: String)]
    let selection: String
    let title: String
    let select: (String) -> Void
    @Environment(\.isEnabled) private var enabled
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "", target: context.coordinator, action: #selector(Coordinator.open(_:)))
        button.isTransparent = true
        button.setButtonType(.momentaryPushIn)
        button.setAccessibilityLabel(label)
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.value = self
        button.isEnabled = enabled
        button.setAccessibilityValue(title)
    }
    final class Coordinator: NSObject {
        var value: TrackingChoiceMenu?
        @MainActor @objc func open(_ sender: NSButton) {
            guard let value else { return }
            let menu = NSMenu(); menu.autoenablesItems = false; menu.minimumWidth = sender.bounds.width
            for choice in value.options {
                let item = NSMenuItem(title: choice.title, action: #selector(choose(_:)), keyEquivalent: "")
                item.target = self; item.representedObject = choice.id
                item.state = choice.id == value.selection ? .on : .off
                menu.addItem(item)
            }
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: -4), in: sender)
        }
        @MainActor @objc private func choose(_ sender: NSMenuItem) {
            guard let id = sender.representedObject as? String else { return }
            value?.select(id)
        }
    }
}
