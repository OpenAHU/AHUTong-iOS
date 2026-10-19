import XCTest
@testable import AHUTong

final class ContributorsCatalogTests: XCTestCase {
    func testCatalogPreservesAliasesAndIncludesMaintainersWithTheirCohorts() {
        XCTAssertEqual(ContributorsCatalog.partners.map(\.name), ["Hello~"])
        XCTAssertEqual(
            ContributorsCatalog.developers.map(\.name),
            ["s1nk（20级）", "😓😢😥😰（21级）", "\u{200B}（22级）", "堂吉诃德（22级）", "Yukon（22级）", "zirui.xu（24级）", "MuxYang（25级）", "InChange-Jiang（25级）", "Himekawa（24级）"]
        )
        XCTAssertEqual(
            ContributorsCatalog.developers[2].name.unicodeScalars.first?.value,
            0x200B
        )

        XCTAssertEqual(
            ContributorsCatalog.developers.compactMap(\.qq),
            ["468766131", "330771794", "257314409", "3148336396", "605606366", "1793838025", "32142587", "2719904894", "1705945565"]
        )
    }

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

    func testPartnerHasNoExternalRepositoryDestination() {
        let partner = ContributorsCatalog.partners[0]

        XCTAssertNil(partner.qq)
        XCTAssertNil(partner.avatarURL)
        XCTAssertNil(partner.contactURL)
    }
}
