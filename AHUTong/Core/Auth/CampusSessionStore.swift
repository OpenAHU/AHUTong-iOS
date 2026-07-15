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

    let campusAPI: any CampusCoreAPI
    private let sessionStore: CampusSessionStore
    private let credentialStore: CredentialStore

    init(
        campusAPI: any CampusCoreAPI = RustCampusCoreAPI(),
        sessionStore: CampusSessionStore = CampusSessionStore(),
        credentialStore: CredentialStore = CredentialStore()
    ) {
        self.campusAPI = campusAPI
        self.sessionStore = sessionStore
        self.credentialStore = credentialStore
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
                _ = try await campusAPI.currentWeek()
                sessionState = .authenticated(snapshot.user)
            } catch CampusCoreError.credentialsUnavailable {
                try? await sessionStore.clear()
                sessionState = .signedOut
            } catch CampusCoreError.unauthorized {
                guard let credentials = try await credentialStore.credentials(for: snapshot.user.studentID) else {
                    try? await sessionStore.clear()
                    sessionState = .signedOut
                    return
                }
                do {
                    try await campusAPI.initialize(cookiesJSON: "")
                    let user = try await campusAPI.login(
                        studentID: credentials.studentID,
                        password: credentials.password
                    )
                    let cookies = try await campusAPI.dumpCookies()
                    try await sessionStore.save(CampusSessionSnapshot(user: user, cookiesJSON: cookies))
                    sessionState = .authenticated(user)
                } catch CampusCoreError.unauthorized {
                    try? await credentialStore.removeCredentials(for: snapshot.user.studentID)
                    try? await sessionStore.clear()
                    sessionState = .signedOut
                } catch CampusCoreError.credentialsUnavailable {
                    try? await credentialStore.removeCredentials(for: snapshot.user.studentID)
                    try? await sessionStore.clear()
                    sessionState = .signedOut
                } catch {
                    // A campus outage must not make local, user-scoped caches
                    // inaccessible. Keep the last authenticated identity and
                    // let individual online screens expose their error state.
                    sessionState = .authenticated(snapshot.user)
                }
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
        let credentials = LoginCredentials(studentID: studentID, password: password)
        try await campusAPI.initialize(cookiesJSON: "")
        let user = try await campusAPI.login(studentID: studentID, password: password)
        let cookies = try await campusAPI.dumpCookies()
        try await credentialStore.save(credentials)
        try await sessionStore.save(CampusSessionSnapshot(user: user, cookiesJSON: cookies))
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
}
