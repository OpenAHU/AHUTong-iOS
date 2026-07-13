enum AuthState: Equatable, Sendable {
    case signedOut
    case authenticated(User)
}

protocol AuthSessionProtocol: Sendable {
    func currentState() async -> AuthState
    func authenticate(user: User) async
    func signOut() async
}

actor InMemoryAuthSession: AuthSessionProtocol {
    private var state: AuthState

    init(initialState: AuthState = .signedOut) {
        state = initialState
    }

    func currentState() async -> AuthState {
        state
    }

    func authenticate(user: User) async {
        state = .authenticated(user)
    }

    func signOut() async {
        state = .signedOut
    }
}
