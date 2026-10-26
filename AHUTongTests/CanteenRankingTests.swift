import XCTest
@testable import AHUTong

final class CanteenRankingTests: XCTestCase {
    func testPublicRankingRequestUsesAndroidFiltersAndCarriesNoSchoolIdentity() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CanteenFixtureProtocol.self]
        let remote = OfficialCanteenRankingRemote(session: URLSession(configuration: configuration))
        let value = try await remote.load(.init(period: .month, campus: .longhe))
        XCTAssertEqual(value.ranking?.first?.title, "未命名窗口")
        XCTAssertEqual(value.ranking?.first?.avgCentsPerTxn, 1250)
        XCTAssertEqual(value.superlatives?.lunchTopWindow?.title, "示例午餐")
        XCTAssertNil(value.superlatives?.lunchTopWindow?.rank)
        XCTAssertTrue(CanteenFixtureProtocol.validRequest)
    }

    @MainActor
    func testFilterCacheIsReusedAndManualRefreshBypassesIt() async {
        let remote = CanteenRemoteStub()
        let model = CanteenRankingViewModel(remote: remote)
        await model.load(.init())
        await model.load(.init())
        let cachedCount = await remote.count
        XCTAssertEqual(cachedCount, 1)
        await model.load(.init(), refresh: true)
        let refreshedCount = await remote.count
        XCTAssertEqual(refreshedCount, 2)
    }

    @MainActor
    func testLatePreviousCampusResultCannotOverwriteCurrentCampus() async {
        let remote = DelayedCanteenRemote()
        let model = CanteenRankingViewModel(remote: remote)
        let first = Task { await model.load(.init(campus: .qingyuan)) }
        await remote.waitForFirst()
        await model.load(.init(campus: .longhe))
        try? await remote.releaseFirst()
        await first.value
        XCTAssertEqual(model.saved?.query.campus, .longhe)
        XCTAssertEqual(model.saved?.value.startDay, "current")
    }
}

private actor CanteenRemoteStub: CanteenRankingRemote {
    private(set) var count = 0
    func load(_ query: CanteenQuery) throws -> CanteenInsights {
        count += 1
        return try JSONDecoder().decode(CanteenInsights.self, from: Data(#"{"ranking":[]}"#.utf8))
    }
}

private actor DelayedCanteenRemote: CanteenRankingRemote {
    private var first: CheckedContinuation<CanteenInsights, Error>?
    private var waiter: CheckedContinuation<Void, Never>?
    func load(_ query: CanteenQuery) async throws -> CanteenInsights {
        if query.campus == .qingyuan {
            return try await withCheckedThrowingContinuation { first = $0; waiter?.resume(); waiter = nil }
        }
        return try JSONDecoder().decode(CanteenInsights.self, from: Data(#"{"startDay":"current"}"#.utf8))
    }
    func waitForFirst() async {
        if first != nil { return }
        await withCheckedContinuation { waiter = $0 }
    }
    func releaseFirst() throws {
        let value = try JSONDecoder().decode(CanteenInsights.self, from: Data(#"{"startDay":"obsolete"}"#.utf8))
        first?.resume(returning: value); first = nil
    }
}

private final class CanteenFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var valid = false
    static var validRequest: Bool { lock.withLock { valid } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        Self.lock.withLock {
            Self.valid = url.host == "inchangejiang.cn" && url.path == "/api/canteen/insights"
                && query == ["period": "month", "limit": "50", "minTxns": "20", "canteens": CanteenCampus.longhe.canteens!]
                && request.httpMethod == "GET" && request.httpBody == nil
                && request.value(forHTTPHeaderField: "Cookie") == nil
                && request.value(forHTTPHeaderField: "Authorization") == nil
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"ranking":[{"rank":1,"terminal":"TEST001","name":null,"canteen":"梅园","txns":42,"avgCentsPerTxn":1250}],"superlatives":{"lunchTopWindow":{"terminal":"TEST001","name":"示例午餐","txns":20}}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
