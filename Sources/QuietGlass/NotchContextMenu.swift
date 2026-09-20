// Clinton Imaro was here 20/09/2026.

import SwiftUI

enum NotchMenuAction: CaseIterable {
    case snooze, settings, resetPosition, tracking, recenter, preview, clear
}

final class NotchMenuState: ObservableObject {
    @Published var highlighted: NotchMenuAction?
}

struct NotchContextMenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var state: NotchMenuState
    let action: (NotchMenuAction) -> Void

    var body: some View {
        VStack(spacing: 2) {
            row(.snooze, "Hide for 1 hour", .clock)
            row(.settings, "Settings…", .settings)
            row(.resetPosition, "Move Notch Down", .dockBottom)
            separator
            row(.tracking, model.enabled ? "Pause tracking" : "Start tracking", model.enabled ? .pause : .play)
            row(.recenter, "Recenter", .focus, shortcut: model.shortcutLabel, enabled: model.canRecenter)
            separator
            row(.preview, model.previewing ? "Clear preview" : "Preview blur", model.previewing ? .cancel : .viewOff)
            row(.clear, "Clear screen", .view)
        }
        .padding(6)
        .frame(width: 252)
        .background(Color(white: 0.985), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.black.opacity(0.14), lineWidth: 0.75))
        .fixedSize(horizontal: false, vertical: true)
        .preferredColorScheme(.light)
    }

    private var separator: some View {
        Rectangle().fill(.black.opacity(0.09)).frame(height: 1)
            .padding(.horizontal, 8).padding(.vertical, 5)
    }

    private func row(_ item: NotchMenuAction, _ title: String, _ icon: AppIcon,
                     shortcut: String? = nil, enabled: Bool = true) -> some View {
        let highlighted = enabled && state.highlighted == item
        return Button { action(item) } label: {
            HStack(spacing: 10) {
                AppIconView(icon: icon, size: 18)
                Text(title)
                Spacer(minLength: 5)
                if let shortcut {
                    Text(shortcut).font(.system(size: 11)).opacity(highlighted ? 0.9 : 0.55)
                }
            }
            .font(.system(size: 13))
            .foregroundStyle(highlighted ? Color.white : Color(white: 0.12).opacity(enabled ? 1 : 0.35))
            .padding(.horizontal, 9)
            .frame(height: 32)
            .background(highlighted ? Color.accentColor : .clear, in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
        .onHover { inside in
            if inside, enabled { state.highlighted = item }
            else if state.highlighted == item { state.highlighted = nil }
        }
    }
}
