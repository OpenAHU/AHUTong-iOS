import XCTest

extension XCUIElement {
    @MainActor
    func tapNativeSwitch() {
        // Form exposes the label and UISwitch as one accessibility frame.
        // The label's geometric center is not the native switch's touch target.
        coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
}
