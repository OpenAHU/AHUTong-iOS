import XCTest
@testable import AHUTong

final class CampusSessionStoreTests: XCTestCase {
    func testLegacyCookieDetectionDoesNotTreatOfflinePlaceholderAsNativeDump() {
        XCTAssertTrue(CampusCookieSnapshotPolicy.isLegacyNativeDump(#"{"raw_cookie":"test-only"}"#))
        XCTAssertFalse(CampusCookieSnapshotPolicy.isLegacyNativeDump("cached-cookie"))
        XCTAssertFalse(CampusCookieSnapshotPolicy.isLegacyNativeDump("[]"))
    }

    @MainActor
    func testRestoreMigratesLegacyNativeCookieDumpToFlatSnapshot() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let user = User(name: "测试同学", studentID: "AB220001")
        try await sessionStore.save(CampusSessionSnapshot(
            user: user,
            cookiesJSON: #"{"raw_cookie":"test-only"}"# + "\n"
        ))
        let cookie = CampusCookie(
            name: "JSESSIONID", value: "test-only", domain: "adwmh.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )
        let flat = String(decoding: try JSONEncoder().encode([cookie]), as: UTF8.self)
        let suite = "legacy-cookie-migration-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(
            campusAPI: CampusCoreAPIStub(flatCookies: flat),
            sessionStore: sessionStore,
            credentialStore: CredentialStore(secureStore: secureStore),
            defaults: defaults
        )

        await model.restore(privacyDecision: .accepted)

        let restored = try await sessionStore.load()
        XCTAssertEqual(model.sessionState, .authenticated(user))
        XCTAssertEqual(restored?.cookiesJSON, flat)
        XCTAssertTrue(CampusCookieSnapshotPolicy.isFlat(restored?.cookiesJSON ?? ""))
    }

    @MainActor
    func testAcceptedPrivacyRestoresChosenExperienceAccountWithoutCredentials() async throws {
        let secureStore = InMemorySecureStore()
        let suite = "experience-skip-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let experienceStore = ExperienceScheduleStore(store: InMemoryDataStore())
        let first = AppModel(
            campusAPI: CampusCoreAPIStub(),
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore),
            experienceScheduleStore: experienceStore,
            defaults: defaults,
            accountCacheCleaner: {}
        )
        await first.enterExperienceMode(preserveSchedule: false)

        let restored = AppModel(
            campusAPI: CampusCoreAPIStub(),
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore),
            experienceScheduleStore: experienceStore,
            defaults: defaults,
            accountCacheCleaner: {}
        )
        await restored.restore(privacyDecision: .accepted)

        XCTAssertEqual(restored.sessionState, .experience(AppModel.experienceUser))
        let snapshot = try await CampusSessionStore(secureStore: secureStore).load()
        XCTAssertNil(snapshot)
    }

    @MainActor
    func testLoginPersistsCredentialsAndRestoresCookieSession() async throws {
        let secureStore = InMemorySecureStore()
        let api = CampusCoreAPIStub()
        let model = AppModel(
            campusAPI: api,
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore)
        )

        try await model.completeWebLogin(Self.webLoginResult())
        XCTAssertEqual(model.sessionState, .authenticated(User(name: "AB220001", studentID: "AB220001")))

        let restored = AppModel(
            campusAPI: api,
            sessionStore: CampusSessionStore(secureStore: secureStore),
            credentialStore: CredentialStore(secureStore: secureStore)
        )
        await restored.restore()

        XCTAssertEqual(restored.sessionState, model.sessionState)
        let initializedCookies = await api.lastInitializedCookies()
        XCTAssertTrue(initializedCookies.contains("SESSION"))
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
        try await model.completeWebLogin(Self.webLoginResult())

        await model.signOut()

        XCTAssertEqual(model.sessionState, .signedOut)
        let persistedSession = try await CampusSessionStore(secureStore: secureStore).load()
        XCTAssertNil(persistedSession)
    }

    @MainActor
    func testCampusCardLoginKeepsCookiesUpdatedDuringValidation() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let api = CampusCoreAPIStub()
        let user = User(name: "测试同学", studentID: "AB220001")
        try await sessionStore.save(CampusSessionSnapshot(user: user, cookiesJSON: "[]"))
        let currentCookie = CampusCookie(
            name: "JSESSIONID", value: "rotated-test-only", domain: "adwmh.ahu.edu.cn",
            path: "/", secure: true, httpOnly: true
        )
        let currentCookies = String(decoding: try JSONEncoder().encode([currentCookie]), as: UTF8.self)
        await api.setDumpCookies(currentCookies)
        let model = AppModel(
            campusAPI: api,
            sessionStore: sessionStore,
            credentialStore: CredentialStore(secureStore: secureStore)
        )

        try await model.completeCampusCardLogin(CampusWebAuthenticationResult(
            credentials: nil,
            cookies: [CampusCookie(
                name: "JSESSIONID", value: "initial-test-only", domain: "adwmh.ahu.edu.cn",
                path: "/", secure: true, httpOnly: true
            )]
        ))

        let stored = try await sessionStore.load()
        XCTAssertEqual(stored?.cookiesJSON, currentCookies)
    }

    @MainActor
    func testPrivacyRevocationClearsCredentialsAndEntersExperienceMode() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentialStore = CredentialStore(secureStore: secureStore)
        let scheduleDataStore = InMemoryDataStore()
        let experienceStore = ExperienceScheduleStore(store: scheduleDataStore)
        let semester = Semester.current()
        let course = ScheduleViewModel.demoCourses[0]
        try await experienceStore.save(courses: [course], semester: semester, currentWeek: 2)
        let suite = "experience-session-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try await sessionStore.save(CampusSessionSnapshot(
            user: User(name: "测试同学", studentID: "AB220001"),
            cookiesJSON: "[]"
        ))
        try await credentialStore.save(LoginCredentials(
            studentID: "AB220001",
            password: "test-only"
        ))
        let model = AppModel(
            campusAPI: CampusCoreAPIStub(),
            sessionStore: sessionStore,
            credentialStore: credentialStore,
            experienceScheduleStore: experienceStore,
            defaults: defaults,
            accountCacheCleaner: {}
        )

        await model.enterExperienceMode(preserveSchedule: false)

        let persistedSession = try await sessionStore.load()
        let persistedCredentials = try await credentialStore.credentials(for: "AB220001")
        let experienceCourses = await experienceStore.courses(for: semester)
        XCTAssertEqual(model.sessionState, .experience(AppModel.experienceUser))
        XCTAssertNil(persistedSession)
        XCTAssertNil(persistedCredentials)
        XCTAssertEqual(experienceCourses, [course])
    }

    @MainActor
    func testRestoreReauthenticatesExpiredCookieSessionAndPersistsReplacement() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentials = CredentialStore(secureStore: secureStore)
        let api = CampusCoreAPIStub(
            sessionStore: sessionStore,
            credentialStore: credentials
        )
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
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentials = CredentialStore(secureStore: secureStore)
        let api = CampusCoreAPIStub(
            sessionStore: sessionStore,
            credentialStore: credentials
        )
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
            credentialStore: credentials
        )

        await model.restore()

        XCTAssertEqual(model.sessionState, .signedOut)
        XCTAssertEqual(model.reauthenticationMessage, "登录信息需要更新，请重新登录一次")
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
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentials = CredentialStore(secureStore: secureStore)
        let api = CampusCoreAPIStub(
            sessionStore: sessionStore,
            credentialStore: credentials
        )
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

    @MainActor
    func testRestoreKeepsIdentityAndCredentialsForSchoolFiveHundred() async throws {
        let secureStore = InMemorySecureStore()
        let sessionStore = CampusSessionStore(secureStore: secureStore)
        let credentials = CredentialStore(secureStore: secureStore)
        let snapshot = CampusSessionSnapshot(
            user: User(name: "离线同学", studentID: "AB220001"),
            cookiesJSON: "cached-cookie"
        )
        try await sessionStore.save(snapshot)
        try await credentials.save(
            LoginCredentials(studentID: "AB220001", password: "test-only")
        )
        let api = CampusCoreAPIStub(
            sessionStore: sessionStore,
            credentialStore: credentials
        )
        await api.failNextValidationWithServerError()
        let model = AppModel(
            campusAPI: api,
            sessionStore: sessionStore,
            credentialStore: credentials,
            refreshCoordinator: SessionRefreshCoordinator()
        )

        await model.restore()

        XCTAssertEqual(model.sessionState, .authenticated(snapshot.user))
        let restoredSnapshot = try await sessionStore.load()
        let restoredCredentials = try await credentials.credentials(for: "AB220001")
        XCTAssertEqual(restoredSnapshot, snapshot)
        XCTAssertNotNil(restoredCredentials)
    }

    private static func webLoginResult() -> CampusWebAuthenticationResult {
        CampusWebAuthenticationResult(
            credentials: LoginCredentials(studentID: "AB220001", password: "secret"),
            cookies: [
                CampusCookie(
                    name: "SESSION",
                    value: "test-only",
                    domain: "jw.ahu.edu.cn",
                    path: "/",
                    secure: true,
                    httpOnly: true
                )
            ]
        )
    }
}

private actor CampusCoreAPIStub: CampusCoreAPI {
    private var cookies = ""
    private var shouldExpireNextValidation = false
    private var shouldFailNextValidationOffline = false
    private var shouldFailNextValidationServer = false
    private var shouldRejectNextLogin = false
    private var performedLogins = 0
    private var nextDumpCookies: String?
    private let flatCookies: String?
    private let sessionStore: CampusSessionStore?
    private let credentialStore: CredentialStore?

    init(
        sessionStore: CampusSessionStore? = nil,
        credentialStore: CredentialStore? = nil,
        flatCookies: String? = nil
    ) {
        self.sessionStore = sessionStore
        self.credentialStore = credentialStore
        self.flatCookies = flatCookies
    }
    func initialize(cookiesJSON: String) { cookies = cookiesJSON }
    func login(studentID: String, password: String) throws -> User {
        performedLogins += 1
        if shouldRejectNextLogin {
            shouldRejectNextLogin = false
            throw CampusCoreError.credentialsRejected
        }
        return User(name: "测试同学", studentID: studentID)
    }
    func dumpCookies() -> String { nextDumpCookies ?? "cookie-json" }
    func setDumpCookies(_ value: String) { nextDumpCookies = value }
    func cookiesFlat() -> String { flatCookies ?? "[]" }
    func schedule() -> [Course] { [] }
    func currentWeek() throws -> Int {
        if shouldFailNextValidationOffline {
            shouldFailNextValidationOffline = false
            throw URLError(.notConnectedToInternet)
        }
        if shouldFailNextValidationServer {
            shouldFailNextValidationServer = false
            throw CampusCoreError.campus("学校服务请求失败（500）")
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
    func refreshSession(scope: CampusSessionScope) async throws {
        guard let sessionStore,
              let credentialStore,
              let snapshot = try await sessionStore.load(),
              let credentials = try await credentialStore.credentials(
                  for: snapshot.user.studentID
              ) else {
            throw CampusCoreError.credentialsUnavailable
        }
        cookies = ""
        let user = try login(
            studentID: credentials.studentID,
            password: credentials.password
        )
        cookies = "cookie-json"
        try await sessionStore.save(
            CampusSessionSnapshot(user: user, cookiesJSON: cookies)
        )
    }
    func invalidateStoredSession() async {
        if let sessionStore,
           let snapshot = try? await sessionStore.load(),
           let credentialStore {
            try? await credentialStore.removeCredentials(for: snapshot.user.studentID)
        }
        if let sessionStore {
            try? await sessionStore.clear()
        }
        cookies = ""
    }
    func lastInitializedCookies() -> String { cookies }
    func expireNextValidation() { shouldExpireNextValidation = true }
    func failNextValidationWithTransportError() { shouldFailNextValidationOffline = true }
    func failNextValidationWithServerError() { shouldFailNextValidationServer = true }
    func rejectNextLogin() { shouldRejectNextLogin = true }
    func loginCount() -> Int { performedLogins }
}
