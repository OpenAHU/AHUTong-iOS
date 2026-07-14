import XCTest
@testable import AHUTong

final class LostFoundTests: XCTestCase {
    func testDecodesAndroidPageContractAndIgnoresUnknownFields() throws {
        let data = Data(#"{"pageNum":1,"pageSize":20,"total":1,"pages":1,"list":[{"id":"1","title":"捡到校园卡","phone":"13800000000","linkman":"同学","createtime":"2026-07-14 09:00:00","state":1,"typeid":"1","campusid":"1","num1":"博学南楼","campusName":"磬苑校区","imgs":[],"pubuser":{"idNumber":"AB220001","userName":"测试同学"},"lostType":{"typeId":"1","typeName":"校园卡"},"unknown":true}]}"#.utf8)
        let page = try JSONDecoder().decode(LostFoundPage.self, from: data)
        XCTAssertEqual(page.list.first?.lostType?.typeName, "校园卡")
        XCTAssertEqual(page.list.first?.num1, "博学南楼")
    }

    func testFiltersAcrossCampusTypeAndSearchableFields() {
        let item = DemoLostFoundRemote.fixtures[0]
        XCTAssertTrue(item.matches(query: "值班室", campusID: "1", typeID: "1"))
        XCTAssertFalse(item.matches(query: "值班室", campusID: "2", typeID: "1"))
        XCTAssertFalse(item.matches(query: "耳机", campusID: nil, typeID: nil))
    }

    func testPublishDraftRejectsMissingFieldsAndShortPhone() {
        XCTAssertEqual(LostFoundPublishDraft().validationMessage, "请填写完整信息")
        var draft = validDraft()
        draft.phone = "123"
        XCTAssertEqual(draft.validationMessage, "请填写有效联系电话")
        draft.phone = "13800000000"
        XCTAssertNil(draft.validationMessage)
    }

    func testDemoRemotePaginatesWithoutDuplicates() async throws {
        let remote = DemoLostFoundRemote()
        let first = try await remote.page(state: 1, page: 1, size: 2)
        let second = try await remote.page(state: 1, page: 2, size: 2)
        XCTAssertEqual(first.list.count, 2)
        XCTAssertEqual(Set(first.list.map(\.id)).intersection(Set(second.list.map(\.id))), Set<String>())
    }

    func testPublishBecomesVisibleOnlyAfterSuccessfulRemoteResponse() async throws {
        let remote = DemoLostFoundRemote()
        let item = try await remote.publish(validDraft())
        let page = try await remote.page(state: 1, page: 1, size: 20)
        XCTAssertEqual(item.pubuser?.idNumber, "AB220001")
        XCTAssertEqual(page.list.first?.id, item.id)
    }

    func testDeleteRejectsForeignPostAndRemovesOwnedPost() async throws {
        let remote = DemoLostFoundRemote()
        do {
            try await remote.delete(id: "demo-lost-1")
            XCTFail("Expected ownership rejection")
        } catch {
            XCTAssertEqual(error.localizedDescription, "只能删除自己发布的帖子")
        }
        try await remote.delete(id: "demo-owned-1")
        let page = try await remote.page(state: 1, page: 1, size: 20)
        XCTAssertFalse(page.list.contains { $0.id == "demo-owned-1" })
    }

    private func validDraft() -> LostFoundPublishDraft {
        var draft = LostFoundPublishDraft()
        draft.contact = "测试同学"
        draft.phone = "13800000000"
        draft.title = "捡到校园卡"
        draft.campusID = "1"
        draft.typeID = "1"
        return draft
    }
}
