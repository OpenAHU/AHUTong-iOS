import Foundation

/// Provisioning metadata is only a hint for re-signed builds. It never grants
/// access: FileManager must still authorize the selected container. Store builds
/// and normal developer builds use the configured group without a profile.
struct WidgetProvisioningGroups: Equatable, Sendable {
    let team: String
    let groups: Set<String>

    init?(data: Data) {
        // Embedded profiles currently contain an XML plist in a CMS envelope.
        // This optional compatibility path fails closed if that format changes.
        guard data.count <= 1_048_576,
              let start = data.range(of: Data("<plist".utf8)),
              let end = data.range(of: Data("</plist>".utf8), in: start.lowerBound..<data.endIndex),
              let plist = try? PropertyListSerialization.propertyList(
                from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil
              ) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any],
              let team = entitlements["com.apple.developer.team-identifier"] as? String,
              !team.isEmpty else { return nil }
        self.team = team
        groups = Set((entitlements["com.apple.security.application-groups"] as? [String] ?? []).filter {
            $0.hasPrefix("group.") && !$0.contains("*") && !$0.contains("$(") && !$0.contains(where: \.isWhitespace)
        })
    }
}

struct WidgetSharingConfiguration: Sendable {
    let configuredGroup: String
    let widgetGroup: String?
    let appProfile: WidgetProvisioningGroups?
    let widgetProfile: WidgetProvisioningGroups?
    let widgetPresent: Bool
    var appBundleID: String? = nil
    var widgetBundleID: String? = nil

    static func bundled(in bundle: Bundle = .main) -> Self {
        let appURL = bundle.bundleURL.pathExtension == "appex"
            ? bundle.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            : bundle.bundleURL
        let app = Bundle(url: appURL)
        let plugins = (try? FileManager.default.contentsOfDirectory(
            at: appURL.appendingPathComponent("PlugIns"), includingPropertiesForKeys: nil
        )) ?? []
        let widgets = plugins.compactMap { Bundle(url: $0) }.filter {
            ($0.object(forInfoDictionaryKey: "NSExtension") as? [String: Any])?["NSExtensionPointIdentifier"] as? String
                == "com.apple.widgetkit-extension"
        }
        let widget = widgets.count == 1 ? widgets.first : nil
        return Self(
            configuredGroup: app?.object(forInfoDictionaryKey: "AHUTongAppGroupIdentifier") as? String
                ?? "group.com.openahu.ahutong.shared",
            widgetGroup: widget?.object(forInfoDictionaryKey: "AHUTongAppGroupIdentifier") as? String,
            appProfile: profile(at: appURL),
            widgetProfile: widget.flatMap { profile(at: $0.bundleURL) },
            widgetPresent: widget != nil,
            appBundleID: app?.bundleIdentifier,
            widgetBundleID: widget?.bundleIdentifier
        )
    }

    private static func profile(at bundleURL: URL) -> WidgetProvisioningGroups? {
        let url = bundleURL.appendingPathComponent("embedded.mobileprovision")
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              size <= 1_048_576, let data = try? Data(contentsOf: url) else { return nil }
        return WidgetProvisioningGroups(data: data)
    }
}

struct WidgetSharingResolution: Sendable {
    enum Issue: String, Sendable {
        case missingWidget, mismatchedConfiguration, unavailableProfiles, mismatchedTeams
        case noCommonGroup, ambiguousGroups, accessDenied

        var guidance: String {
            switch self {
            case .missingWidget: "安装包未保留课表小组件，请在重签时保留扩展。"
            case .mismatchedConfiguration: "App 与小组件的共享组配置不一致，请重新打包。"
            case .unavailableProfiles: "无法确认安装的共享权限，请在签名时为 App 和课表小组件启用同一 App Group。"
            case .mismatchedTeams: "App 与小组件未使用同一签名团队，请重新签名。"
            case .noCommonGroup: "App 与课表小组件没有共同的 App Group，请在签名时为两者启用同一共享组。"
            case .ambiguousGroups: "安装中存在多个共同共享组，请在打包时明确指定课表使用的 App Group。"
            case .accessDenied: "系统未允许访问课表共享组，请检查 App 和小组件的 App Group 签名权限。"
            }
        }
    }

    let configuration: WidgetSharingConfiguration
    let group: String?
    let containerURL: URL?
    let issue: Issue?

    static func resolve(
        _ configuration: WidgetSharingConfiguration,
        container: (String) -> URL?
    ) -> Self {
        func result(_ group: String? = nil, _ url: URL? = nil, issue: Issue? = nil) -> Self {
            Self(configuration: configuration, group: group, containerURL: url, issue: issue)
        }
        guard configuration.widgetPresent else { return result(issue: .missingWidget) }
        guard configuration.widgetGroup == configuration.configuredGroup else {
            return result(issue: .mismatchedConfiguration)
        }
        guard let app = configuration.appProfile, let widget = configuration.widgetProfile else {
            if let url = container(configuration.configuredGroup) {
                return result(configuration.configuredGroup, url)
            }
            return result(issue: .unavailableProfiles)
        }
        guard app.team == widget.team else { return result(issue: .mismatchedTeams) }
        let common = app.groups.intersection(widget.groups)
        guard !common.isEmpty else { return result(issue: .noCommonGroup) }
        if common.contains(configuration.configuredGroup), let url = container(configuration.configuredGroup) {
            return result(configuration.configuredGroup, url)
        }
        // Never pick an arbitrary group, or different groups in the two processes.
        guard common.count == 1, let candidate = common.first else {
            return result(issue: .ambiguousGroups)
        }
        guard candidate != configuration.configuredGroup, let url = container(candidate) else {
            return result(issue: .accessDenied)
        }
        return result(candidate, url)
    }

    /// Explicitly assembled allowlist: never export a profile, account, device
    /// identifier, certificate, container path, course, or authentication data.
    var diagnosticSummary: String {
        func groupNames(_ profile: WidgetProvisioningGroups?) -> String {
            guard let profile else { return "unavailable" }
            return profile.groups.isEmpty ? "none" : profile.groups.sorted().joined(separator: ", ")
        }
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"
        return """
        AHUTong Widget sharing check v1
        App version: \(version) (\(build))
        App bundle ID: \(configuration.appBundleID ?? "unavailable")
        Widget bundle ID: \(configuration.widgetBundleID ?? "unavailable")
        Widget extension: \(configuration.widgetPresent ? "present" : "missing")
        Configured group: \(configuration.configuredGroup)
        Widget configured group: \(configuration.widgetGroup ?? "missing")
        App profile groups: \(groupNames(configuration.appProfile))
        Widget profile groups: \(groupNames(configuration.widgetProfile))
        Same profile team: \(configuration.appProfile != nil && configuration.widgetProfile != nil && configuration.appProfile?.team == configuration.widgetProfile?.team)
        Resolved group: \(group ?? "none")
        Container available: \(containerURL != nil)
        Result: \(issue?.rawValue ?? "ready")
        """
    }
}
