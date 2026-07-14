import XCTest
@testable import AHUTong

final class CampusSessionStoreTests: XCTestCase {
    @MainActor
    func testLoginPersistsCredentialsAndRestoresCookieSession() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let model = AppModel(
            campusAPI: api,
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore)
        )

        try await model.login(studentID: "AB220001", password: "secret")
        XCTAssertEqual(model.sessionState, .authenticated(User(name: "测试同学", studentID: "AB220001")))

        let restored = AppModel(
            campusAPI: api,
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore)
        )
        await restored.restore()

        XCTAssertEqual(restored.sessionState, model.sessionState)
        let initializedCookies = await api.lastInitializedCookies()
        XCTAssertEqual(initializedCookies, "cookie-json")
    }

    @MainActor
    func testSignOutClearsPersistedSession() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let model = AppModel(
            campusAPI: api,
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore)
        )
        try await model.login(studentID: "AB220001", password: "secret")

        await model.signOut()

        XCTAssertEqual(model.sessionState, .signedOut)
        let persistedSession = try await CampusSessionStore(secureStore: secureStore).load()
        XCTAssertNil(persistedSession)
    }
}

private actor CampusCoreAPIStub: CampusCoreAPI {
    private var cookies = ""
    func initialize(cookiesJSON: String) { cookies = cookiesJSON }
    func login(studentID: String, password: String) -> User { User(name: "测试同学", studentID: studentID) }
    func dumpCookies() -> String { "cookie-json" }
    func schedule() -> [Course] { [] }
    func currentWeek() -> Int { 1 }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func lastInitializedCookies() -> String { cookies }
}
