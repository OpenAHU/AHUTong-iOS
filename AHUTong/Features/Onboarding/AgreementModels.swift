import Foundation

enum PrivacyConsentDecision: String, Codable, Equatable, Sendable {
    case unset
    case accepted
    case declined
}

enum AgreementDocument: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case disclaimer
    case privacy
    case community

    var id: String { rawValue }

    static let communityQQGroupURL = URL(
        string: "mqqapi://card/show_pslcard?src_type=internal&version=1&uin=1006203134&card_type=group&source=qrcode"
    )!

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
            "了解账号密码、Cookie、课表等数据的用途、本地存储和撤回方式。"
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
            1. 在您同意后，安大通会从安徽大学官方登录页读取您主动输入的学号和密码，并使用仅本设备可用的 iOS ThisDeviceOnly Keychain 保存。校园系统 Cookie 同样只保存在本机 Keychain。
            2. 学号、密码和 Cookie 仅用于登录 one.ahu.edu.cn、jw.ahu.edu.cn 及必要的 adwmh.ahu.edu.cn 校园服务。首次登录需要图形验证码的校园服务时，验证码必须由您在可见页面中手动填写。首次授权成功后，只要您未撤回同意，后续 Cookie 过期时 App 可启动隐藏 WebView，自动填入本机保存的账密，并将当次校方验证码图片发送到 openahu.org 的远程验证码识别接口，使用返回的识别文本帮助填入验证码，以恢复会话。
            3. 远程验证码识别请求只包含当次验证码图片，不附带学号、密码、Cookie、Token 或其他校园业务数据。App 不将验证码图片或识别结果保存到本机文件、日志或诊断中；远程接口仅得将该数据用于本次验证码识别。识别失败、结果不可靠、出现设备验证或校方页面变化时，App 会转为可见页面，由您手动完成登录。
            4. 账号、密码、Token 和 Cookie 不会进入日志、诊断、剪贴板、iCloud 备份或开发者服务器，也不会发送给验证码识别接口、统计或广告服务。安大通不将这些凭据用于校园服务登录以外的用途。
            5. 登录、教务、校园卡、失物招领等请求会直接发送到安徽大学对应业务系统；天气查询会按您的授权向天气服务发送必要的位置或城市信息。
            6. 支付功能仅在您主动确认后通过学校 HTTPS 接口提交。校园卡六位密码只在当前操作的内存中短暂存在，完成后立即清除。
            7. 课表、缓存、偏好和小组件快照保存在本机或 App Group。您拒绝或在设置中撤回同意后，App 会删除账号密码和校园 Cookie，并切换为“安大通体验用户”。之前缓存或手动导入的课表会保留，直到您清除缓存或重新导入。
            8. 拒绝本政策仍可使用体验账户的课表和设置；其他需要真实校园身份的功能不可用。您可随时在设置中重新同意或撤回同意。
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
    static let currentVersion = 3
    static let currentPrivacyPolicyVersion = 3

    var acceptedDocumentIDs: Set<String> = []
    var confirmedVersion: Int? = nil
    var privacyDecision: PrivacyConsentDecision = .unset
    var privacyPolicyVersion: Int? = nil

    static let empty = AgreementConsent()

    var hasAcceptedRequiredDocuments: Bool {
        acceptedDocumentIDs.contains(AgreementDocument.disclaimer.id)
            && privacyDecision == .accepted
    }

    var hasResolvedRequiredDocuments: Bool {
        acceptedDocumentIDs.contains(AgreementDocument.disclaimer.id)
            && privacyDecision != .unset
    }

    var isComplete: Bool {
        hasResolvedRequiredDocuments
            && privacyPolicyVersion == Self.currentPrivacyPolicyVersion
            && confirmedVersion == Self.currentVersion
    }

    func isAccepted(_ document: AgreementDocument) -> Bool {
        if document == .privacy {
            return privacyDecision == .accepted
        }
        return acceptedDocumentIDs.contains(document.id)
    }

    enum CodingKeys: String, CodingKey {
        case acceptedDocumentIDs
        case confirmedVersion
        case privacyDecision
        case privacyPolicyVersion
    }

    init(
        acceptedDocumentIDs: Set<String> = [],
        confirmedVersion: Int? = nil,
        privacyDecision: PrivacyConsentDecision = .unset,
        privacyPolicyVersion: Int? = nil
    ) {
        self.acceptedDocumentIDs = acceptedDocumentIDs
        self.confirmedVersion = confirmedVersion
        self.privacyDecision = privacyDecision
        self.privacyPolicyVersion = privacyPolicyVersion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        acceptedDocumentIDs = try container.decodeIfPresent(
            Set<String>.self,
            forKey: .acceptedDocumentIDs
        ) ?? []
        confirmedVersion = try container.decodeIfPresent(Int.self, forKey: .confirmedVersion)
        privacyDecision = try container.decodeIfPresent(
            PrivacyConsentDecision.self,
            forKey: .privacyDecision
        ) ?? .unset
        privacyPolicyVersion = try container.decodeIfPresent(Int.self, forKey: .privacyPolicyVersion)
    }
}
