import SwiftUI

struct NativeHeaderIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    var grouped = false
    let action: () -> Void

    var body: some View {
        Group {
            if grouped {
                Button(action: action) {
                    Image(systemName: systemName)
                        .font(.system(size: 20))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
            } else if #available(iOS 26.0, *) {
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

/// Related actions share one material surface while keeping separate native buttons.
struct NativeHeaderActionGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                actions.glassEffect(.regular.interactive(), in: Capsule())
            } else {
                actions.background(.regularMaterial, in: Capsule())
            }
        }
    }

    private var actions: some View {
        ControlGroup { content }
            .controlGroupStyle(.navigation)
            .fixedSize()
            .padding(.horizontal, 4)
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
