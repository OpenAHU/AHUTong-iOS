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
            1. 本项目完全开源，任何人均可基于本项目进行二次开发或分发。
            2. 由于开源特性，非官方渠道下载或安装的应用可能存在安全风险，请务必确保应用来源可信。
            3. 本项目不会收集、存储或泄露用户的任何个人信息，也不会侵犯用户的合法权利。
            4. 用户在使用本项目或其二次开发版本时，应自行判断安全性并承担相应风险。因非官方或非正版应用造成的财产损失，开发者不承担任何责任。
            5. 使用本应用即表示您已阅读并理解本免责声明，并同意自行承担使用风险。
            """
        case .privacy:
            """
            1. 安大通不会将您的用户数据上传到云服务器。
            2. 安大通会记录运行时的软件内（仅限安大通）页面信息，用于分析用户群体的使用习惯，并及时做功能调整。
            3. 安大通记录的页面信息中，不包括您的个人数据。
            4. 一切您的个人数据，不会被分享至第三方（学校属于两方平台）。

            截止2025/11/09，安大通并未实现上传数据等相关功能。目前该功能处于试验阶段，记录到的数据仅存储在本地，依赖 iOS 的应用容器隔离保障安全性。
            """
        case .community:
            """
            目前安大通的商业价值处于探索阶段，为了持久化发展、优化广大同学的体验，急需几名大一/大二的同学做发展规划。
            如果您有兴趣，欢迎联系我们！QQ群1006203134
            另外，如果您对安大通有任何想法或建议，也欢迎加群反馈！
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
