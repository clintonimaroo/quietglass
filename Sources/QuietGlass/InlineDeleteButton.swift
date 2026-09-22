import SwiftUI

/// Native adaptation of Rare UI's lifting lid and inline confirmation panel.
/// Interaction reference: https://www.rareui.com/components/deletebutton
struct InlineDeleteButton: View {
    var itemName = "saved face"
    var confirmationHelp = "Remove the saved face from Keychain and turn off Recognize me"
    var isBusy: Bool
    var isDeleted: Bool
    var onConfirm: () -> Void
    var onFinished: () -> Void

    @State private var expanded = false
    @State private var waiting = false
    @State private var completed = false
    @State private var checkProgress: CGFloat = 0
    @FocusState private var focused: Control?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private enum Control: Hashable { case trash, confirm, cancel }
    private var animation: Animation? { reduceMotion ? nil : .spring(response: 0.36, dampingFraction: 0.78) }

    var body: some View {
        HStack(spacing: 0) {
            Button {
                if expanded { cancel() }
                else { withAnimation(animation) { expanded = true } }
            } label: {
                ZStack {
                    if waiting {
                        ProgressView().controlSize(.small).scaleEffect(0.65)
                    } else if completed {
                        DeleteCompletionMark().trim(from: 0, to: checkProgress)
                            .stroke(Color.green, style: StrokeStyle(lineWidth: 1.7, lineCap: .round, lineJoin: .round))
                            .frame(width: 15, height: 15)
                    } else {
                        DeleteBinIcon(open: expanded)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 34, height: 34)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .focused($focused, equals: .trash)
            .disabled(waiting || completed)
            .accessibilityLabel(completed ? "Deleted \(itemName)" : expanded ? "Cancel deleting \(itemName)" : "Delete \(itemName)")
            .accessibilityValue(expanded ? "Confirmation open" : "")
            .help(expanded ? "Cancel deletion" : "Delete \(itemName)")

            if expanded {
                HStack(spacing: 4) {
                    confirmationButton("checkmark", label: "Confirm deleting \(itemName)", control: .confirm,
                                       color: Color(red: 0.94, green: 0.68, blue: 0.91)) {
                        guard !waiting, !isBusy else { return }
                        waiting = true
                        focused = nil
                        withAnimation(animation) { expanded = false }
                        onConfirm()
                    }
                    .help(confirmationHelp)
                    confirmationButton("xmark", label: "Cancel deletion", control: .cancel, color: .secondary, action: cancel)
                        .help("Keep your \(itemName)")
                }
                .padding(5)
                .background(Color.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 10))
                .transition(reduceMotion ? .identity : .move(edge: .leading).combined(with: .opacity))
            }
        }
        .background(ControlAppearance.fill, in: RoundedRectangle(cornerRadius: 10))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .fixedSize()
        .disabled(isBusy)
        .onExitCommand { cancel() }
        .onChange(of: isBusy) { _, busy in
            guard waiting, !busy else { return }
            waiting = false
            if isDeleted {
                completed = true
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.25)) { checkProgress = 1 }
            } else {
                onFinished()
            }
        }
        .task(id: completed) {
            guard completed else { return }
            do { try await Task.sleep(for: .milliseconds(900)) }
            catch { return }
            onFinished()
        }
    }

    private func confirmationButton(_ symbol: String, label: String, control: Control, color: Color,
                                    action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 24, height: 24)
                .background(ControlAppearance.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .focused($focused, equals: control)
        .accessibilityLabel(label)
    }

    private func cancel() {
        guard expanded, !waiting else { return }
        withAnimation(animation) { expanded = false }
        focused = .trash
    }
}

private struct DeleteBinIcon: View {
    var open: Bool
    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 4, y: 6))
                path.addLine(to: CGPoint(x: 4.7, y: 15))
                path.addQuadCurve(to: CGPoint(x: 6.1, y: 16.2), control: CGPoint(x: 4.8, y: 16.2))
                path.addLine(to: CGPoint(x: 12.9, y: 16.2))
                path.addQuadCurve(to: CGPoint(x: 14.3, y: 15), control: CGPoint(x: 14.2, y: 16.2))
                path.addLine(to: CGPoint(x: 15, y: 6))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            Path { path in
                path.move(to: CGPoint(x: 3, y: 4.4))
                path.addLine(to: CGPoint(x: 16, y: 4.4))
                path.move(to: CGPoint(x: 7, y: 4.4))
                path.addLine(to: CGPoint(x: 7, y: 2.3))
                path.addLine(to: CGPoint(x: 12, y: 2.3))
                path.addLine(to: CGPoint(x: 12, y: 4.4))
            }
            .stroke(style: StrokeStyle(lineWidth: 1.3, lineCap: .round, lineJoin: .round))
            .rotationEffect(.degrees(open ? -30 : 0), anchor: UnitPoint(x: 0.2, y: 0.24))
            .offset(x: open ? -0.5 : 0, y: open ? -0.5 : 0)
        }
        .frame(width: 19, height: 19)
    }
}

private struct DeleteCompletionMark: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.width * 0.12, y: rect.height * 0.52))
            path.addLine(to: CGPoint(x: rect.width * 0.40, y: rect.height * 0.80))
            path.addLine(to: CGPoint(x: rect.width * 0.90, y: rect.height * 0.22))
        }
    }
}
