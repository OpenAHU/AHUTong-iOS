import XCTest
@testable import AHUTong

final class ContributorsCatalogTests: XCTestCase {
    func testCatalogMatchesAndroidContributorOrderAndContent() {
        XCTAssertEqual(ContributorsCatalog.partners.map(\.name), ["Hello~"])
        XCTAssertEqual(
            ContributorsCatalog.developers.map(\.name),
            ["高玉灿（20级）", "谭哲昊（21级）", "王学雷（22级）", "徐健灿（22级）", "王    钰（22级）"]
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
