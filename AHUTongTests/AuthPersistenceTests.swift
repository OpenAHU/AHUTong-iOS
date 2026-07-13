import Foundation
import XCTest
@testable import AHUTong

final class AuthPersistenceTests: XCTestCase {
    @MainActor
    func testAuthSessionTransitionsWithoutPersistingCredentials() async {
        let session = InMemoryAuthSession()
        let user = User(name: "张三", studentID: "AB220001")

        var state = await session.currentState()
        XCTAssertEqual(state, .signedOut)
        await session.authenticate(user: user)
        state = await session.currentState()
        XCTAssertEqual(state, .authenticated(user))
        await session.signOut()
        state = await session.currentState()
        XCTAssertEqual(state, .signedOut)
    }

    @MainActor
    func testUserScopedStoreSeparatesAccounts() async throws {
        let base = InMemoryDataStore()
        let first = UserScopedStore(store: base, userID: "AB220001")
        let second = UserScopedStore(store: base, userID: "AB230001")

        try await first.set(Data("first".utf8), forKey: "schedule.current")
        try await second.set(Data("second".utf8), forKey: "schedule.current")

        let firstValue = try await first.data(forKey: "schedule.current")
        let secondValue = try await second.data(forKey: "schedule.current")
        XCTAssertEqual(firstValue, Data("first".utf8))
        XCTAssertEqual(secondValue, Data("second".utf8))
    }

    @MainActor
    func testJSONStoreRoundTripsTypedValues() async throws {
        let base = InMemoryDataStore()
        let scoped = UserScopedStore(store: base, userID: "AB220001")
        let store = JSONStore<[Course]>(store: scoped, key: "schedule.2025-2026-1")
        let course = Course(
            weekday: 1,
            startWeek: 1,
            endWeek: 16,
            location: "博学南楼101",
            name: "高等数学",
            teacher: "李老师",
            duration: 2,
            startPeriod: 1,
            courseID: "42",
            weekIndexes: [1, 3, 5]
        )

        try await store.save([course])
        let savedCourses = try await store.load()
        XCTAssertEqual(savedCourses, [course])
        try await store.remove()
        let removedCourses = try await store.load()
        XCTAssertNil(removedCourses)
    }
}
