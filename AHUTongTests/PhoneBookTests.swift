import XCTest
@testable import AHUTong

final class PhoneBookTests: XCTestCase {
    func testSearchMatchesDepartmentCategoryAndNumber() {
        let categoryResults = PhoneBookDirectory.search("心理健康")
        XCTAssertEqual(categoryResults.count, 5)
        XCTAssertTrue(categoryResults.contains { $0.name == "心理健康教育中心" })
        XCTAssertTrue(PhoneBookDirectory.search("报警电话").contains { $0.name == "芙蓉派出所" })
        XCTAssertTrue(PhoneBookDirectory.search("65107064").contains { $0.name == "206楼" })
    }

    func testCampusNumbersProduceSafeDialURLs() throws {
        let finance = try XCTUnwrap(
            PhoneBookDirectory.entries.first(where: { $0.name == "财务处" })
        )
        XCTAssertEqual(finance.numbers.map(\.campus), [.qingyuan, .longhe])
        XCTAssertEqual(finance.numbers[0].dialURL?.absoluteString, "tel://055163861322")
        XCTAssertEqual(finance.numbers.map(\.dialActionTitle), ["磬苑校区 0551-63861322", "龙河校区 0551-65107303"])
        XCTAssertEqual(CampusPhoneNumber(campus: nil, localNumber: "63861109").dialActionTitle, "0551-63861109")
        XCTAssertNil(CampusPhoneNumber(campus: nil, localNumber: "110").dialURL)
    }
}
