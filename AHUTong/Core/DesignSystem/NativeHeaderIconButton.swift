import SwiftUI

struct NativeHeaderIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(.system(size: 20))
                        .frame(width: 30, height: 30)
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
                .frame(width: 44, height: 44)
            } else {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(HeaderMaterialButtonStyle())
            }
        }
        .foregroundStyle(.primary)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct HeaderMaterialButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(.regularMaterial, in: Circle())
            .overlay {
                Circle()
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.1 : 0))
                    .allowsHitTesting(false)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
            .sensoryFeedback(.impact(weight: .light, intensity: 0.55), trigger: configuration.isPressed) { _, pressed in
                pressed
            }
    }
}
