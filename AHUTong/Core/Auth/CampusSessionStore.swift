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

enum AppSessionState: Equatable {
    case loading
    case signedOut
    case authenticated(User)
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var sessionState: AppSessionState = .loading
    @Published private(set) var reauthenticationMessage: String?

    let campusAPI: any CampusCoreAPI
    private let sessionStore: CampusSessionStore
    private let credentialStore: CredentialStore
    private let refreshCoordinator: SessionRefreshCoordinator

    init(
        campusAPI: any CampusCoreAPI = RustCampusCoreAPI(),
        sessionStore: CampusSessionStore = CampusSessionStore(),
        credentialStore: CredentialStore = CredentialStore(),
        refreshCoordinator: SessionRefreshCoordinator = .shared
    ) {
        self.campusAPI = campusAPI
        self.sessionStore = sessionStore
        self.credentialStore = credentialStore
        self.refreshCoordinator = refreshCoordinator
    }

    func restore(demoSession: Bool = false) async {
        if demoSession {
            sessionState = .authenticated(User(name: "测试同学", studentID: "AB220001"))
            return
        }
        do {
            guard let snapshot = try await sessionStore.load() else {
                sessionState = .signedOut
                return
            }
            do {
                try await campusAPI.initialize(cookiesJSON: snapshot.cookiesJSON)
                do {
                    _ = try await campusAPI.currentWeek()
                } catch CampusCoreError.unauthorized {
                    try await refreshCoordinator.refresh { [campusAPI] in
                        try await campusAPI.refreshSession()
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

    func login(studentID: String, password: String) async throws {
        let canonicalID = StudentIDCanonicalizer.canonical(studentID)
        let credentials = LoginCredentials(studentID: canonicalID, password: password)
        try await campusAPI.initialize(cookiesJSON: "")
        let user = try await campusAPI.login(studentID: canonicalID, password: password)
        let cookies = try await campusAPI.dumpCookies()
        try await credentialStore.save(credentials)
        try await sessionStore.save(CampusSessionSnapshot(user: user, cookiesJSON: cookies))
        reauthenticationMessage = nil
        sessionState = .authenticated(user)
    }

    func signOut() async {
        if case let .authenticated(user) = sessionState {
            try? await credentialStore.removeCredentials(for: user.studentID)
        }
        try? await sessionStore.clear()
        try? await campusAPI.initialize(cookiesJSON: "")
        try? await ScheduleWidgetSnapshotStore.shared.save(.unavailable(.signedOut))
        WidgetCenter.shared.reloadTimelines(ofKind: "AHUTongScheduleWidget")
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
}
