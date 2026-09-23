import Foundation
import WidgetKit

struct CampusSessionSnapshot: Codable, Equatable, Sendable {
    let user: User
    let cookiesJSON: String
}

struct CampusSessionStore: Sendable {
    private let secureStore: any SecureStore
    private let account = "campus.session"

    init(secureStore: any SecureStore = KeychainSecureStore()) {
        self.secureStore = secureStore
    }

    func load() async throws -> CampusSessionSnapshot? {
        guard let data = try await secureStore.data(forAccount: account) else { return nil }
        return try JSONDecoder().decode(CampusSessionSnapshot.self, from: data)
    }

    func save(_ snapshot: CampusSessionSnapshot) async throws {
        try await secureStore.set(try JSONEncoder().encode(snapshot), forAccount: account)
    }

    func clear() async throws {
        try await secureStore.removeValue(forAccount: account)
    }
}

enum CampusCookieSnapshotPolicy {
    static func isFlat(_ cookiesJSON: String) -> Bool {
        (try? JSONDecoder().decode([CampusCookie].self, from: Data(cookiesJSON.utf8))) != nil
    }

    static func isLegacyNativeDump(_ cookiesJSON: String) -> Bool {
        let lines = cookiesJSON.split(whereSeparator: \.isNewline)
        guard !lines.isEmpty else { return false }
        return lines.allSatisfy { line in
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else {
                return false
            }
            return object["raw_cookie"] is String
        }
    }
}

enum AppSessionState: Equatable {
    case loading
    case signedOut
    case authenticated(User)
    case experience(User)
}

@MainActor
final class AppModel: ObservableObject {
    static let experienceUser = User(name: "安大通体验用户", studentID: "AHUTONG-EXPERIENCE")

    @Published private(set) var sessionState: AppSessionState = .loading
    @Published private(set) var reauthenticationMessage: String?

    let campusAPI: any CampusCoreAPI
    private let sessionStore: CampusSessionStore
    private let credentialStore: CredentialStore
    private let refreshCoordinator: SessionRefreshCoordinator
    private let experienceScheduleStore: ExperienceScheduleStore
    private let defaults: UserDefaults
    private let accountCacheCleaner: @Sendable () async -> Void
    static let experienceEnabledKey = "session.experience-enabled"

    init(
        campusAPI: any CampusCoreAPI = RustCampusCoreAPI(),
        sessionStore: CampusSessionStore = CampusSessionStore(),
        credentialStore: CredentialStore = CredentialStore(),
        refreshCoordinator: SessionRefreshCoordinator = .shared,
        experienceScheduleStore: ExperienceScheduleStore = ExperienceScheduleStore(),
        defaults: UserDefaults = .standard,
        accountCacheCleaner: @escaping @Sendable () async -> Void = {
            await AppDataCleaner.clearCaches()
        }
    ) {
        self.campusAPI = campusAPI
        self.sessionStore = sessionStore
        self.credentialStore = credentialStore
        self.refreshCoordinator = refreshCoordinator
        self.experienceScheduleStore = experienceScheduleStore
        self.defaults = defaults
        self.accountCacheCleaner = accountCacheCleaner
    }

    var isExperienceMode: Bool {
        if case .experience = sessionState { return true }
        return false
    }

    func restore(
        privacyDecision: PrivacyConsentDecision = .accepted,
        demoSession: Bool = false
    ) async {
        if demoSession {
            sessionState = .authenticated(User(name: "测试同学", studentID: "AB220001"))
            return
        }
        guard privacyDecision == .accepted else {
            if (try? await sessionStore.load()) != nil {
                await enterExperienceMode()
                return
            }
            sessionState = defaults.bool(forKey: Self.experienceEnabledKey)
                ? .experience(Self.experienceUser)
                : .signedOut
            return
        }
        if defaults.bool(forKey: Self.experienceEnabledKey) {
            sessionState = .experience(Self.experienceUser)
            return
        }
        do {
            guard let snapshot = try await sessionStore.load() else {
                sessionState = .signedOut
                return
            }
            do {
                try await campusAPI.initialize(cookiesJSON: snapshot.cookiesJSON)
                if CampusCookieSnapshotPolicy.isLegacyNativeDump(snapshot.cookiesJSON) {
                    let flatCookies = try await campusAPI.cookiesFlat()
                    guard let decoded = try? JSONDecoder().decode(
                        [CampusCookie].self, from: Data(flatCookies.utf8)
                    ), !decoded.isEmpty else {
                        throw CampusCoreError.invalidResponse
                    }
                    try await sessionStore.save(CampusSessionSnapshot(
                        user: snapshot.user, cookiesJSON: flatCookies
                    ))
                }
                do {
                    _ = try await campusAPI.currentWeek()
                } catch CampusCoreError.unauthorized {
                    try await refreshCoordinator.refresh(scope: .academic) { [campusAPI] in
                        try await campusAPI.refreshSession(scope: .academic)
                    }
                    do {
                        _ = try await campusAPI.currentWeek()
                    } catch CampusCoreError.unauthorized {
                        await campusAPI.invalidateStoredSession()
                        throw CampusCoreError.credentialsRejected
                    }
                }
                let refreshedSnapshot = try await sessionStore.load()
                reauthenticationMessage = nil
                sessionState = .authenticated(refreshedSnapshot?.user ?? snapshot.user)
            } catch CampusCoreError.credentialsUnavailable {
                await requireReauthentication()
            } catch CampusCoreError.credentialsRejected {
                await rejectCredentials(for: snapshot.user.studentID)
            } catch {
                // Transport failures and 5xx responses are not proof that the
                // Keychain session is invalid. Preserve offline access.
                sessionState = .authenticated(snapshot.user)
            }
        } catch {
            sessionState = .signedOut
        }
    }

    func completeWebLogin(_ result: CampusWebAuthenticationResult) async throws {
        guard let credentials = result.credentials else {
            throw CampusWebAuthenticationError.credentialsUnavailable
        }
        let canonicalID = StudentIDCanonicalizer.canonical(credentials.studentID)
        let normalizedCredentials = LoginCredentials(
            studentID: canonicalID,
            password: credentials.password
        )
        let previous = try? await sessionStore.load()
        let existingCookies = previous.flatMap {
            try? JSONDecoder().decode([CampusCookie].self, from: Data($0.cookiesJSON.utf8))
        } ?? []
        let merged = CampusCookieMerger.merge(existing: existingCookies, incoming: result.cookies)
        let cookies = String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        try await campusAPI.initialize(cookiesJSON: cookies)
        do {
            try await campusAPI.validateSession(scope: .academic)
        } catch {
            try? await campusAPI.initialize(cookiesJSON: "")
            throw error
        }
        let user: User
        if let previous, previous.user.studentID == canonicalID {
            user = previous.user
        } else {
            user = User(name: canonicalID, studentID: canonicalID)
        }
        do {
            try await credentialStore.save(normalizedCredentials)
            try await sessionStore.save(CampusSessionSnapshot(user: user, cookiesJSON: cookies))
        } catch {
            try? await credentialStore.removeCredentials(for: canonicalID)
            try? await sessionStore.clear()
            try? await campusAPI.initialize(cookiesJSON: "")
            throw error
        }
        defaults.set(false, forKey: Self.experienceEnabledKey)
        reauthenticationMessage = nil
        sessionState = .authenticated(user)
    }

    func completeCampusCardLogin(_ result: CampusWebAuthenticationResult) async throws {
        guard let snapshot = try await sessionStore.load() else {
            throw CampusWebAuthenticationError.credentialsUnavailable
        }
        var existing = (try? JSONDecoder().decode(
            [CampusCookie].self,
            from: Data(snapshot.cookiesJSON.utf8)
        )) ?? []
        if existing.isEmpty, !CampusCookieSnapshotPolicy.isFlat(snapshot.cookiesJSON),
           let flatCookies = try? await campusAPI.cookiesFlat(),
           let migrated = try? JSONDecoder().decode([CampusCookie].self, from: Data(flatCookies.utf8)) {
            existing = migrated
        }
        let merged = CampusCookieMerger.merge(existing: existing, incoming: result.cookies)
        let cookies = String(decoding: try JSONEncoder().encode(merged), as: UTF8.self)
        try await campusAPI.initialize(cookiesJSON: cookies)
        do {
            try await campusAPI.validateSession(scope: .campusCard)
            let validatedCookies = try await campusAPI.dumpCookies()
            try await sessionStore.save(CampusSessionSnapshot(user: snapshot.user, cookiesJSON: validatedCookies))
        } catch {
            try? await campusAPI.initialize(cookiesJSON: snapshot.cookiesJSON)
            throw error
        }
    }

    func currentCredentials() async -> LoginCredentials? {
        guard let snapshot = try? await sessionStore.load() else { return nil }
        return try? await credentialStore.credentials(for: snapshot.user.studentID)
    }

    func enterExperienceMode(preserveSchedule: Bool = true) async {
        let snapshot = try? await sessionStore.load()
        if preserveSchedule, let studentID = snapshot?.user.studentID {
            await experienceScheduleStore.preserveAccountCache(userID: studentID)
        }
        let preservedSchedule = await experienceScheduleStore.snapshot()
        if let studentID = snapshot?.user.studentID {
            try? await credentialStore.removeCredentials(for: studentID)
        }
        try? await sessionStore.clear()
        try? await campusAPI.initialize(cookiesJSON: "")
        await accountCacheCleaner()
        try? await experienceScheduleStore.replace(with: preservedSchedule)
        defaults.set(true, forKey: Self.experienceEnabledKey)
        reauthenticationMessage = nil
        sessionState = .experience(Self.experienceUser)
        await publishExperienceWidget()
    }

    func prepareForRealLogin() async {
        defaults.set(false, forKey: Self.experienceEnabledKey)
        reauthenticationMessage = nil
        sessionState = .signedOut
    }

    func signOut() async {
        if case let .authenticated(user) = sessionState {
            try? await credentialStore.removeCredentials(for: user.studentID)
        }
        try? await sessionStore.clear()
        try? await campusAPI.initialize(cookiesJSON: "")
        try? await ScheduleWidgetSnapshotStore.shared.save(.unavailable(.signedOut))
        WidgetCenter.shared.reloadTimelines(ofKind: "AHUTongScheduleWidget")
        defaults.set(false, forKey: Self.experienceEnabledKey)
        sessionState = .signedOut
    }

    func handleCredentialsRejected() async {
        let studentID: String?
        if case let .authenticated(user) = sessionState {
            studentID = user.studentID
        } else {
            studentID = (try? await sessionStore.load())?.user.studentID
        }
        if let studentID {
            await rejectCredentials(for: studentID)
        } else {
            reauthenticationMessage = "保存的登录信息已失效，请重新登录"
            sessionState = .signedOut
        }
    }

    func requireReauthentication() async {
        try? await sessionStore.clear()
        reauthenticationMessage = "登录信息需要更新，请重新登录一次"
        sessionState = .signedOut
    }

    private func rejectCredentials(for studentID: String) async {
        try? await credentialStore.removeCredentials(for: studentID)
        try? await sessionStore.clear()
        reauthenticationMessage = "保存的登录信息已失效，请重新登录"
        sessionState = .signedOut
    }

    private func publishExperienceWidget() async {
        let snapshot = await experienceScheduleStore.snapshot()
        let current = Semester.current()
        let courses = snapshot.coursesBySemester[current.rawValue] ?? []
        try? await ScheduleWidgetSnapshotStore.shared.save(
            .make(courses: courses, currentWeek: snapshot.resolvedCurrentWeek())
        )
        WidgetCenter.shared.reloadTimelines(ofKind: "AHUTongScheduleWidget")
    }
}
