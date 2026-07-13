import XCTest
@testable import AHUTong

final class CredentialStoreTests: XCTestCase {
    @MainActor
    func testCredentialsRoundTripAndCanBeRemoved() async throws {
        let secureStore = InMemorySecureStore()
        let store = CredentialStore(secureStore: secureStore)
        let credentials = LoginCredentials(studentID: " AB220001 ", password: "test-only")

        try await store.save(credentials)

        let saved = try await store.credentials(for: "AB220001")
        XCTAssertEqual(saved, LoginCredentials(studentID: "AB220001", password: "test-only"))
        try await store.removeCredentials(for: "AB220001")
        let removed = try await store.credentials(for: "AB220001")
        XCTAssertNil(removed)
    }

    @MainActor
    func testCredentialsAreIsolatedByStudentID() async throws {
        let store = CredentialStore(secureStore: InMemorySecureStore())
        try await store.save(LoginCredentials(studentID: "AB220001", password: "first"))
        try await store.save(LoginCredentials(studentID: "AB230001", password: "second"))

        let first = try await store.credentials(for: "AB220001")
        let second = try await store.credentials(for: "AB230001")
        XCTAssertEqual(first?.password, "first")
        XCTAssertEqual(second?.password, "second")
    }

    @MainActor
    func testEmptyCredentialsAreRejected() async throws {
        let store = CredentialStore(secureStore: InMemorySecureStore())

        do {
            try await store.save(LoginCredentials(studentID: "", password: ""))
            XCTFail("Expected invalid credentials")
        } catch let error as CredentialStoreError {
            XCTAssertEqual(error, .invalidCredentials)
        }
    }

    @MainActor
    func testKeychainAdapterRoundTripsNonProductionFixture() async throws {
        let service = "com.openahu.ahutong.tests.\(UUID().uuidString)"
        let secureStore = KeychainSecureStore(service: service)
        let account = "fixture-account"
        let fixture = Data("fixture-only".utf8)

        try await secureStore.set(fixture, forAccount: account)
        let saved = try await secureStore.data(forAccount: account)
        XCTAssertEqual(saved, fixture)
        try await secureStore.removeValue(forAccount: account)
        let removed = try await secureStore.data(forAccount: account)
        XCTAssertNil(removed)
    }
}
