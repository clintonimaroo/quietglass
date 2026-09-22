import SwiftUI
import ShieldCore

/// Native adaptation of Rare UI's joined-pill / split-segment duration picker.
/// Interaction reference: https://www.rareui.com/components/durationpicker
struct WarningDurationPicker: View {
    @Binding var duration: TimeInterval
    @State private var editing = false
    @State private var hours = "0"
    @State private var minutes = "2"
    @State private var correction: String?
    @State private var shake = 0.0
    @FocusState private var focused: Field?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Field: Hashable { case hours, minutes }
    private let accent = Color(red: 0.94, green: 0.68, blue: 0.91)
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78) }

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            HStack(spacing: editing ? 6 : 0) {
                segment(.hours, text: $hours, label: "Hr.", width: 67)
                segment(.minutes, text: $minutes, label: "Min.", width: 75)
                Button {
                    if editing { confirm() }
                    else {
                        loadValue()
                        withAnimation(animation) { editing = true }
                        focused = .hours
                    }
                } label: {
                    Image(systemName: editing ? "checkmark" : "pencil")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(editing ? accent : .secondary)
                        .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                        .frame(width: 34, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(editing ? ControlAppearance.fill : .clear, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(editing ? "Save warning duration" : "Edit warning duration")
                .help(editing ? "Save duration" : "Change how long to warn before blurring")
            }
            .background(editing ? .clear : ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 10))
            .modifier(DurationCorrectionShake(amount: shake))
            .fixedSize()
            .onSubmit { confirm() }
            .onExitCommand {
                guard editing else { return }
                focused = nil
                withAnimation(animation) { editing = false }
                correction = nil
            }
            if let correction {
                Text(correction).font(.system(size: 10)).foregroundStyle(.secondary)
                    .accessibilityAddTraits(.updatesFrequently)
            }
        }
        .onAppear { loadValue() }
        .onChange(of: duration) { _, _ in if !editing { loadValue() } }
    }

    private func segment(_ field: Field, text: Binding<String>, label: String, width: CGFloat) -> some View {
        HStack(spacing: 5) {
            if editing {
                TextField("0", text: text)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .focused($focused, equals: field)
                    .accessibilityLabel(field == .hours ? "Warning delay hours" : "Warning delay minutes")
                    .onChange(of: text.wrappedValue) { _, value in
                        let digits = value.filter { $0.isASCII && $0.isNumber }
                        let limit = field == .hours ? 24 : 59
                        let number = digits.isEmpty ? 0 : (Int(digits) ?? limit + 1)
                        if number > limit {
                            text.wrappedValue = String(limit)
                            corrected("Maximum \(limit) \(field == .hours ? "hours" : "minutes")")
                        } else if digits != value { text.wrappedValue = digits }
                    }
                    .frame(width: 22)
            } else {
                Text(field == .hours ? String(Int(duration) / 3600) : String(Int(duration) / 60 % 60))
                    .frame(minWidth: 12, alignment: .trailing)
            }
            Text(label).foregroundStyle(.secondary)
        }
        .font(.system(size: 13, weight: .medium)).monospacedDigit()
        .frame(width: width, height: 34)
        .background(editing ? ControlAppearance.fill : .clear, in: RoundedRectangle(cornerRadius: 10))
    }

    private func loadValue() {
        hours = String(Int(duration) / 3600)
        minutes = String(Int(duration) / 60 % 60)
        correction = nil
    }

    private func corrected(_ message: String) {
        correction = message
        withAnimation(reduceMotion ? nil : .linear(duration: 0.3)) { shake += 1 }
    }

    private func confirm() {
        guard editing else { return }
        let raw = Double(Int(hours) ?? 0) * 3600 + Double(Int(minutes) ?? 0) * 60
        let value = NearbyWarningPolicy.normalizedDelay(raw)
        if raw != value {
            hours = String(Int(value) / 3600)
            minutes = String(Int(value) / 60 % 60)
            corrected(raw < 60 ? "Use at least 1 minute" : "Maximum 24 hours")
            return
        }
        duration = value
        focused = nil
        correction = nil
        withAnimation(animation) { editing = false }
    }
}

private struct DurationCorrectionShake: GeometryEffect {
    var amount: Double
    var animatableData: Double {
        get { amount }
        set { amount = newValue }
    }
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(amount * .pi * 6) * 3, y: 0))
    }
}
