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
