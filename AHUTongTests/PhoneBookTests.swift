import XCTest
@testable import AHUTong

final class PhoneBookTests: XCTestCase {
    func testDirectoryMatchesAndroidCategoriesAndTraceableSource() {
        XCTAssertEqual(PhoneBookDirectory.sections.count, 9)
        XCTAssertEqual(PhoneBookDirectory.entries.count, 57)
        XCTAssertTrue(PhoneBookDirectory.sourceDescription.contains("2025 新生手册"))
        XCTAssertTrue(PhoneBookDirectory.sourceDescription.contains("2026 年 3 月"))
    }

    func testSearchMatchesDepartmentCategoryAndNumber() {
        XCTAssertEqual(PhoneBookDirectory.search("心理健康").map(\.name), ["心理健康教育中心"])
        XCTAssertTrue(PhoneBookDirectory.search("报警电话").contains { $0.name == "芙蓉派出所" })
        XCTAssertTrue(PhoneBookDirectory.search("65107064").contains { $0.name == "206楼" })
    }

    func testBlankSearchHasNoSyntheticResults() {
        XCTAssertTrue(PhoneBookDirectory.search("  \n").isEmpty)
    }

    func testCampusNumbersProduceSafeDialURLs() throws {
        let finance = try XCTUnwrap(
            PhoneBookDirectory.entries.first(where: { $0.name == "财务处" })
        )
        XCTAssertEqual(finance.numbers.map(\.campus), [.qingyuan, .longhe])
        XCTAssertEqual(finance.numbers[0].dialURL?.absoluteString, "tel://055163861322")
        XCTAssertNil(CampusPhoneNumber(campus: nil, localNumber: "110").dialURL)
    }
}
