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

    @MainActor
    func testRestoreReauthenticatesExpiredCookieSessionAndPersistsReplacement() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentials = CredentialStore(secureStore: secureStore)
        try await sessionStore.save(
            CampusSessionSnapshot(
                user: User(name: "旧会话", studentID: "AB220001"),
                cookiesJSON: "expired-cookie"
            )
        )
        try await credentials.save(LoginCredentials(studentID: "AB220001", password: "test-only"))
        await api.expireNextValidation()
        let model = AppModel(campusAPI: api, sessionStore: sessionStore, credentialStore: credentials)

        await model.restore()

        XCTAssertEqual(model.sessionState, .authenticated(User(name: "测试同学", studentID: "AB220001")))
        let restoredSession = try await sessionStore.load()
        let performedLogins = await api.loginCount()
        XCTAssertEqual(restoredSession?.cookiesJSON, "cookie-json")
        XCTAssertEqual(performedLogins, 1)
    }

    @MainActor
    func testRestoreClearsExpiredSessionWhenCredentialsAreUnavailable() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        try await sessionStore.save(
            CampusSessionSnapshot(
                user: User(name: "旧会话", studentID: "AB220001"),
                cookiesJSON: "expired-cookie"
            )
        )
        await api.expireNextValidation()
        let model = AppModel(
            campusAPI: api,
            sessionStore: sessionStore,
            credentialStore: CredentialStore(secureStore: secureStore)
        )

        await model.restore()

        XCTAssertEqual(model.sessionState, .signedOut)
        let clearedSession = try await sessionStore.load()
        XCTAssertNil(clearedSession)
    }

    @MainActor
    func testRestoreKeepsCachedIdentityWhenValidationIsOffline() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let snapshot = CampusSessionSnapshot(
            user: User(name: "离线同学", studentID: "AB220001"),
            cookiesJSON: "cached-cookie"
        )
        try await sessionStore.save(snapshot)
        await api.failNextValidationWithTransportError()
        let model = AppModel(
            campusAPI: api,
            sessionStore: sessionStore,
            credentialStore: CredentialStore(secureStore: secureStore)
        )

        await model.restore()

        XCTAssertEqual(model.sessionState, .authenticated(snapshot.user))
        let persisted = try await sessionStore.load()
        XCTAssertEqual(persisted, snapshot)
    }

    @MainActor
    func testRestoreSignsOutWhenCredentialReauthenticationIsRejected() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentials = CredentialStore(secureStore: secureStore)
        let snapshot = CampusSessionSnapshot(
            user: User(name: "旧会话", studentID: "AB220001"),
            cookiesJSON: "expired-cookie"
        )
        try await sessionStore.save(snapshot)
        try await credentials.save(LoginCredentials(studentID: "AB220001", password: "expired"))
        await api.expireNextValidation()
        await api.rejectNextLogin()
        let model = AppModel(campusAPI: api, sessionStore: sessionStore, credentialStore: credentials)

        await model.restore()
        let persistedSession = try await sessionStore.load()
        let persistedCredentials = try await credentials.credentials(for: "AB220001")

        XCTAssertEqual(model.sessionState, .signedOut)
        XCTAssertNil(persistedSession)
        XCTAssertNil(persistedCredentials)
    }
}

private actor CampusCoreAPIStub: CampusCoreAPI {
    private var cookies = ""
    private var shouldExpireNextValidation = false
    private var shouldFailNextValidationOffline = false
    private var shouldRejectNextLogin = false
    private var performedLogins = 0
    func initialize(cookiesJSON: String) { cookies = cookiesJSON }
    func login(studentID: String, password: String) throws -> User {
        performedLogins += 1
        if shouldRejectNextLogin {
            shouldRejectNextLogin = false
            throw CampusCoreError.unauthorized
        }
        return User(name: "测试同学", studentID: studentID)
    }
    func dumpCookies() -> String { "cookie-json" }
    func cookiesFlat() -> String { "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() throws -> Int {
        if shouldFailNextValidationOffline {
            shouldFailNextValidationOffline = false
            throw URLError(.notConnectedToInternet)
        }
        if shouldExpireNextValidation {
            shouldExpireNextValidation = false
            throw CampusCoreError.unauthorized
        }
        return 1
    }
    func exams() -> [CampusExam] { [] }
    func grades() -> CampusGradeReport { CampusGradeReport(grades: [], gradePointAverage: nil, rank: nil, studentProfiles: []) }
    func cardBalance() -> Double { 126.35 }
    func cardQRCode() -> String { "DEMO-QR" }
    func lastInitializedCookies() -> String { cookies }
    func expireNextValidation() { shouldExpireNextValidation = true }
    func failNextValidationWithTransportError() { shouldFailNextValidationOffline = true }
    func rejectNextLogin() { shouldRejectNextLogin = true }
    func loginCount() -> Int { performedLogins }
}
