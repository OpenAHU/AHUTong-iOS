import SwiftUI

private struct NativeNumericTransition<Value: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let value: Value
    let countsDown: Bool

    func body(content: Content) -> some View {
        content
            .monospacedDigit()
            .contentTransition(reduceMotion ? .identity : .numericText(countsDown: countsDown))
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: value)
    }
}

extension View {
    func nativeNumericTransition<Value: Equatable>(value: Value, countsDown: Bool = false) -> some View {
        modifier(NativeNumericTransition(value: value, countsDown: countsDown))
    }
}

/// Animate each page's arrival without replacing the system tab controller or its delegate.
struct TabPageEntrance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion || isVisible ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.22)) {
                    isVisible = true
                }
            }
            .onDisappear { isVisible = false }
    }
}
