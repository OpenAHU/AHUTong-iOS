import Foundation

enum AgreementDocument: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case disclaimer
    case privacy
    case community

    var id: String { rawValue }

    var title: String {
        switch self {
        case .disclaimer:
            "温馨提示与免责声明"
        case .privacy:
            "隐私政策"
        case .community:
            "商业合作"
        }
    }

    var isRequired: Bool {
        self != .community
    }

    var summary: String {
        switch self {
        case .disclaimer:
            "了解开源版本、非官方分发和使用风险。"
        case .privacy:
            "了解账号、课表等数据的处理和本地存储方式。"
        case .community:
            "可选阅读，不影响使用应用。"
        }
    }

    var body: String {
        switch self {
        case .disclaimer:
            """
            安大通是开源项目。通过非官方渠道获得的构建版本可能被修改，请确认安装来源可信。

            应用用于访问用户主动选择的校园服务。校园系统、网络环境或第三方服务的变化可能造成查询失败、数据延迟或功能暂时不可用。

            使用者应妥善保管自己的校园账号，并在涉及缴费等写操作时再次核对金额和结果。开发版本仅用于个人测试，不应作为财务结果的唯一依据。
            """
        case .privacy:
            """
            安大通会在提供功能所必需的范围内处理校园账号标识、登录会话、课表和用户主动查询的数据。

            密码、Token 和 Cookie 只允许保存在本机 Keychain；普通偏好和课表缓存与账号隔离。请求校园服务时，必要数据会发送到对应的学校系统。

            当前 iOS 迁移版本未接入广告、第三方统计或崩溃上报。未来如处理范围发生变化，将先更新说明并重新征求同意。

            用户可通过退出账号清理会话数据，并可撤回协议同意后重新确认；卸载应用会移除应用容器中的普通本地数据。
            """
        case .community:
            """
            安大通仍在持续开发。如果你希望反馈建议、参与开发或讨论长期维护，可以加入项目社区。

            Android 项目当前公开的反馈群为 1006203134。加入社区完全自愿，不影响任何应用功能，也不会自动共享你的校园账号数据。
            """
        }
    }
}

struct AgreementConsent: Codable, Equatable, Sendable {
    static let currentVersion = 1

    var acceptedDocumentIDs: Set<String> = []
    var confirmedVersion: Int? = nil

    static let empty = AgreementConsent()

    var hasAcceptedRequiredDocuments: Bool {
        AgreementDocument.allCases
            .filter(\.isRequired)
            .allSatisfy { acceptedDocumentIDs.contains($0.id) }
    }

    var isComplete: Bool {
        hasAcceptedRequiredDocuments && confirmedVersion == Self.currentVersion
    }

    func isAccepted(_ document: AgreementDocument) -> Bool {
        acceptedDocumentIDs.contains(document.id)
    }
}
