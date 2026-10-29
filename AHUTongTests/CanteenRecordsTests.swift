import XCTest
@testable import AHUTong

final class CanteenRecordsTests: XCTestCase {
    func testContributionUsesOnlyEligibleMealsAndExplicitDeidentifiedFields() throws {
        let rows = try bills([
            row(id: "keep", time: "2026-10-27T11:30", merchant: "北二区食堂二楼"),
            row(id: "refund", time: "2026-10-27 12:00:00", type: "1"),
            row(id: "breakfast", time: "2026-10-27 09:00:00"),
            row(id: "lunch-end", time: "2026-10-27 14:00:00"),
            row(id: "late", time: "2026-10-27 22:30:00"),
            row(id: "bad-date", time: "2026-02-30 11:30:00"),
            row(id: "over-limit", time: "2026-10-27 11:30:00", amount: 50_001),
            row(id: "retail", time: "2026-10-27 11:30:00", merchant: "校园超市"),
            row(id: "old", time: "2026-09-27 11:30:00"),
            row(id: "future", time: "2026-10-28 11:30:00")
        ])
        let now = try XCTUnwrap(CanteenFootprint.formatter().date(from: "2026-10-27 23:00:00"))
        let payload = CanteenFootprint(records: rows + rows).contribution(now: now)
        XCTAssertEqual(payload.count, 1)
        let data = try JSONEncoder().encode(payload)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(Set(json[0].keys), ["terminal", "ts", "amountCents", "canteen", "floor"])
        XCTAssertEqual(json[0]["ts"] as? String, "2026-10-27 11:30:00")
        XCTAssertEqual(json[0]["canteen"] as? String, "榴园")
        XCTAssertEqual(json[0]["floor"] as? String, "二楼")
        XCTAssertEqual(json[0]["amountCents"] as? Int, 1250)
    }

    func testPersonalMealsMergeWithinFiveMinutesWithoutCombiningDifferentWindows() throws {
        let rows = try bills([
            row(id: "a", time: "2026-10-27T11:30:00", amount: 1000),
            row(id: "b", time: "2026-10-27 11:35:00", amount: 200),
            row(id: "c", time: "2026-10-27 11:35:01", amount: 500),
            row(id: "d", time: "2026-10-27 11:31:00", amount: 900, terminal: "POS-2")
        ])
        let footprint = CanteenFootprint(records: rows + rows)
        XCTAssertEqual(footprint.meals.count, 3)
        XCTAssertEqual(footprint.total, 2600)
        XCTAssertEqual(footprint.windowCount, 2)
        XCTAssertEqual(footprint.meals.first { $0.date == CanteenFootprint.formatter().date(from: "2026-10-27 11:30:00") }?.cents, 1200)
        XCTAssertTrue(footprint.filtered(canteens: ["梅园"]).isEmpty)
    }

    func testContributionStopsAtFailedBatchAndReportsOnlyConfirmedProgress() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ContributionProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let remote = OfficialCanteenCommunityRemote(session: session, writeKey: "fixture-client-key")
        let transactions = (0..<801).map { CanteenTransaction(terminal: "POS-\($0)", ts: "2026-10-27 11:30:00", amountCents: 1000, canteen: "榴园", floor: nil) }
        do { try await remote.upload(transactions); XCTFail("Second batch must fail") }
        catch let failure as CanteenContributionFailure {
            XCTAssertEqual(failure.sent, 400)
            XCTAssertEqual(failure.total, 801)
            XCTAssertTrue(failure.reason.contains("稍后再试"))
        }
    }

    private func row(id: String, time: String, amount: Int = 1250, type: String = "2", merchant: String = "北二区食堂一楼", terminal: String = "POS-1") -> [String: Any] {
        ["orderId": id, "effectdateStr": time, "tranamt": amount, "typeFrom": type, "resume": merchant, "locationName": terminal]
    }
    private func bills(_ rows: [[String: Any]]) throws -> [CardBill] {
        try JSONDecoder().decode([CardBill].self, from: JSONSerialization.data(withJSONObject: rows))
    }
}

private final class ContributionProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        XCTAssertEqual(request.url?.absoluteString, "https://inchangejiang.cn/api/canteen/txns")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Api-Key"), "fixture-client-key")
        XCTAssertNil(request.value(forHTTPHeaderField: "Cookie"))
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        var data = request.httpBody ?? Data()
        if let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }
                data.append(contentsOf: buffer.prefix(count))
            }
        }
        let json = try! JSONSerialization.jsonObject(with: data) as! [String: [[String: Any]]]
        let rows = json["txns"]!
        XCTAssertEqual(rows.count, 400)
        let terminal = rows[0]["terminal"] as! String
        XCTAssertTrue(terminal == "POS-0" || terminal == "POS-400", "A failed batch must not be retried or followed by another batch")
        let code = terminal == "POS-0" ? 204 : 429
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
