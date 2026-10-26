import XCTest
@testable import AHUTong

final class ContributorsCatalogTests: XCTestCase {
    func testDeveloperAvatarAndCompletePersonalProfileDestination() throws {
        XCTAssertEqual(ContributorsCatalog.developers.last?.description, "iOS开发与维护")
        let developer = ContributorsCatalog.developers[0]

        XCTAssertEqual(developer.avatarURL?.host, "q1.qlogo.cn")
        XCTAssertEqual(developer.avatarURL?.query, "b=qq&nk=468766131&s=640")
        XCTAssertEqual(developer.contactURL?.scheme, "mqqapi")
        XCTAssertTrue(developer.contactURL?.absoluteString.contains("uin=468766131") == true)

        let maintainer = ContributorsCatalog.developers.first { $0.qq == "1793838025" }
        XCTAssertEqual(maintainer?.name, "zirui.xu（24级）")
        XCTAssertEqual(maintainer?.description, "功能维护、开发")
        XCTAssertEqual(maintainer?.avatarURL?.query, "b=qq&nk=1793838025&s=640")
        XCTAssertTrue(maintainer?.contactURL?.absoluteString.contains("uin=1793838025") == true)

        for entry in ContributorsCatalog.developers {
            let url = try XCTUnwrap(entry.contactURL)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            XCTAssertEqual(components.scheme, "mqqapi")
            XCTAssertEqual(components.host, "card")
            XCTAssertEqual(components.path, "/show_pslcard")
            XCTAssertEqual(
                Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) }),
                ["src_type": "internal", "version": "1", "uin": entry.qq, "card_type": "person", "source": "qrcode"]
            )
        }
    }

}
