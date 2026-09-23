import XCTest
@testable import AHUTong

final class LostFoundTests: XCTestCase {
    func testReadAcceptsAndroidCampusSuccessCodeWithoutAcceptingItForMutations() {
        XCTAssertTrue(CampusLostFoundRemote.readSuccess(10_000))
        XCTAssertTrue(CampusLostFoundRemote.readSuccess(0))
        XCTAssertTrue(CampusLostFoundRemote.readSuccess(200))
        XCTAssertFalse(CampusLostFoundRemote.readSuccess(40_001))
        XCTAssertFalse(CampusLostFoundRemote.mutationSuccess(10_000))
    }

    func testRemoteDecodesSchoolReadSuccessWithoutCampusNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LostFoundFixtureURLProtocol.self]
        let client = CampusAuthenticatedClient(
            campusAPI: LostFoundFixtureAPI(),
            session: URLSession(configuration: configuration)
        )
        let remote = CampusLostFoundRemote(client: client)

        let catalog = try await remote.catalog()
        let page = try await remote.page(state: 1, page: 1, size: 20)

        XCTAssertEqual(catalog.campuses.first?.campusName, "磬苑校区")
        XCTAssertEqual(catalog.types.first?.typeName, "校园卡")
        XCTAssertEqual(page.list.first?.title, "捡到校园卡")
    }

    func testDecodesAndroidPageContractAndIgnoresUnknownFields() throws {
        let data = Data(#"{"pageNum":1,"pageSize":20,"total":1,"pages":1,"list":[{"id":"1","title":"捡到校园卡","phone":"13800000000","linkman":"同学","createtime":"2026-07-14 09:00:00","state":1,"typeid":"1","campusid":"1","num1":"博学南楼","campusName":"磬苑校区","imgs":[],"pubuser":{"idNumber":"AB220001","userName":"测试同学"},"lostType":{"typeId":"1","typeName":"校园卡"},"unknown":true}]}"#.utf8)
        let page = try JSONDecoder().decode(LostFoundPage.self, from: data)
        XCTAssertEqual(page.list.first?.lostType?.typeName, "校园卡")
        XCTAssertEqual(page.list.first?.num1, "博学南楼")
    }

    func testFiltersAcrossCampusTypeAndSearchableFields() {
        let item = DemoLostFoundRemote.fixtures[0]
        XCTAssertTrue(item.matches(query: "自习区", campusID: "1", typeID: "2"))
        XCTAssertFalse(item.matches(query: "自习区", campusID: "2", typeID: "2"))
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
        let first = await remote.page(state: 1, page: 1, size: 2)
        let second = await remote.page(state: 1, page: 2, size: 2)
        XCTAssertEqual(first.list.count, 2)
        XCTAssertEqual(Set(first.list.map(\.id)).intersection(Set(second.list.map(\.id))), Set<String>())
    }

    func testPublishBecomesVisibleOnlyAfterSuccessfulRemoteResponse() async throws {
        let remote = DemoLostFoundRemote()
        let item = try await remote.publish(validDraft())
        let page = await remote.page(state: 1, page: 1, size: 20)
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
        let owned = try await remote.publish(validDraft())
        try await remote.delete(id: owned.id)
        let page = await remote.page(state: 1, page: 1, size: 20)
        XCTAssertFalse(page.list.contains { $0.id == owned.id })
    }

    func testOwnedPostsAggregatesBothStatesIndependentlyFromVisiblePage() async throws {
        let remote = DemoLostFoundRemote()
        var lost = validDraft()
        lost.title = "我发布的失物"
        lost.state = 1
        var found = validDraft()
        found.title = "我发布的寻物"
        found.state = 2
        let first = try await remote.publish(lost)
        let second = try await remote.publish(found)

        let owned = await remote.ownedPosts(userID: "AB220001")
        XCTAssertEqual(Set(owned.map(\.id)), Set([first.id, second.id]))
        XCTAssertTrue(owned.allSatisfy { $0.pubuser?.idNumber == "AB220001" })
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

private final class LostFoundFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let object: String
        switch url.path {
        case "/lostfound/campus/all": object = #"[{"id":"1","campusName":"磬苑校区"}]"#
        case "/lostfound/type/all": object = #"[{"typeId":"1","typeName":"校园卡"}]"#
        case "/lostfound/all":
            object = #"{"pageNum":1,"pageSize":20,"total":1,"pages":1,"list":[{"id":"1","title":"捡到校园卡","state":1,"imgs":[]}]}"#
        default: object = "null"
        }
        let data = Data("{\"code\":10000,\"msg\":\"操作成功!\",\"object\":\(object)}".utf8)
        let response = HTTPURLResponse(
            url: url, statusCode: 200, httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private actor LostFoundFixtureAPI: CampusCoreAPI {
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 1 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport {
        CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: [])
    }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "" }
}
