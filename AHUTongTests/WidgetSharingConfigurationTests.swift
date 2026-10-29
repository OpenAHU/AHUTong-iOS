import XCTest
@testable import AHUTong

final class WidgetSharingConfigurationTests: XCTestCase {
    private let original = "group.example.shared"
    private let renamed = "group.example.resigned.shared"
    private let sharedURL = URL(fileURLWithPath: "/shared-test-container")

    func testConfiguredGroupWorksWithoutEmbeddedProfiles() {
        let result = WidgetSharingResolution.resolve(configuration()) { $0 == self.original ? self.sharedURL : nil }
        XCTAssertEqual(result.group, original)
        XCTAssertNil(result.issue)
    }

    func testConfiguredGroupWinsOverOtherAuthorizedGroups() throws {
        let profile = try makeProfile(groups: [original, renamed])
        let result = WidgetSharingResolution.resolve(configuration(app: profile, widget: profile)) { _ in self.sharedURL }
        XCTAssertEqual(result.group, original)
    }

    func testResolvesOnlyTheCommonRenamedGroup() throws {
        let app = try makeProfile(groups: [renamed, "group.example.app-only"])
        let widget = try makeProfile(groups: [renamed, "group.example.widget-only"])
        let result = WidgetSharingResolution.resolve(configuration(app: app, widget: widget)) {
            $0 == self.renamed ? self.sharedURL : nil
        }
        XCTAssertEqual(result.group, renamed)
        XCTAssertEqual(result.containerURL, sharedURL)
        XCTAssertNil(result.issue)
    }

    func testProfileDoesNotGrantAccessToTheContainer() throws {
        let profile = try makeProfile(groups: [renamed])
        let result = WidgetSharingResolution.resolve(configuration(app: profile, widget: profile)) { _ in nil }
        XCTAssertEqual(result.issue, .accessDenied)
        XCTAssertNil(result.containerURL)
    }

    func testDeniedConfiguredGroupDoesNotFallBackToPrivateStorage() throws {
        let profile = try makeProfile(groups: [original])
        let result = WidgetSharingResolution.resolve(configuration(app: profile, widget: profile)) { _ in nil }
        XCTAssertEqual(result.issue, .accessDenied)
        XCTAssertNil(result.containerURL)
    }

    func testMultipleCommonGroupsAreNotChosenArbitrarily() throws {
        let profile = try makeProfile(groups: [renamed, "group.example.another"])
        let result = WidgetSharingResolution.resolve(configuration(app: profile, widget: profile)) { _ in self.sharedURL }
        XCTAssertEqual(result.issue, .ambiguousGroups)
        XCTAssertNil(result.group)
    }

    func testUnrelatedOrMissingGroupOnWidgetIsRejectedEvenIfAppCanAccessItsGroup() throws {
        for groups in [[String](), ["group.example.unrelated"]] {
            let app = try makeProfile(groups: [original])
            let widget = try makeProfile(groups: groups)
            let result = WidgetSharingResolution.resolve(configuration(app: app, widget: widget)) { _ in self.sharedURL }
            XCTAssertEqual(result.issue, .noCommonGroup)
        }
    }

    func testDifferentSigningTeamsAreRejected() throws {
        let app = try makeProfile(groups: [renamed])
        let widget = try makeProfile(groups: [renamed], team: "OTHERTEAM")
        let result = WidgetSharingResolution.resolve(configuration(app: app, widget: widget)) { _ in self.sharedURL }
        XCTAssertEqual(result.issue, .mismatchedTeams)
    }

    func testMissingWidgetAndDifferentConfiguredGroupsHaveSpecificGuidance() {
        let missing = WidgetSharingConfiguration(configuredGroup: original, widgetGroup: nil,
            appProfile: nil, widgetProfile: nil, widgetPresent: false)
        XCTAssertEqual(WidgetSharingResolution.resolve(missing) { _ in self.sharedURL }.issue, .missingWidget)
        let mismatch = WidgetSharingConfiguration(configuredGroup: original, widgetGroup: renamed,
            appProfile: nil, widgetProfile: nil, widgetPresent: true)
        XCTAssertEqual(WidgetSharingResolution.resolve(mismatch) { _ in self.sharedURL }.issue, .mismatchedConfiguration)
    }

    func testMissingProfilesDoNotInventASharedGroup() {
        let result = WidgetSharingResolution.resolve(configuration()) { _ in nil }
        XCTAssertEqual(result.issue, .unavailableProfiles)
        XCTAssertNil(result.group)
        XCTAssertTrue(result.diagnosticSummary.contains("Same profile team: unknown"))
    }

    func testReportedResignedInstallationHasSpecificMissingAppGroupGuidance() throws {
        let app = try makeProfile(groups: [])
        let result = WidgetSharingResolution.resolve(configuration(app: app, widget: nil)) { _ in nil }
        XCTAssertEqual(result.issue, .appGroupNotProvisioned)
        XCTAssertNil(result.containerURL)
        XCTAssertTrue(result.diagnosticSummary.contains("App profile groups: none"))
        XCTAssertTrue(result.diagnosticSummary.contains("Widget profile groups: unavailable"))
        XCTAssertTrue(result.diagnosticSummary.contains("Same profile team: unknown"))
    }

    func testProfileReaderIgnoresWildcardsAndUnresolvedOrMalformedGroups() throws {
        let profile = try makeProfile(groups: [renamed, renamed, "*", "group.*", "group.$(TEAM).shared", "bad", "group.bad name"])
        XCTAssertEqual(profile.groups, [renamed])
    }

    func testMalformedOrOversizedProfileFailsClosed() {
        for data in [Data(), Data("<plist>garbage</plist>".utf8), Data("<plist>".utf8), Data(repeating: 0, count: 1_048_577)] {
            XCTAssertNil(WidgetProvisioningGroups(data: data))
        }
    }

    func testDiagnosticsExcludePrivateProfileFieldsAndPaths() throws {
        let profile = try makeProfile(groups: [renamed])
        let result = WidgetSharingResolution.resolve(configuration(app: profile, widget: profile)) { _ in self.sharedURL }
        let report = result.diagnosticSummary
        XCTAssertTrue(report.contains(renamed))
        XCTAssertTrue(report.contains("Result: ready"))
        for value in ["PRIVATE-DEVICE", "PRIVATE-ACCOUNT", "PRIVATE-CERT", "TESTTEAM", sharedURL.path] {
            XCTAssertFalse(report.contains(value), value)
        }
    }

    func testHostAndExtensionDiscoverSameResignedGroupAndShareSnapshot() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Test.app")
        let widget = app.appendingPathComponent("PlugIns/TestWidget.appex")
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "example.app", "AHUTongAppGroupIdentifier": original],
            format: .xml, options: 0).write(to: app.appendingPathComponent("Info.plist"))
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "example.app.widget", "AHUTongAppGroupIdentifier": original,
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"]], format: .xml, options: 0)
            .write(to: widget.appendingPathComponent("Info.plist"))
        try profileData(groups: [renamed, "group.example.host-only"]).write(to: app.appendingPathComponent("embedded.mobileprovision"))
        try profileData(groups: [renamed, "group.example.widget-only"]).write(to: widget.appendingPathComponent("embedded.mobileprovision"))
        let host = WidgetSharingConfiguration.bundled(in: try XCTUnwrap(Bundle(url: app)))
        let extensionConfig = WidgetSharingConfiguration.bundled(in: try XCTUnwrap(Bundle(url: widget)))
        XCTAssertTrue(host.widgetPresent)
        XCTAssertEqual(host.configuredGroup, original)
        XCTAssertEqual(host.widgetGroup, extensionConfig.widgetGroup)
        XCTAssertEqual(host.configuredGroup, extensionConfig.configuredGroup)
        let container = root.appendingPathComponent("shared")
        let writer = WidgetSharingResolution.resolve(host) { $0 == self.renamed ? container : nil }
        let reader = WidgetSharingResolution.resolve(extensionConfig) { $0 == self.renamed ? container : nil }
        XCTAssertEqual(writer.group, renamed)
        XCTAssertEqual(writer.containerURL, reader.containerURL)
        XCTAssertEqual(reader.group, renamed)
        let expected = ScheduleWidgetSnapshot.make(courses: [Course(weekday: 2, startWeek: 1, endWeek: 20,
            location: "A301", name: "移动开发", teacher: "", duration: 2, startPeriod: 1,
            courseID: "shared-course", weekIndexes: [7])], currentWeek: 7)
        try await ScheduleWidgetSnapshotStore(containerURL: writer.containerURL).save(expected)
        let snapshot = await ScheduleWidgetSnapshotStore(containerURL: reader.containerURL).load()
        XCTAssertEqual(snapshot, expected)
    }

    private func configuration(app: WidgetProvisioningGroups? = nil, widget: WidgetProvisioningGroups? = nil) -> WidgetSharingConfiguration {
        WidgetSharingConfiguration(configuredGroup: original, widgetGroup: original,
            appProfile: app, widgetProfile: widget, widgetPresent: true)
    }

    private func makeProfile(groups: [String], team: String = "TESTTEAM") throws -> WidgetProvisioningGroups {
        try XCTUnwrap(WidgetProvisioningGroups(data: profileData(groups: groups, team: team)))
    }

    private func profileData(groups: [String], team: String = "TESTTEAM") throws -> Data {
        let plist: [String: Any] = ["Entitlements": ["com.apple.developer.team-identifier": team,
            "com.apple.security.application-groups": groups], "ProvisionedDevices": ["PRIVATE-DEVICE"],
            "Name": "PRIVATE-ACCOUNT", "DeveloperCertificates": [Data("PRIVATE-CERT".utf8)]]
        var envelope = Data([0x30, 0x82, 0x00, 0x01])
        envelope.append(try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0))
        envelope.append(contentsOf: [0x00, 0xff])
        return envelope
    }
}
