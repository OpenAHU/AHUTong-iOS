import XCTest
@testable import AHUTong

final class LicenseCatalogTests: XCTestCase {
    func testThirdPartyDependenciesProvideOfflineAttribution() throws {
        for name in ["Material Icons", "Sentry SDK 9.31.0"] {
            let entry = try XCTUnwrap(IOSLicenseCatalog.entries.first { $0.name == name })
            for resource in entry.bundledDocuments {
                let url = try XCTUnwrap(
                    Bundle.main.url(forResource: resource, withExtension: nil),
                    "Missing bundled attribution: \(resource)"
                )
                XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).isEmpty)
            }
        }
    }
}
