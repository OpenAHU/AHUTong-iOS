import XCTest

extension XCUIElement {
    @MainActor
    func tapNativeSwitch() {
        // Form exposes the label and UISwitch as one accessibility frame.
        // The label's geometric center is not the native switch's touch target.
        coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }
}

@MainActor
extension XCUIApplication {
    /// Tool cards can exist outside the visible viewport.
    func revealTool(_ identifier: String, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let tool = buttons[identifier]
        let grid = scrollViews["tools.grid"]
        for _ in 0..<6 {
            if tool.isHittable { return tool }
            if tool.exists && tool.frame.maxY < navigationBars.firstMatch.frame.maxY {
                grid.swipeDown()
            } else {
                grid.swipeUp()
            }
        }
        XCTAssertTrue(tool.isHittable, "Expected visible tool: \(identifier)", file: file, line: line)
        return tool
    }
}
