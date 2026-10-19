import XCTest
@testable import AHUTong

final class LicenseCatalogTests: XCTestCase {
    func testCatalogDescribesIOSAndRustDependenciesRatherThanAndroidLibraries() {
        let names = IOSLicenseCatalog.entries.map(\.name)

        XCTAssertTrue(names.contains("GuiXu (Rust rewrite)"))
        XCTAssertTrue(names.contains("AHUTong Rust SDK"))
        XCTAssertFalse(names.contains("AndroidX"))
        XCTAssertFalse(names.contains("Retrofit"))
        XCTAssertFalse(names.contains("Coil"))
    }

    func testGuiXuProvidesOfflineLicenseAndNoticeDocuments() throws {
        let entry = try XCTUnwrap(
            IOSLicenseCatalog.entries.first { $0.name == "GuiXu (Rust rewrite)" }
        )

        XCTAssertEqual(entry.license, "Apache License 2.0")
        XCTAssertEqual(Set(entry.bundledDocuments), Set(["LICENSE", "NOTICE"]))
    }

    func testMaterialIconsProvidesOfflineAttribution() throws {
        let entry = try XCTUnwrap(IOSLicenseCatalog.entries.first { $0.name == "Material Icons" })
        for resource in entry.bundledDocuments {
            let url = try XCTUnwrap(
                Bundle.main.url(forResource: resource, withExtension: nil),
                "Missing bundled attribution: \(resource)"
            )
            XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).isEmpty)
        }
    }
}
