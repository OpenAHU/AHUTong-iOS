import XCTest
@testable import AHUTong

final class LoadableStateTests: XCTestCase {
    func testLoadingStateIsReported() {
        let state = LoadableState<String>.loading

        XCTAssertTrue(state.isLoading)
        XCTAssertNil(state.value)
    }

    func testLoadedStateExposesValue() {
        let state = LoadableState.loaded("course")

        XCTAssertFalse(state.isLoading)
        XCTAssertEqual(state.value, "course")
    }

    func testErrorsAreEquatableForDeterministicRendering() {
        let error = AppErrorState(message: "网络不可用")

        XCTAssertEqual(
            LoadableState<String>.failed(error),
            LoadableState<String>.failed(error)
        )
    }
}
