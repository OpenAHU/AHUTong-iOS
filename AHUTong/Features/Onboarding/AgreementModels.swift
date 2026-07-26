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
            3. 本应用仅为实现登录、教务、校园卡、天气、失物招领等用户主动使用的功能处理必要数据；处理范围和去向以隐私政策为准。
            4. 用户在使用本项目或其二次开发版本时，应自行判断安全性并承担相应风险。因非官方或非正版应用造成的财产损失，开发者不承担任何责任。
            5. 使用本应用即表示您已阅读并理解本免责声明，并同意自行承担使用风险。
            """
        case .privacy:
            """
            1. 为完成您主动使用的功能，安大通会处理姓名、学号、校园系统会话、课表、成绩等必要数据。密码、Token 和 Cookie 使用 iOS Keychain 或仅在当前操作的内存中保存。
            2. 登录、教务、校园卡、失物招领等请求会发送到安徽大学对应业务系统；天气查询会按您的授权向天气服务发送位置、城市或网络定位信息。发布失物招领时，您填写的联系人、手机号和内容会提交到校方失物招领服务。
            3. 支付功能优先使用学校官方 HTTPS 页面。安大通不会在日志、剪贴板或持久化存储中保存支付密码；未配置安全网关时不会由 App 发起原生扣款。
            4. 课表、缓存、偏好和小组件快照保存在本机或 App Group；退出登录时会清理会话和共享课表快照。用于灰度判断的学号只生成不可逆摘要，不发送原始学号。
            5. 当前版本不接入广告、跨 App 跟踪、第三方统计或崩溃上报，也不运营用于汇集用户业务数据的自有云服务。除完成您选择的功能外，不向其他第三方出售或共享个人数据。
            6. 您可以拒绝定位、通知和照片权限；对应功能会降级或不可用，但不影响其他基础功能。您也可以退出登录以清理本机会话。
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
    static let currentVersion = 2

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
