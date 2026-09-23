import XCTest
@testable import AHUTong

final class ContributorsCatalogTests: XCTestCase {
    func testCatalogMatchesAndroidContributorOrderAndContent() {
        XCTAssertEqual(ContributorsCatalog.partners.map(\.name), ["Hello~"])
        XCTAssertEqual(
            ContributorsCatalog.developers.map(\.name),
            ["s1nk", "😓😢😥😰", "\u{200B}", "堂吉诃德", "Yukon"]
        )
        XCTAssertEqual(
            ContributorsCatalog.developers[2].name.unicodeScalars.map(\.value),
            [0x200B]
        )

        XCTAssertEqual(
            ContributorsCatalog.developers.compactMap(\.qq),
            ["468766131", "330771794", "257314409", "3148336396", "605606366"]
        )
    }

    func testDeveloperContactAndAvatarStayOnAndroidQQContract() {
        let developer = ContributorsCatalog.developers[0]

        XCTAssertEqual(developer.avatarURL?.host, "q1.qlogo.cn")
        XCTAssertEqual(developer.avatarURL?.query, "b=qq&nk=468766131&s=640")
        XCTAssertEqual(developer.contactURL?.scheme, "mqqapi")
        XCTAssertTrue(developer.contactURL?.absoluteString.contains("uin=468766131") == true)
    }

    func testPartnerHasNoExternalRepositoryDestination() {
        let partner = ContributorsCatalog.partners[0]

        XCTAssertNil(partner.qq)
        XCTAssertNil(partner.avatarURL)
        XCTAssertNil(partner.contactURL)
    }
}
