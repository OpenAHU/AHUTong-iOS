import XCTest
@testable import AHUTong

final class ReadOnlyServicesTests: XCTestCase {
    private let page = #"<script>var model = {'program':{'nameZh':'计算机 {方案}'},'requireInfo':{'credits':161},'completionSummary':{'passedCredits':56,'takingCredits':26.5,'failedCredits':105,'completeProgress':'34.8%'},'result':{'published':false},'moduleList':[{'nameZh':'通识课程','requireInfo':{'credits':10},'completionSummary':{'passedCredits':4},'children':[{'nameZh':'艺术','courseList':[{'nameZh':'艺术\'导论','code':'TS1','credits':2,'resultType':{$type:'ResultType',$name:'TAKING'},'remark':undefined}]}]}],'student':{'idNumber':'NEVER_PERSIST'}};</script>"#

    func testProgramLiteralHandlesNestedModulesEnumsEscapesAndUndefined() throws {
        let value = try ProgramCompletionParser.parse(page)
        XCTAssertEqual(value.required, 161)
        XCTAssertEqual(value.passed, 56)
        XCTAssertEqual(value.progress, "34.8%")
        XCTAssertEqual(value.programName, "计算机 {方案}")
        XCTAssertEqual(value.modules[0].children[0].courses[0].name, "艺术'导论")
        XCTAssertEqual(value.modules[0].children[0].courses[0].statusText, "在修")
        XCTAssertNil(value.modules[0].children[0].courses[0].remark)
        let persisted = String(decoding: try JSONEncoder().encode(value), as: UTF8.self)
        XCTAssertFalse(persisted.contains("NEVER_PERSIST"))
        XCTAssertFalse(persisted.contains("idNumber"))
    }

    func testProgramProtocolChangeAndLoginAreNotDisplayedAsZeroCompletion() {
        XCTAssertThrowsError(try ProgramCompletionParser.parse("<html>cas/login</html>"))
        XCTAssertThrowsError(try ProgramCompletionParser.parse("var model = {}"))
        XCTAssertThrowsError(try ProgramCompletionParser.parse("var model = {'requireInfo':{"))
        XCTAssertThrowsError(try ProgramCompletionParser.parse("var model = {'requireInfo':alert('x')}"))
    }

    func testProgramProgressFallbackUsesServerCreditsAndUnicodeEscapes() throws {
        let value = try ProgramCompletionParser.parse(#"var model = {'program':{'nameZh':'\uD83D\uDCDA方案'},'requireInfo':{'credits':100},'completionSummary':{'passedCredits':60},'moduleList':[]}"#)
        XCTAssertEqual(value.programName, "📚方案")
        XCTAssertEqual(value.progressTitle, "学分完成率")
        XCTAssertTrue(value.progressText.contains("60"))
        XCTAssertThrowsError(try ProgramCompletionParser.parse("var model = {'requireInfo':{'credits':0},'moduleList':[]}"))
    }

    @MainActor
    func testProgramCacheWorksOfflineAndStaysScopedToAccount() async {
        let api = ProgramFixtureAPI()
        let remote = ProgramFixtureRemote()
        let store = InMemoryDataStore()
        let first = ProgramCompletionViewModel(api: api, userID: "account-a", remote: remote, store: store)
        await first.load(demo: false)
        XCTAssertNotNil(first.saved)
        await api.fail()
        await remote.fail()
        let offline = ProgramCompletionViewModel(api: api, userID: "account-a", remote: remote, store: store)
        await offline.load(demo: false)
        XCTAssertNotNil(offline.saved)
        XCTAssertNil(offline.error)
        await offline.load(demo: false, refresh: true)
        XCTAssertNotNil(offline.saved)
        XCTAssertNotNil(offline.error)
        let otherAccount = ProgramCompletionViewModel(api: api, userID: "account-b", remote: remote, store: store)
        await otherAccount.load(demo: false)
        XCTAssertNil(otherAccount.saved)
        XCTAssertNotNil(otherAccount.error)
    }

    func testProgramEntryFollowsOnlyExactAcademicInfoRedirect() async throws {
        ProgramHTTPProtocol.state.reset(location: "/student/for-std/program-completion-preview/info/123")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgramHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let remote = OfficialProgramCompletionRemote(api: ProgramFixtureAPI(), session: session)
        let value = try await remote.load(profileID: nil)
        XCTAssertEqual(value.required, 160)
        XCTAssertEqual(ProgramHTTPProtocol.state.requests().map { $0.url?.host }, ["jw.ahu.edu.cn", "jw.ahu.edu.cn"])
    }

    func testProgramEntryNeverForwardsCookiesToExternalRedirect() async {
        ProgramHTTPProtocol.state.reset(location: "https://example.invalid/info/123")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProgramHTTPProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await OfficialProgramCompletionRemote(api: ProgramFixtureAPI(), session: session).load(profileID: nil)
            XCTFail("External redirect must be rejected")
        } catch { XCTAssertEqual(error as? CampusWebError, .invalidResponse) }
        XCTAssertEqual(ProgramHTTPProtocol.state.requests().count, 1)
    }

    func testBillingWhitelistAcceptsReadOnlyPagesAndRejectsMutationsAndInvalidQueries() throws {
        let query = CardBillingContract.query(page: 1, size: 20, range: .init(from: "2024-02-01", to: "2024-02-29"), type: "2")
        let request = try YCardReadOnlyClient.makeRequest(.billPage, queryItems: query, accessToken: "fixture", cookies: [])
        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertNil(request.httpBody)
        var invalid = request
        invalid.httpMethod = "POST"
        XCTAssertThrowsError(try YCardReadOnlyRequestPolicy.authorize(invalid))
        var items = query
        items.append(.init(name: "orderId", value: "unexpected"))
        XCTAssertThrowsError(try YCardReadOnlyClient.makeRequest(.billPage, queryItems: items, accessToken: nil, cookies: []))
        XCTAssertThrowsError(try YCardReadOnlyClient.makeRequest(.billPage, queryItems: CardBillingContract.query(page: 0, size: 20, range: nil, type: nil), accessToken: nil, cookies: []))
        XCTAssertThrowsError(try YCardReadOnlyClient.makeRequest(.billPage, queryItems: CardBillingContract.query(page: 1, size: 20, range: .init(from: "2026-02-01", to: "2026-02-30"), type: nil), accessToken: nil, cookies: []))
    }

    func testBillingContractDistinguishesExpiryAndEmptyPages() throws {
        let empty = try CardBillingContract.decode(CardBillPage.self, data: Data(#"{"code":200,"data":{"records":[],"total":null,"pages":null}}"#.utf8))
        XCTAssertEqual(empty.records?.count, 0)
        XCTAssertThrowsError(try CardBillingContract.decode(CardBillPage.self, data: Data(#"{"code":401}"#.utf8))) { error in
            XCTAssertEqual(error as? YCardReadOnlyError, .credentialsUnavailable)
        }
    }

    func testAnalyticsUsesCentsDirectionAndDeduplicatesOrderID() throws {
        let rows = try CardBillingViewModel.demoRecords()
        let report = CardBillAnalytics(records: rows + rows)
        XCTAssertEqual(report.expense, 1900)
        XCTAssertEqual(report.income, 10000)
        XCTAssertEqual(report.expenseCount, 2)
        XCTAssertEqual(report.days.count, 2)
        XCTAssertEqual(report.merchants.first?.id, "榴园食堂")
    }

    func testMonthRangeUsesCampusCalendarAndLeapYears() throws {
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2024-02-29T15:59:00Z"))
        XCTAssertEqual(CardBillRange.month(containing: date), .init(from: "2024-02-01", to: "2024-02-29"))
        let march = date.addingTimeInterval(60)
        XCTAssertEqual(CardBillRange.month(containing: march), .init(from: "2024-03-01", to: "2024-03-31"))
    }

    @MainActor
    func testBillingPaginationDeduplicatesAndStopsAtLastPage() async throws {
        let remote = BillingFixture()
        let model = CardBillingViewModel(remote: remote)
        await model.refresh(range: nil, type: nil)
        XCTAssertTrue(model.hasMore)
        await model.loadMore(range: nil, type: nil)
        XCTAssertEqual(model.records.count, 3)
        XCTAssertFalse(model.hasMore)
        await model.loadMore(range: nil, type: nil)
        let calls = await remote.calls
        XCTAssertEqual(calls, [1, 2])
    }

    @MainActor
    func testStatisticsFailureDoesNotPublishPartialTotals() async {
        let model = CardBillingViewModel(remote: BillingFixture(failSecond: true))
        await model.loadAnalytics(range: nil)
        XCTAssertNil(model.analytics)
        XCTAssertNotNil(model.error)
    }

    @MainActor
    func testStatisticsFetchesEveryPage() async {
        let model = CardBillingViewModel(remote: BillingFixture())
        await model.loadAnalytics(range: nil)
        XCTAssertEqual(model.analytics?.expense, 1900)
        XCTAssertEqual(model.analytics?.income, 10000)
    }
}

private actor BillingFixture: CardBillingRemote {
    let failSecond: Bool
    private(set) var calls: [Int] = []
    init(failSecond: Bool = false) { self.failSecond = failSecond }
    func page(_ page: Int, size: Int, range: CardBillRange?, type: String?) throws -> CardBillPage {
        calls.append(page)
        if page == 2, failSecond { throw YCardReadOnlyError.unavailable }
        let rows = try CardBillingViewModel.demoRecords()
        return CardBillPage(records: page == 1 ? Array(rows.prefix(2)) : Array(rows.suffix(2)), total: 3, pages: 2)
    }
    func summary(range: CardBillRange) -> CardBillSummary { CardBillSummary(expenses: 1900, income: 10000) }
}

private actor ProgramFixtureRemote: ProgramCompletionRemote {
    private var fails = false
    func fail() { fails = true }
    func load(profileID: String?) async throws -> ProgramCompletion {
        if fails { throw CampusWebError.invalidResponse }
        return await ProgramCompletionViewModel.demo
    }
}
private actor ProgramFixtureAPI: CampusCoreAPI {
    private var fails = false
    func fail() { fails = true }
    func gradeProfiles() throws -> [CampusGradeStudentProfile] {
        if fails { throw CampusCoreError.invalidResponse }
        return [.init(id: "123", trainingType: "主修", department: "示例学院", major: "示例专业")]
    }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 7 }
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "FIXTURE" }
}

private final class ProgramHTTPProtocol: URLProtocol, @unchecked Sendable {
    static let state = ProgramHTTPState()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, location) = Self.state.record(request)
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: location.map { ["Location": $0] })!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("var model = {'requireInfo':{'credits':160},'moduleList':[]}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
private final class ProgramHTTPState: @unchecked Sendable {
    private let lock = NSLock()
    private var location = ""
    private var captured: [URLRequest] = []
    func reset(location: String) { lock.withLock { self.location = location; captured = [] } }
    func record(_ request: URLRequest) -> (Int, String?) {
        lock.withLock {
            captured.append(request)
            return request.url?.path.contains("/info/") == true ? (200, nil) : (302, location)
        }
    }
    func requests() -> [URLRequest] { lock.withLock { captured } }
}
