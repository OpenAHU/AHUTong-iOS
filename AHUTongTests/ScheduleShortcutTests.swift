import AppIntents
import Foundation
import XCTest
@testable import AHUTong

@MainActor
final class ScheduleShortcutTests: XCTestCase {
    func testTeachingWeekParsingNeverDefaultsMissingOrUnrelatedDataToWeekOne() {
        for body in ["null", "{}", "true", "1.5", #"{"code":1}"#, #"{"data":null,"status":200}"#, "broken"] {
            XCTAssertThrowsError(try TeachingWeekParser.parse(Data(body.utf8)), body)
        }
    }

    func testTeachingWeekParserSupportsKnownResponseShapes() throws {
        for (body, expected) in [("6", 6), (#"{"currentWeek":"3"}"#, 3), (#"{"data":{"teachWeek":4},"code":200}"#, 4)] {
            XCTAssertEqual(try TeachingWeekParser.parse(Data(body.utf8)), expected)
        }
    }

    func testSpecifiedDateUsesExactWeekIndexesAndSundayMondayBoundary() {
        let snapshot = snapshot(courses: [course(weeks: [1, 3]), course(day: 7, id: "sunday")])
        XCTAssertEqual(query(snapshot, "2026-09-13").status, .courses)
        XCTAssertEqual(query(snapshot, "2026-09-14").status, .noClasses)
        XCTAssertEqual(query(snapshot, "2026-09-21").status, .courses)
        XCTAssertTrue(query(snapshot, "2026-09-21").text.contains("第3周"))
    }

    func testEmptySyncedScheduleIsDifferentFromMissingData() {
        XCTAssertEqual(query(snapshot(courses: []), "2026-09-14").status, .noClasses)
        let missing = query(nil, "2026-09-14")
        XCTAssertEqual(missing.status, .noData)
        XCTAssertFalse(missing.text.contains("当天没有课程"))
    }

    func testDatesOutsideSemesterAreNeverClampedToFirstOrLastWeek() {
        let value = snapshot(courses: [course()])
        XCTAssertEqual(query(value, "2026-09-06").status, .outsideSemester)
        XCTAssertEqual(query(value, "2027-01-24").status, .noClasses) // last day of week 20
        XCTAssertEqual(query(value, "2027-01-25").status, .outsideSemester)
    }

    func testCoursesAreOrderedDeduplicatedAndMissingLocationIsExplicit() {
        let morning = course(id: "early", period: 1, location: "")
        let later = course(id: "late", period: 6)
        let value = query(snapshot(courses: [later, morning, morning]), "2026-09-14")
        XCTAssertTrue(value.text.contains("共2门课程"))
        XCTAssertTrue(value.text.contains("地点待公布"))
        XCTAssertLessThan(value.text.range(of: "第1—2节")!.lowerBound, value.text.range(of: "第6—7节")!.lowerBound)
        XCTAssertTrue(value.text.contains("上次同步"))
    }

    func testMalformedCoursesAreNotReportedAsAnEmptyDay() {
        let malformed = ShortcutScheduleSnapshot(
            semester: semester, semesterStart: day("2026-09-07"), updatedAt: nil,
            courses: [course(day: 0)]
        )
        XCTAssertEqual(query(malformed, "2026-09-14").status, .noData)
        XCTAssertNil(ShortcutScheduleSnapshot.make(
            semester: semester, courses: [], currentWeek: 0,
            referenceDate: day("2026-09-14"), updatedAt: nil
        ))
    }

    func testSelectedCalendarDayIsPreservedWhenUserIsAbroad() {
        var overseas = Calendar(identifier: .gregorian)
        overseas.timeZone = TimeZone(secondsFromGMT: 14 * 3600)!
        let selected = overseas.date(from: DateComponents(year: 2026, month: 9, day: 14))!
        let campusDay = CampusScheduleCalendar.selectedDay(selected, inputCalendar: overseas)!
        XCTAssertEqual(campusDay, day("2026-09-14"))
        XCTAssertEqual(query(snapshot(courses: [course()]), "2026-09-14").status, .courses)
    }

    func testNonGregorianDeviceCalendarDoesNotChangeTheSelectedDay() {
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = CampusScheduleCalendar.calendar.timeZone
        XCTAssertEqual(
            CampusScheduleCalendar.selectedDay(day("2026-09-14"), inputCalendar: buddhist),
            day("2026-09-14")
        )
    }

    func testMissingWeekDoesNotInventAnAnchorAndOfflineRefreshKeepsKnownAnchor() async throws {
        let store = ScheduleShortcutStore(userID: "A", dataStore: InMemoryDataStore())
        try await store.record(courses: [course()], semester: semester, currentWeek: nil, source: .remote)
        let missing = try await store.load()
        XCTAssertNil(missing)

        try await store.record(
            courses: [course()], semester: semester, currentWeek: 2,
            source: .remote, at: day("2026-09-20")
        )
        try await store.record(
            courses: [course()], semester: semester, currentWeek: nil,
            source: .cache, at: day("2026-09-28")
        )
        let restored = try await store.load()
        XCTAssertEqual(restored?.semesterStart, day("2026-09-07"))
        XCTAssertEqual(restored?.updatedAt, day("2026-09-20"))
        XCTAssertTrue(query(restored, "2026-09-28").text.contains("第4周"))
    }

    func testCachedDataDoesNotPretendToHaveJustSynced() async throws {
        let store = ScheduleShortcutStore(userID: "A", dataStore: InMemoryDataStore())
        try await store.record(
            courses: [], semester: semester, currentWeek: 2,
            source: .cache, at: day("2026-09-20")
        )
        let cached = try await store.load()
        XCTAssertNil(cached?.updatedAt)
        XCTAssertTrue(query(cached, "2026-09-14").text.contains("缓存课表"))
    }

    func testDelayedCacheReadCannotOverwriteRecordedRemoteCourses() async throws {
        let store = ScheduleShortcutStore(userID: "A", dataStore: InMemoryDataStore())
        let fresh = course(id: "new-course")
        try await store.record(
            courses: [fresh], semester: semester, currentWeek: 2,
            source: .remote, at: day("2026-09-20")
        )
        try await store.record(
            courses: [course(id: "old-course")], semester: semester, currentWeek: 3,
            source: .cache, at: day("2026-09-21")
        )
        let restored = try await store.load()
        XCTAssertEqual(restored?.courses, [fresh])
        XCTAssertEqual(restored?.updatedAt, day("2026-09-20"))
    }

    func testAccountSwitchAndSignOutNeverExposePreviousAccountsSchedule() async throws {
        let data = InMemoryDataStore()
        let session = CampusSessionStore(secureStore: InMemorySecureStore())
        let service = ScheduleShortcutService(
            dataStore: data, sessionStore: session, consentStore: try await consent(), experienceEnabled: { false }
        )
        try await ScheduleShortcutStore(userID: "A", dataStore: data).record(
            courses: [course()], semester: semester, currentWeek: 2,
            source: .remote, at: day("2026-09-20")
        )
        try await session.save(.init(user: User(name: "A", studentID: "A"), cookiesJSON: "[]"))
        let first = await service.query(date: day("2026-09-14"), inputCalendar: CampusScheduleCalendar.calendar)
        XCTAssertEqual(first.status, .courses)
        try await session.save(.init(user: User(name: "B", studentID: "B"), cookiesJSON: "[]"))
        let second = await service.query(date: day("2026-09-14"), inputCalendar: CampusScheduleCalendar.calendar)
        XCTAssertEqual(second.status, .noData)
        try await session.clear()
        let signedOut = await service.query(date: day("2026-09-14"))
        XCTAssertEqual(signedOut.status, .signInRequired)
    }

    func testFirstRunRequiresSetup() async {
        let service = ScheduleShortcutService(
            dataStore: InMemoryDataStore(), sessionStore: CampusSessionStore(secureStore: InMemorySecureStore()),
            consentStore: AgreementConsentStore(store: InMemoryDataStore()), experienceEnabled: { false }
        )
        let value = await service.query(date: day("2026-09-14"))
        XCTAssertEqual(value.status, .setupRequired)
    }

    func testExperienceModeDistinguishesAbsentAndImportedEmptyScheduleWithoutLogin() async throws {
        let data = InMemoryDataStore()
        let service = ScheduleShortcutService(
            dataStore: data, sessionStore: CampusSessionStore(secureStore: InMemorySecureStore()),
            consentStore: try await consent(.declined), experienceEnabled: { true }
        )
        let absent = await service.query(date: day("2026-09-14"))
        XCTAssertEqual(absent.status, .noData)
        var imported = ExperienceScheduleSnapshot()
        imported.currentWeek = 2
        imported.updatedAt = day("2026-09-20")
        imported.coursesBySemester = [semester.rawValue: []]
        try await ExperienceScheduleStore(store: data).replace(with: imported)
        let empty = await service.query(date: day("2026-09-14"), inputCalendar: CampusScheduleCalendar.calendar)
        XCTAssertEqual(empty.status, .noClasses)
    }

    func testCorruptCacheDoesNotBecomeNoClasses() async throws {
        let data = InMemoryDataStore()
        let session = CampusSessionStore(secureStore: InMemorySecureStore())
        try await session.save(.init(user: User(name: "A", studentID: "A"), cookiesJSON: "[]"))
        try await UserScopedStore(store: data, userID: "A").set(Data("broken".utf8), forKey: "shortcuts.schedule.v1")
        let service = ScheduleShortcutService(
            dataStore: data, sessionStore: session, consentStore: try await consent(), experienceEnabled: { false }
        )
        let value = await service.query(date: day("2026-09-14"))
        XCTAssertEqual(value.status, .noData)
    }

    func testPaymentIntentQueuesARequestAndAnOldConsumerCannotRemoveANewRequest() async throws {
        let navigation = ShortcutNavigation.shared
        defer { if let request = navigation.pendingRequest { navigation.consume(request) } }
        _ = try await OpenPaymentCodeIntent().perform()
        let first = try XCTUnwrap(navigation.pendingRequest)
        XCTAssertEqual(first.destination, .paymentCode)
        _ = try await OpenPaymentCodeIntent().perform()
        let second = try XCTUnwrap(navigation.pendingRequest)
        XCTAssertNotEqual(first.id, second.id)
        navigation.consume(first)
        XCTAssertEqual(navigation.pendingRequest, second)
    }

    func testPaymentURLOnlyAcceptsTheExpectedRoute() {
        XCTAssertEqual(ShortcutDestination(url: URL(string: "ahutong://payment-code")!), .paymentCode)
        for url in ["https://payment-code", "ahutong://schedule", "ahutong://payment-code/other", "ahutong://payment-code?token=value"] {
            XCTAssertNil(ShortcutDestination(url: URL(string: url)!))
        }
    }

    private var semester: Semester { Semester(schoolYear: "2026-2027", term: "1")! }

    private func day(_ value: String) -> Date {
        let parts = value.split(separator: "-").map { Int($0)! }
        return CampusScheduleCalendar.calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))!
    }

    private func snapshot(courses: [Course]) -> ShortcutScheduleSnapshot {
        ShortcutScheduleSnapshot.make(
            semester: semester, courses: courses, currentWeek: 2,
            referenceDate: day("2026-09-20"), updatedAt: day("2026-09-20")
        )!
    }

    private func query(_ snapshot: ShortcutScheduleSnapshot?, _ value: String) -> ScheduleShortcutResult {
        .query(snapshot: snapshot, day: day(value))
    }

    private func course(day: Int = 1, id: String = "course", period: Int = 1, location: String = "博学南楼 A301", weeks: [Int] = Array(1...20)) -> Course {
        Course(weekday: day, startWeek: 1, endWeek: 20, location: location, name: "测试课程", teacher: "", duration: 2, startPeriod: period, courseID: id, weekIndexes: weeks)
    }

    private func consent(_ decision: PrivacyConsentDecision = .accepted) async throws -> AgreementConsentStore {
        let store = AgreementConsentStore(store: InMemoryDataStore())
        _ = try await store.setPrivacyDecision(decision)
        _ = try await store.setAccepted(true, document: .disclaimer)
        _ = try await store.confirmRequiredDocuments()
        return store
    }
}
