import SwiftUI

enum ControlAppearance {
    // Opaque so the reference gray stays identical on cards, sheets, and popovers.
    static let fill = Color(red: 50 / 255, green: 50 / 255, blue: 50 / 255)
    static let hoverFill = Color(red: 57 / 255, green: 57 / 255, blue: 57 / 255)
    static let pressedFill = Color(red: 64 / 255, green: 64 / 255, blue: 64 / 255)
}

struct QuietGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlSize) private var controlSize
    @State private var hovering = false

    private var compact: Bool { controlSize == .small || controlSize == .mini }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 11 : 13))
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, compact ? 10 : 12)
            .padding(.vertical, compact ? 5 : 7)
            .background(configuration.isPressed ? ControlAppearance.pressedFill
                        : hovering && isEnabled ? ControlAppearance.hoverFill : ControlAppearance.fill,
                        in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
            .opacity(isEnabled ? 1 : 0.4)
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: hovering)
    }
}
