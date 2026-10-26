import XCTest
@testable import AHUTong

final class AttendanceTests: XCTestCase {
    override func setUp() {
        super.setUp()
        AttendanceFixtureProtocol.reset()
    }

    func testAbsenceUsesActualAccountDateAndSectionsRatherThanSemesterTemplate() throws {
        let page = try AttendanceContract.parsePage(Data(#"{"code":200,"data":{"totalCount":1,"list":[{"subjectBean":{"sName":"高等数学","sCode":"M001"},"accountBean":{"checkdate":"2026-10-23","startJc":3,"endJc":4},"accountDetailEntity":{"timingdate_startdate":"2026-01-01"},"classWaterBean":{"status":3,"operdate":""},"buildBean":{"name":"博学楼"},"isSupportAppeal":"1"}]}}"#.utf8))
        let record = try XCTUnwrap(page.records.first)
        XCTAssertEqual(record.classDate, "2026-10-23")
        XCTAssertEqual(record.section, "第3-4节")
        XCTAssertEqual(record.room, "博学楼")
        XCTAssertEqual(record.statusText, "缺勤")
        XCTAssertTrue(record.canAppeal)
        XCTAssertEqual(record.punchTime, "")
    }

    func testPortalRejectsExternalRedirectBeforeSendingSchoolCookies() throws {
        let base = URL(string: "https://adwmh.ahu.edu.cn/commapp/myapp")!
        for raw in ["https://one.ahu.edu.cn.attacker.test/cas", "https://one.ahu.edu.cn:8443/cas", "https://user@one.ahu.edu.cn/cas", "file:///tmp/private"] {
            XCTAssertThrowsError(try AttendanceContract.portalURL(raw, relativeTo: base))
        }
        XCTAssertNil(AttendanceContract.token(in: URL(string: "https://attacker.test/?token=must-not-use")!))
    }

    func testSchoolSSOParsesScriptCallbackAndRenewsRejectedAttendanceTokenOnce() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AttendanceFixtureProtocol.self]
        let api = AttendanceAPIStub()
        let remote = OfficialAttendanceRemote(api: api, session: URLSession(configuration: configuration))
        let page = try await remote.page(status: 3, page: 2)
        XCTAssertEqual(page.totalCount, 0)
        let calls = await api.appsCount()
        XCTAssertEqual(calls, 4)
        XCTAssertEqual(AttendanceFixtureProtocol.pageRequests, 2)
        XCTAssertTrue(AttendanceFixtureProtocol.validRequest)
    }
}

private actor AttendanceAPIStub: CampusCoreAPI {
    private var count = 0
    func initialize(cookiesJSON: String) {}
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { count += 1; return "[]" }
    func appsCount() -> Int { count }
    func persistSessionCookies() {}
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 1 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { .init(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 0 }
    func cardQRCode() -> String { "" }
}

private final class AttendanceFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var count = 0
    nonisolated(unsafe) private static var valid = true
    static func reset() { lock.withLock { count = 0; valid = true } }
    static var pageRequests: Int { lock.withLock { count } }
    static var validRequest: Bool { lock.withLock { valid } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var status = 200
        let body: String
        if url.path == "/commapp/myapp" {
            body = #"{"code":10000,"object":[{"items":[{"id":2035,"lk":"http://one.ahu.edu.cn/oauth"}]}]}"#
        } else if url.path == "/oauth" {
            body = #"<script>location.href='https://kqcard.ahu.edu.cn/#/login?token=fixture-jwt';</script>"#
        } else {
            let index = Self.lock.withLock { () -> Int in
                Self.count += 1
                let payload = request.httpBody ?? Self.body(request)
                let object = (try? JSONSerialization.jsonObject(with: payload)) as? [String: Any]
                Self.valid = Self.valid && request.httpMethod == "POST"
                    && request.value(forHTTPHeaderField: "synjones-auth") == "bearer fixture-jwt"
                    && object?["current"] as? Int == 2
                    && (object?["classWaterBean"] as? [String: Int])?["status"] == 3
                return Self.count
            }
            status = index == 1 ? 401 : 200
            body = #"{"code":200,"data":{"totalCount":0,"list":[]}}"#
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: [:])!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) -> Data {
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { return data }; data.append(contentsOf: buffer[..<n]) }
    }
}
