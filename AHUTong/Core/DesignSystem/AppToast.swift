import SwiftUI

@MainActor
final class AppToastCenter: ObservableObject {
    @Published private(set) var message: String?
    private var dismissalTask: Task<Void, Never>?

    func show(_ message: String, duration: Duration = .seconds(3)) {
        dismissalTask?.cancel()
        self.message = message
        dismissalTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.message = nil
        }
    }

    func dismiss() {
        dismissalTask?.cancel()
        dismissalTask = nil
        message = nil
    }
}

struct AppToastOverlay: View {
    @ObservedObject var center: AppToastCenter

    var body: some View {
        VStack {
            Spacer()
            if let message = center.message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(.black.opacity(0.82), in: Capsule())
                    .padding(.horizontal, 24)
                    .padding(.bottom, 28)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .accessibilityIdentifier("app.toast")
            }
        }
        .animation(.easeInOut(duration: 0.2), value: center.message)
        .allowsHitTesting(false)
    }
}
