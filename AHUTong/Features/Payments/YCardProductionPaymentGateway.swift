import CryptoKit
import Foundation

enum YCardProductionPaymentError: LocalizedError, Equatable, Sendable {
    case disallowedEndpoint
    case credentialsUnavailable
    case automatedDebitDisabled
    case invalidRequest
    case invalidResponse
    case rejected
    case timedOut
    case unknownResult

    var errorDescription: String? {
        switch self {
        case .disallowedEndpoint:
            "已阻止不符合校园卡生产协议的请求"
        case .credentialsUnavailable:
            "校园卡登录状态已失效，请重新登录后重试"
        case .automatedDebitDisabled:
            "自动化环境禁止连接真实扣款接口"
        case .invalidRequest:
            "支付请求格式无效，未发起扣款"
        case .invalidResponse:
            "学校支付服务返回了无法识别的数据"
        case .rejected:
            "学校支付服务拒绝了本次请求"
        case .timedOut:
            "支付请求超时，订单结果待确认，请勿重复提交"
        case .unknownResult:
            "订单结果暂时无法确认，请勿重复提交"
        }
    }
}

struct YCardPaymentFormField: Equatable, Sendable {
    let name: String
    let value: String

    init(_ name: String, _ value: String) {
        self.name = name
        self.value = value
    }
}

struct YCardSignedForm: Equatable, Sendable {
    let fields: [YCardPaymentFormField]

    var signature: String? {
        fields.first(where: { $0.name == "SIGN" })?.value
    }
}

private enum YCardClientProtocolMaterial {
    // Android production compatibility material. Never log, persist, reflect,
    // interpolate into errors, or expose outside this translation unit.
    static let appID = "56321"
    static let secretKey = "0osTIhce7uPvDKHz6aa67bhCukaKoYl4"
    static let cardRedirectURL = "https://ycard.ahu.edu.cn/payment/?name=result"
    static let chargeRedirectURL = "https://ycard.ahu.edu.cn/plat"
    static let bathroomUUID = "da07e4442e4841cca1655cb29653a023"
    static let bathroomPermutation = "1690457382"
    static let networkEntryAppID = "75"
    static let signType = "SHA256"
}

struct YCardProductionPaymentSigner: Sendable {
    typealias Clock = @Sendable () -> Date
    typealias Nonce = @Sendable () -> String

    private let clock: Clock
    private let nonce: Nonce
    private let timeZone: TimeZone

    init(
        clock: @escaping Clock = { Date() },
        nonce: @escaping Nonce = { Self.randomNonce() },
        timeZone: TimeZone = .current
    ) {
        self.clock = clock
        self.nonce = nonce
        self.timeZone = timeZone
    }

    func cardCreate(amount: String, cardType: String) throws -> YCardSignedForm {
        let metadata = try makeMetadata()
        let business = [
            YCardPaymentFormField("feeitemid", "401"),
            YCardPaymentFormField("appid", YCardClientProtocolMaterial.appID),
            YCardPaymentFormField("tranamt", amount),
            YCardPaymentFormField("source", "app"),
            YCardPaymentFormField("yktcard", cardType),
            YCardPaymentFormField("synAccessSource", "h5")
        ]
        try validateAmount(amount)
        try validateOpaqueIdentifier(cardType)
        let signingFields = [
            YCardPaymentFormField("APP_ID", YCardClientProtocolMaterial.appID),
            YCardPaymentFormField("NONCE", metadata.nonce),
            YCardPaymentFormField("SIGN_TYPE", YCardClientProtocolMaterial.signType),
            YCardPaymentFormField("TIMESTAMP", metadata.timestamp)
        ] + business.sorted { $0.name < $1.name }
        let signature = Self.signature(for: signingFields)
        return YCardSignedForm(fields: business + metadata.bodyFields(signature: signature))
    }

    func cardBankSubmit(orderID: String) throws -> YCardSignedForm {
        try validateOrderID(orderID)
        let metadata = try makeMetadata()
        let signedBusiness = [
            YCardPaymentFormField("orderid", orderID),
            YCardPaymentFormField("paystep", "2"),
            YCardPaymentFormField("paytype", "BANKCARD"),
            YCardPaymentFormField("paytypeid", "63"),
            YCardPaymentFormField("redirect_url", YCardClientProtocolMaterial.cardRedirectURL),
            YCardPaymentFormField("userAgent", "h5")
        ]
        let signingFields = [
            YCardPaymentFormField("APP_ID", YCardClientProtocolMaterial.appID),
            YCardPaymentFormField("NONCE", metadata.nonce),
            YCardPaymentFormField("SIGN_TYPE", YCardClientProtocolMaterial.signType),
            YCardPaymentFormField("TIMESTAMP", metadata.timestamp)
        ] + signedBusiness
        let signature = Self.signature(for: signingFields)
        let body = [
            YCardPaymentFormField("paytypeid", "63"),
            YCardPaymentFormField("paytype", "BANKCARD"),
            YCardPaymentFormField("paystep", "2"),
            YCardPaymentFormField("orderid", orderID),
            YCardPaymentFormField("redirect_url", YCardClientProtocolMaterial.cardRedirectURL),
            YCardPaymentFormField("userAgent", "h5")
        ] + metadata.bodyFields(signature: signature) + [
            // Android sends this body field after SIGN but intentionally omits
            // it from the CardPay signing source.
            YCardPaymentFormField("synAccessSource", "h5")
        ]
        return YCardSignedForm(fields: body)
    }

    func chargeCreate(
        feeItemID: String,
        amount: String,
        thirdPartyJSON: String
    ) throws -> YCardSignedForm {
        guard feeItemID == "488" || feeItemID == "431",
              Self.isJSONObject(thirdPartyJSON) else {
            throw YCardProductionPaymentError.invalidRequest
        }
        try validateAmount(amount)
        return try signedChargeForm([
            YCardPaymentFormField("feeitemid", feeItemID),
            YCardPaymentFormField("tranamt", amount),
            YCardPaymentFormField("flag", "choose"),
            YCardPaymentFormField("source", "app"),
            YCardPaymentFormField("paystep", "0"),
            YCardPaymentFormField("abstracts", ""),
            YCardPaymentFormField("redirect_url", YCardClientProtocolMaterial.chargeRedirectURL),
            YCardPaymentFormField("third_party", thirdPartyJSON)
        ])
    }

    func dynamicKeyboardRequest(orderID: String) throws -> YCardSignedForm {
        try validateOrderID(orderID)
        return try signedChargeForm([
            YCardPaymentFormField("paytypeid", "64"),
            YCardPaymentFormField("paytype", "ACCOUNTTSM"),
            YCardPaymentFormField("paystep", "2"),
            YCardPaymentFormField("orderid", orderID)
        ])
    }

    func campusAccountSubmitBase(
        orderID: String,
        uuid: String
    ) throws -> [YCardPaymentFormField] {
        try validateOrderID(orderID)
        try validateUUID(uuid)
        return [
            YCardPaymentFormField("orderid", orderID),
            YCardPaymentFormField("paystep", "2"),
            YCardPaymentFormField("paytype", "ACCOUNTTSM"),
            YCardPaymentFormField("paytypeid", "64"),
            YCardPaymentFormField("userAgent", "h5"),
            YCardPaymentFormField("ccctype", "000"),
            YCardPaymentFormField("uuid", uuid),
            YCardPaymentFormField("isWX", "0")
        ]
    }

    func signedCampusAccountSubmit(
        orderID: String,
        uuid: String,
        mappedPassword: String
    ) throws -> YCardSignedForm {
        guard Self.isSixASCIIDigits(mappedPassword) else {
            throw YCardProductionPaymentError.invalidRequest
        }
        let base = try campusAccountSubmitBase(orderID: orderID, uuid: uuid)
        let fields = Array(base.prefix(6)) + [
            YCardPaymentFormField("password", mappedPassword)
        ] + Array(base.suffix(2))
        return try signedChargeForm(fields)
    }

    func signedChargeForm(
        _ businessFields: [YCardPaymentFormField]
    ) throws -> YCardSignedForm {
        try Self.validateUniqueFields(businessFields)
        let metadata = try makeMetadata()
        let signingFields = [
            YCardPaymentFormField("APP_ID", YCardClientProtocolMaterial.appID),
            YCardPaymentFormField("NONCE", metadata.nonce),
            YCardPaymentFormField("SIGN_TYPE", YCardClientProtocolMaterial.signType),
            YCardPaymentFormField("TIMESTAMP", metadata.timestamp)
        ] + businessFields
            .filter { !$0.value.isEmpty }
            .sorted { lhs, rhs in lhs.name < rhs.name }
        let signature = Self.signature(for: signingFields)
        return YCardSignedForm(
            fields: businessFields + metadata.bodyFields(signature: signature)
        )
    }

    static func verifyProductionConstantFingerprints() -> Bool {
        fingerprint(YCardClientProtocolMaterial.appID) == "15296142be6dbb84aad4a8525aa31e9d075b02b8e01f8774952e1c49e45cc095"
            && YCardClientProtocolMaterial.appID.utf8.count == 5
            && fingerprint(YCardClientProtocolMaterial.secretKey) == "7b355975da02d97e4713e35f037b1d202c36b25f25c77c49e872a5c90dac8f37"
            && YCardClientProtocolMaterial.secretKey.utf8.count == 32
    }

    static func verifiesCardCreate(_ form: [String: String]) -> Bool {
        guard let appID = form["APP_ID"],
              let nonce = form["NONCE"],
              let signType = form["SIGN_TYPE"],
              let timestamp = form["TIMESTAMP"],
              let signature = form["SIGN"] else { return false }
        let businessNames = [
            "appid", "feeitemid", "source", "synAccessSource", "tranamt", "yktcard"
        ]
        guard businessNames.allSatisfy({ form[$0] != nil }) else { return false }
        let fields = [
            YCardPaymentFormField("APP_ID", appID),
            YCardPaymentFormField("NONCE", nonce),
            YCardPaymentFormField("SIGN_TYPE", signType),
            YCardPaymentFormField("TIMESTAMP", timestamp)
        ] + businessNames.map { YCardPaymentFormField($0, form[$0]!) }
        return Self.signature(for: fields) == signature
    }

    static func verifiesCardBankSubmit(_ form: [String: String]) -> Bool {
        guard let appID = form["APP_ID"],
              let nonce = form["NONCE"],
              let signType = form["SIGN_TYPE"],
              let timestamp = form["TIMESTAMP"],
              let signature = form["SIGN"] else { return false }
        let businessNames = [
            "orderid", "paystep", "paytype", "paytypeid", "redirect_url", "userAgent"
        ]
        guard businessNames.allSatisfy({ form[$0] != nil }) else { return false }
        let fields = [
            YCardPaymentFormField("APP_ID", appID),
            YCardPaymentFormField("NONCE", nonce),
            YCardPaymentFormField("SIGN_TYPE", signType),
            YCardPaymentFormField("TIMESTAMP", timestamp)
        ] + businessNames.map { YCardPaymentFormField($0, form[$0]!) }
        return Self.signature(for: fields) == signature
    }

    static func verifiesGeneralSignedForm(_ form: [String: String]) -> Bool {
        guard let appID = form["APP_ID"],
              let nonce = form["NONCE"],
              let signType = form["SIGN_TYPE"],
              let timestamp = form["TIMESTAMP"],
              let signature = form["SIGN"] else { return false }
        let metadata = Set(["APP_ID", "NONCE", "SIGN_TYPE", "TIMESTAMP", "SIGN"])
        let business = form
            .filter { !metadata.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key < $1.key }
            .map { YCardPaymentFormField($0.key, $0.value) }
        let fields = [
            YCardPaymentFormField("APP_ID", appID),
            YCardPaymentFormField("NONCE", nonce),
            YCardPaymentFormField("SIGN_TYPE", signType),
            YCardPaymentFormField("TIMESTAMP", timestamp)
        ] + business
        return Self.signature(for: fields) == signature
    }

    private func makeMetadata() throws -> SigningMetadata {
        let timestamp = Self.timestamp(clock(), timeZone: timeZone)
        let nonce = nonce()
        guard timestamp.count == 14,
              timestamp.allSatisfy({ $0.isASCIIDigit }),
              nonce.utf8.count == 11,
              nonce.utf8.allSatisfy({
                  (48...57).contains($0) || (97...122).contains($0)
              }) else {
            throw YCardProductionPaymentError.invalidRequest
        }
        return SigningMetadata(timestamp: timestamp, nonce: nonce)
    }

    private static func signature(for fields: [YCardPaymentFormField]) -> String {
        let canonical = fields
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "&")
            + "&SECRET_KEY=\(YCardClientProtocolMaterial.secretKey)"
        return fingerprint(canonical).uppercased()
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func timestamp(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMddHHmmss"
        return formatter.string(from: date)
    }

    private static func randomNonce() -> String {
        let alphabet = Array("0123456789abcdefghijklmnopqrstuvwxyz".utf8)
        var generator = SystemRandomNumberGenerator()
        return String(decoding: (0..<11).map { _ in
            alphabet.randomElement(using: &generator) ?? 48
        }, as: UTF8.self)
    }

    private func validateAmount(_ value: String) throws {
        guard value.range(
            of: #"^\d+(?:\.\d{1,2})?$"#,
            options: .regularExpression
        ) != nil,
        let amount = Decimal(
            string: value,
            locale: Locale(identifier: "en_US_POSIX")
        ),
        amount > 0 else {
            throw YCardProductionPaymentError.invalidRequest
        }
    }

    private func validateOrderID(_ value: String) throws {
        try validateOpaqueIdentifier(value)
    }

    private func validateOpaqueIdentifier(_ value: String) throws {
        guard !value.isEmpty,
              value.utf8.count <= 256,
              value.unicodeScalars.allSatisfy({ scalar in
                  scalar.value >= 0x21 && scalar.value <= 0x7e
              }) else {
            throw YCardProductionPaymentError.invalidRequest
        }
    }

    private func validateUUID(_ value: String) throws {
        guard value.utf8.count == 32,
              value.utf8.allSatisfy({ byte in
                  (48...57).contains(byte)
                      || (65...70).contains(byte)
                      || (97...102).contains(byte)
              }) else {
            throw YCardProductionPaymentError.invalidRequest
        }
    }

    private static func validateUniqueFields(
        _ fields: [YCardPaymentFormField]
    ) throws {
        guard Set(fields.map(\.name)).count == fields.count,
              fields.allSatisfy({ !$0.name.isEmpty }) else {
            throw YCardProductionPaymentError.invalidRequest
        }
    }

    private static func isSixASCIIDigits(_ value: String) -> Bool {
        value.utf8.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isJSONObject(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return false
        }
        return object is [String: Any]
    }

    private struct SigningMetadata: Sendable {
        let timestamp: String
        let nonce: String

        func bodyFields(signature: String) -> [YCardPaymentFormField] {
            [
                YCardPaymentFormField("APP_ID", YCardClientProtocolMaterial.appID),
                YCardPaymentFormField("TIMESTAMP", timestamp),
                YCardPaymentFormField("SIGN_TYPE", YCardClientProtocolMaterial.signType),
                YCardPaymentFormField("NONCE", nonce),
                YCardPaymentFormField("SIGN", signature)
            ]
        }
    }
}

enum YCardSecureKeyboardMapper {
    static func bathroomPreparation(
        authorization: inout [UInt8]
    ) throws -> (uuid: String, mapped: [UInt8]) {
        (
            uuid: YCardClientProtocolMaterial.bathroomUUID,
            mapped: try map(
                authorization: &authorization,
                permutation: YCardClientProtocolMaterial.bathroomPermutation
            )
        )
    }

    static func dynamicPreparation(
        authorization: inout [UInt8],
        passwordMap: [String: String]
    ) throws -> (uuid: String, mapped: [UInt8]) {
        guard passwordMap.count == 1,
              let entry = passwordMap.first,
              entry.key.utf8.count == 32,
              entry.key.utf8.allSatisfy({ byte in
                  (48...57).contains(byte)
                      || (65...70).contains(byte)
                      || (97...102).contains(byte)
              }) else {
            Self.clear(&authorization)
            throw YCardProductionPaymentError.invalidResponse
        }
        return (
            uuid: entry.key,
            mapped: try map(
                authorization: &authorization,
                permutation: entry.value
            )
        )
    }

    static func map(
        authorization: inout [UInt8],
        permutation: String
    ) throws -> [UInt8] {
        defer { clear(&authorization) }
        guard authorization.count == 6,
              authorization.allSatisfy({ (48...57).contains($0) }) else {
            throw YCardProductionPaymentError.invalidRequest
        }
        let mapBytes = Array(permutation.utf8)
        guard mapBytes.count == 10,
              Set(mapBytes) == Set(Array("0123456789".utf8)) else {
            throw YCardProductionPaymentError.invalidResponse
        }
        var inverse: [UInt8: UInt8] = [:]
        inverse.reserveCapacity(10)
        for (index, cipherDigit) in mapBytes.enumerated() {
            inverse[cipherDigit] = UInt8(index) + 48
        }
        var mapped = [UInt8]()
        mapped.reserveCapacity(authorization.count)
        for digit in authorization {
            guard let replacement = inverse[digit] else {
                clear(&mapped)
                throw YCardProductionPaymentError.invalidResponse
            }
            mapped.append(replacement)
        }
        return mapped
    }

    static func verifyProductionConstantFingerprints() -> Bool {
        fingerprint(YCardClientProtocolMaterial.bathroomUUID) == "542f6a70bb5b408c335d2db3821634fe105866c4ed1ea71490d1418be5e933ce"
            && YCardClientProtocolMaterial.bathroomUUID.utf8.count == 32
            && fingerprint(YCardClientProtocolMaterial.bathroomPermutation) == "4523a854d13c767baa1c2c3d3ce9dc7e21bc379e9c7b284fd2068900c42fd494"
            && YCardClientProtocolMaterial.bathroomPermutation.utf8.count == 10
    }

    static func clear(_ bytes: inout [UInt8]) {
        bytes.withUnsafeMutableBytes { buffer in
            buffer.initializeMemory(as: UInt8.self, repeating: 0)
        }
        bytes.removeAll(keepingCapacity: false)
    }

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

enum YCardProductionPaymentOperation: Equatable, Sendable {
    case cardBalance
    case cardCreate
    case cardBankSubmit
    case bathroomBalance(feeItemID: String)
    case bathroomCreate(feeItemID: String)
    case bathroomSubmit
    case electricityRoom
    case electricityCreate
    case electricityKeyboard
    case electricitySubmit
    case networkWarmUp
    case networkSelect
    case networkFeeItem
    case networkAccount
    case networkCreate
    case networkKeyboard
    case networkSubmit

    var method: String {
        switch self {
        case .cardBalance, .networkWarmUp, .networkFeeItem: "GET"
        default: "POST"
        }
    }

    var path: String {
        switch self {
        case .cardBalance:
            "/berserker-app/ykt/tsm/queryCard"
        case .cardCreate:
            "/charge/order/thirdOrder"
        case .bathroomBalance, .electricityRoom, .networkSelect, .networkAccount:
            "/charge/feeitem/getThirdData"
        case .networkWarmUp:
            "/charge/feeitem/toAppitem"
        case .networkFeeItem:
            "/charge/feeitem/singleFeeitem"
        case .cardBankSubmit,
             .bathroomCreate,
             .bathroomSubmit,
             .electricityCreate,
             .electricityKeyboard,
             .electricitySubmit,
             .networkCreate,
             .networkKeyboard,
             .networkSubmit:
            "/blade-pay/pay"
        }
    }

    var isDebit: Bool {
        switch self {
        case .cardCreate,
             .cardBankSubmit,
             .bathroomCreate,
             .bathroomSubmit,
             .electricityCreate,
             .electricityKeyboard,
             .electricitySubmit,
             .networkCreate,
             .networkKeyboard,
             .networkSubmit:
            true
        default:
            false
        }
    }

    var acceptsRedirectResponse: Bool {
        self == .cardCreate || self == .networkWarmUp
    }

    var usesChargeHeaders: Bool {
        switch self {
        case .networkWarmUp, .cardBalance, .cardCreate:
            false
        default:
            true
        }
    }
}

enum YCardProductionPaymentRequestPolicy {
    static let credentialPersistence: CMBRechargeCredentialPersistence = .memoryOnly

    static func authorize(
        _ request: URLRequest,
        operation: YCardProductionPaymentOperation
    ) throws {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "ycard.ahu.edu.cn",
              url.user == nil,
              url.password == nil,
              url.fragment == nil,
              url.port == nil || url.port == 443,
              request.httpMethod?.uppercased() == operation.method,
              url.path == operation.path else {
            throw YCardProductionPaymentError.disallowedEndpoint
        }

        let query = try values(
            URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        )
        let form = try formValues(request.httpBody)
        switch operation {
        case .cardBalance:
            try require(query, keys: ["scene", "synAccessSource"])
            guard query["scene"] == "cardRecharge",
                  query["synAccessSource"] == "h5",
                  form.isEmpty else { throw disallowed }
        case .networkWarmUp:
            try require(query, keys: [
                "feeitemid", "appId", "loginFrom", "synAccessSource", "synjones-auth"
            ])
            guard query["feeitemid"] == "431",
                  query["appId"] == YCardClientProtocolMaterial.networkEntryAppID,
                  query["loginFrom"] == "h5",
                  query["synAccessSource"] == "h5",
                  query["synjones-auth"]?.isEmpty == false,
                  form.isEmpty else { throw disallowed }
        case .networkFeeItem:
            try require(query, keys: ["feeitemid"])
            guard query["feeitemid"] == "431", form.isEmpty else { throw disallowed }
        default:
            guard query.isEmpty else { throw disallowed }
            try authorizeForm(form, operation: operation)
        }
    }

    private static var disallowed: YCardProductionPaymentError { .disallowedEndpoint }

    private static func authorizeForm(
        _ form: [String: String],
        operation: YCardProductionPaymentOperation
    ) throws {
        switch operation {
        case .cardCreate:
            try require(form, keys: [
                "feeitemid", "appid", "tranamt", "source", "yktcard",
                "synAccessSource", "APP_ID", "TIMESTAMP", "SIGN_TYPE", "NONCE", "SIGN"
            ])
            guard form["feeitemid"] == "401",
                  form["appid"] == YCardClientProtocolMaterial.appID,
                  form["source"] == "app",
                  form["synAccessSource"] == "h5",
                  YCardProductionPaymentSigner.verifiesCardCreate(form) else { throw disallowed }
            try requireSignedMetadata(form)
        case .cardBankSubmit:
            try require(form, keys: [
                "paytypeid", "paytype", "paystep", "orderid", "redirect_url",
                "userAgent", "APP_ID", "TIMESTAMP", "SIGN_TYPE", "NONCE", "SIGN",
                "synAccessSource"
            ])
            guard form["paytypeid"] == "63",
                  form["paytype"] == "BANKCARD",
                  form["paystep"] == "2",
                  form["userAgent"] == "h5",
                  form["synAccessSource"] == "h5",
                  form["redirect_url"] == YCardClientProtocolMaterial.cardRedirectURL,
                  YCardProductionPaymentSigner.verifiesCardBankSubmit(form) else { throw disallowed }
            try requireSignedMetadata(form)
        case let .bathroomBalance(feeItemID):
            try requireBathroomFeeItem(feeItemID)
            try require(form, keys: ["feeitemid", "type", "level", "telPhone"])
            guard form["feeitemid"] == feeItemID,
                  form["type"] == "IEC",
                  form["level"] == "1",
                  form["telPhone"].map(isElevenASCIIDigits) == true else { throw disallowed }
        case let .bathroomCreate(feeItemID):
            try requireBathroomFeeItem(feeItemID)
            try require(form, keys: [
                "feeitemid", "tranamt", "flag", "source", "paystep", "abstracts", "third_party"
            ])
            guard form["feeitemid"] == feeItemID,
                  form["flag"] == "choose",
                  form["source"] == "app",
                  form["paystep"] == "0",
                  form["abstracts"] == "",
                  form["third_party"].map(isJSONObject) == true else { throw disallowed }
        case .bathroomSubmit:
            try requireCampusAccountSubmit(form, signed: false)
        case .electricityRoom:
            try require(form, keys: [
                "feeitemid", "type", "level", "campus", "building", "floor", "room"
            ])
            guard form["feeitemid"] == "488",
                  form["type"] == "IEC",
                  form["level"] == "4" else { throw disallowed }
        case .electricityCreate, .networkCreate:
            try require(form, keys: [
                "feeitemid", "tranamt", "flag", "source", "paystep", "abstracts",
                "redirect_url", "third_party", "APP_ID", "TIMESTAMP", "SIGN_TYPE",
                "NONCE", "SIGN"
            ])
            let expectedFeeItem = operation == .electricityCreate ? "488" : "431"
            guard form["feeitemid"] == expectedFeeItem,
                  form["flag"] == "choose",
                  form["source"] == "app",
                  form["paystep"] == "0",
                  form["abstracts"] == "",
                  form["redirect_url"] == YCardClientProtocolMaterial.chargeRedirectURL,
                  form["third_party"].map(isJSONObject) == true,
                  YCardProductionPaymentSigner.verifiesGeneralSignedForm(form) else { throw disallowed }
            try requireSignedMetadata(form)
        case .electricityKeyboard, .networkKeyboard:
            try require(form, keys: [
                "paytypeid", "paytype", "paystep", "orderid",
                "APP_ID", "TIMESTAMP", "SIGN_TYPE", "NONCE", "SIGN"
            ])
            guard form["paytypeid"] == "64",
                  form["paytype"] == "ACCOUNTTSM",
                  form["paystep"] == "2",
                  YCardProductionPaymentSigner.verifiesGeneralSignedForm(form) else { throw disallowed }
            try requireSignedMetadata(form)
        case .electricitySubmit, .networkSubmit:
            try requireCampusAccountSubmit(form, signed: true)
        case .networkSelect:
            try require(form, keys: ["feeitemid", "type", "level"])
            guard form["feeitemid"] == "431",
                  form["type"] == "select",
                  form["level"] == "0" else { throw disallowed }
        case .networkAccount:
            try require(form, keys: ["feeitemid", "type", "level"])
            guard form["feeitemid"] == "431",
                  form["type"] == "IEC",
                  form["level"] == "0" else { throw disallowed }
        case .cardBalance, .networkWarmUp, .networkFeeItem:
            throw disallowed
        }
    }

    private static func requireCampusAccountSubmit(
        _ form: [String: String],
        signed: Bool
    ) throws {
        var keys: Set<String> = [
            "orderid", "paystep", "paytype", "paytypeid", "userAgent",
            "ccctype", "password", "uuid", "isWX"
        ]
        if signed {
            keys.formUnion(["APP_ID", "TIMESTAMP", "SIGN_TYPE", "NONCE", "SIGN"])
        }
        try require(form, keys: keys)
        guard form["paystep"] == "2",
              form["paytype"] == "ACCOUNTTSM",
              form["paytypeid"] == "64",
              form["userAgent"] == "h5",
              form["ccctype"] == "000",
              form["isWX"] == "0",
              form["password"].map(isSixASCIIDigits) == true,
              form["uuid"].map(isUUID) == true else { throw disallowed }
        if signed {
            try requireSignedMetadata(form)
            guard YCardProductionPaymentSigner.verifiesGeneralSignedForm(form) else {
                throw disallowed
            }
        }
    }

    private static func requireSignedMetadata(_ form: [String: String]) throws {
        guard form["APP_ID"] == YCardClientProtocolMaterial.appID,
              form["SIGN_TYPE"] == YCardClientProtocolMaterial.signType,
              form["TIMESTAMP"].map(isTimestamp) == true,
              form["NONCE"].map(isNonce) == true,
              form["SIGN"].map(isUppercaseSHA256) == true else { throw disallowed }
    }

    private static func requireBathroomFeeItem(_ value: String) throws {
        guard value == "409" || value == "430" else { throw disallowed }
    }

    private static func require(
        _ values: [String: String],
        keys: Set<String>
    ) throws {
        guard Set(values.keys) == keys else { throw disallowed }
    }

    private static func values(_ items: [URLQueryItem]) throws -> [String: String] {
        guard Set(items.map(\.name)).count == items.count else { throw disallowed }
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
    }

    private static func formValues(_ data: Data?) throws -> [String: String] {
        guard let data else { return [:] }
        do {
            return try YCardServerFormDecoder.values(data)
        } catch {
            throw disallowed
        }
    }

    private static func isJSONObject(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return object is [String: Any]
    }

    private static func isElevenASCIIDigits(_ value: String) -> Bool {
        value.utf8.count == 11 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isSixASCIIDigits(_ value: String) -> Bool {
        value.utf8.count == 6 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isUUID(_ value: String) -> Bool {
        value.utf8.count == 32 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0)
        }
    }

    private static func isTimestamp(_ value: String) -> Bool {
        value.utf8.count == 14 && value.utf8.allSatisfy { (48...57).contains($0) }
    }

    private static func isNonce(_ value: String) -> Bool {
        value.utf8.count == 11 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...122).contains($0)
        }
    }

    private static func isUppercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...70).contains($0)
        }
    }
}

private enum YCardPaymentFormEncoder {
    static func data(_ fields: [YCardPaymentFormField]) throws -> Data {
        guard Set(fields.map(\.name)).count == fields.count else {
            throw YCardProductionPaymentError.invalidRequest
        }
        return YCardFormURLEncoder.data(
            fields.map { (name: $0.name, value: $0.value) }
        )
    }
}

private final class YCardProductionNoRedirectDelegate:
    NSObject,
    URLSessionTaskDelegate,
    @unchecked Sendable
{
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

struct YCardProductionHTTPResult: Sendable {
    let data: Data
    let statusCode: Int
    let responseURL: URL
    let location: URL?
}

actor YCardProductionPaymentClient {
    private static let origin = URL(string: "https://ycard.ahu.edu.cn")!

    private let campusAPI: any CampusCoreAPI
    private let session: URLSession
    private let mockTransportEnabled: Bool
    private let automatedEnvironment: Bool
    private var accessToken: String?
    private var sessionCookies: [CampusCookie] = []

    init(campusAPI: any CampusCoreAPI) {
        self.campusAPI = campusAPI
        session = URLSession(
            configuration: Self.makeConfiguration(),
            delegate: YCardProductionNoRedirectDelegate(),
            delegateQueue: nil
        )
        mockTransportEnabled = false
        automatedEnvironment = Self.isAutomatedEnvironment()
    }

    init(
        campusAPI: any CampusCoreAPI,
        configuration: URLSessionConfiguration,
        mockTransportEnabled: Bool
    ) {
        self.campusAPI = campusAPI
        let configuration = Self.harden(configuration)
        session = URLSession(
            configuration: configuration,
            delegate: YCardProductionNoRedirectDelegate(),
            delegateQueue: nil
        )
        self.mockTransportEnabled = mockTransportEnabled
        automatedEnvironment = Self.isAutomatedEnvironment()
    }

    deinit {
        session.invalidateAndCancel()
    }

    static func makeConfiguration(
        protocolClasses: [AnyClass]? = nil
    ) -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = protocolClasses
        return harden(configuration)
    }

    func execute(
        _ operation: YCardProductionPaymentOperation,
        queryItems: [URLQueryItem] = [],
        formFields: [YCardPaymentFormField] = []
    ) async throws -> YCardProductionHTTPResult {
        if operation.isDebit {
            try authorizeDebitTransport()
        }
        try await prepareCredentialsIfNeeded()
        let resolvedQuery: [URLQueryItem]
        if operation == .networkWarmUp {
            guard let accessToken else { throw YCardProductionPaymentError.credentialsUnavailable }
            resolvedQuery = [
                URLQueryItem(name: "feeitemid", value: "431"),
                URLQueryItem(name: "appId", value: YCardClientProtocolMaterial.networkEntryAppID),
                URLQueryItem(name: "loginFrom", value: "h5"),
                URLQueryItem(name: "synAccessSource", value: "h5"),
                URLQueryItem(name: "synjones-auth", value: accessToken)
            ]
        } else {
            resolvedQuery = queryItems
        }
        var request = try Self.makeRequest(
            operation,
            queryItems: resolvedQuery,
            formFields: formFields,
            accessToken: accessToken,
            cookies: sessionCookies
        )
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch is CancellationError {
            Self.clearBody(&request)
            throw CancellationError()
        } catch let error as URLError where error.code == .timedOut {
            Self.clearBody(&request)
            throw operation.isDebit
                ? YCardProductionPaymentError.unknownResult
                : YCardProductionPaymentError.timedOut
        } catch {
            Self.clearBody(&request)
            throw operation.isDebit
                ? YCardProductionPaymentError.unknownResult
                : YCardProductionPaymentError.invalidResponse
        }
        Self.clearBody(&request)
        let (data, rawResponse) = result
        guard let response = rawResponse as? HTTPURLResponse,
              let responseURL = response.url,
              responseURL == request.url else {
            throw YCardProductionPaymentError.invalidResponse
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            clearCredentials()
            throw YCardProductionPaymentError.credentialsUnavailable
        }
        captureResponseCookies(response, requestURL: responseURL)
        let accepted = (200..<300).contains(response.statusCode)
            || (operation.acceptsRedirectResponse && (300..<400).contains(response.statusCode))
        guard accepted else {
            // Apart from the authentication rejection handled above, an HTTP
            // failure returned by a mutation endpoint does not prove that the
            // server skipped the operation. In particular, 408 can be emitted
            // after the request reached the payment service. Fail closed and
            // require reconciliation instead of allowing an automatic retry.
            if operation.isDebit {
                throw YCardProductionPaymentError.unknownResult
            }
            throw YCardProductionPaymentError.rejected
        }
        return YCardProductionHTTPResult(
            data: data,
            statusCode: response.statusCode,
            responseURL: responseURL,
            location: Self.validatedLocation(response, relativeTo: responseURL)
        )
    }

    func clearCredentials() {
        accessToken = nil
        sessionCookies.removeAll(keepingCapacity: false)
    }

    static func makeRequest(
        _ operation: YCardProductionPaymentOperation,
        queryItems: [URLQueryItem] = [],
        formFields: [YCardPaymentFormField] = [],
        accessToken: String?,
        cookies: [CampusCookie]
    ) throws -> URLRequest {
        var components = URLComponents(
            string: "\(origin.absoluteString)\(operation.path)"
        )
        if !queryItems.isEmpty { components?.queryItems = queryItems }
        guard let url = components?.url else {
            throw YCardProductionPaymentError.invalidRequest
        }
        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = operation.method
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        if operation == .networkWarmUp {
            request.setValue(
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
                forHTTPHeaderField: "Accept"
            )
            request.setValue(
                "https://ycard.ahu.edu.cn/plat/dating?index=1",
                forHTTPHeaderField: "Referer"
            )
        } else {
            request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
            if operation.usesChargeHeaders {
                request.setValue(
                    "https://ycard.ahu.edu.cn/charge-app/",
                    forHTTPHeaderField: "Referer"
                )
                request.setValue(origin.absoluteString, forHTTPHeaderField: "Origin")
            }
        }
        if let accessToken,
           let authorization = NetworkRechargeSessionCredentials.authorizationHeader(
               accessToken: accessToken
           ) {
            request.setValue(authorization, forHTTPHeaderField: "Synjones-Auth")
        }
        if let cookieHeader = NetworkRechargeSessionCredentials.cookieHeader(
            cookies: cookies,
            for: url
        ) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if operation.method == "POST" {
            request.httpBody = try YCardPaymentFormEncoder.data(formFields)
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
        } else if !formFields.isEmpty {
            throw YCardProductionPaymentError.invalidRequest
        }
        try YCardProductionPaymentRequestPolicy.authorize(request, operation: operation)
        return request
    }

    private static func harden(
        _ configuration: URLSessionConfiguration
    ) -> URLSessionConfiguration {
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.httpCookieAcceptPolicy = .never
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        return configuration
    }

    private static func clearBody(_ request: inout URLRequest) {
        if var body = request.httpBody {
            body.resetBytes(in: body.startIndex..<body.endIndex)
        }
        request.httpBody = nil
    }

    private func authorizeDebitTransport() throws {
        if mockTransportEnabled {
            let hasMockProtocol = session.configuration.protocolClasses?.contains(where: {
                $0 is URLProtocol.Type
            }) == true
            guard hasMockProtocol else {
                throw YCardProductionPaymentError.automatedDebitDisabled
            }
            return
        }
        guard !automatedEnvironment else {
            throw YCardProductionPaymentError.automatedDebitDisabled
        }
    }

    private static func isAutomatedEnvironment(
        processInfo: ProcessInfo = .processInfo
    ) -> Bool {
        liveDebitIsDisabled(
            environment: processInfo.environment,
            arguments: processInfo.arguments
        )
    }

    static func liveDebitIsDisabled(
        environment: [String: String],
        arguments: [String]
    ) -> Bool {
        func isEnabled(_ value: String?) -> Bool {
            guard let value else { return false }
            return ["1", "true", "yes", "on"].contains(value.lowercased())
        }
        return isEnabled(environment["AHUTONG_CI_DISABLE_LIVE_PAYMENT"])
            || isEnabled(environment["CI"])
            || isEnabled(environment["GITHUB_ACTIONS"])
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || arguments.contains("--ui-testing")
    }

    private func prepareCredentialsIfNeeded() async throws {
        guard accessToken == nil else { return }
        let token: String
        do {
            token = try await campusAPI.cardAccessToken()
        } catch {
            throw YCardProductionPaymentError.credentialsUnavailable
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw YCardProductionPaymentError.credentialsUnavailable
        }
        accessToken = token
        let rawCookies = (try? await campusAPI.cookiesFlat()) ?? "[]"
        let decoded = (try? JSONDecoder().decode(
            [CampusCookie].self,
            from: Data(rawCookies.utf8)
        )) ?? []
        sessionCookies = decoded.filter(CampusCookieWebBridge.isTrustedSchoolCookie)
    }

    private func captureResponseCookies(
        _ response: HTTPURLResponse,
        requestURL: URL
    ) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) {
            result,
            item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let received = HTTPCookie.cookies(
            withResponseHeaderFields: fields,
            for: response.url ?? requestURL
        )
        CampusCookieResponsePolicy.merge(
            received,
            into: &sessionCookies,
            identityIsAllowed: CampusCookieWebBridge.isTrustedSchoolCookie,
            storedCookieIsAllowed: CampusCookieWebBridge.isTrustedSchoolCookie
        )
    }

    private static func validatedLocation(
        _ response: HTTPURLResponse,
        relativeTo responseURL: URL
    ) -> URL? {
        guard let raw = response.value(forHTTPHeaderField: "Location"),
              let location = URL(string: raw, relativeTo: responseURL)?.absoluteURL,
              location.scheme?.lowercased() == "https",
              location.host?.lowercased() == "ycard.ahu.edu.cn",
              location.user == nil,
              location.password == nil,
              location.port == nil || location.port == 443 else {
            return nil
        }
        return location
    }
}

enum YCardProductionPaymentDecoder {
    static func orderID(from result: YCardProductionHTTPResult) throws -> String {
        let explicitRejection = isExplicitOrderCreationRejection(result.data)
        var discoveredOrderID: String?
        if let object = try? JSONSerialization.jsonObject(with: result.data),
           let orderID = findOrderID(in: object),
           isValidOrderID(orderID) {
            discoveredOrderID = orderID
        }
        for url in [result.location, result.responseURL] where discoveredOrderID == nil {
            guard let url,
                  let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                  let orderID = components.queryItems?.first(where: {
                      $0.name == "orderid"
                  })?.value,
                  isValidOrderID(orderID) else { continue }
            discoveredOrderID = orderID
        }
        if let discoveredOrderID {
            guard !explicitRejection else {
                throw YCardProductionPaymentError.invalidResponse
            }
            return discoveredOrderID
        }
        if explicitRejection {
            throw YCardProductionPaymentError.rejected
        }
        throw YCardProductionPaymentError.invalidResponse
    }

    static func passwordMap(from data: Data) throws -> [String: String] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(root["code"]) == 200,
              let payload = root["data"] as? [String: Any],
              let map = payload["passwordMap"] as? [String: String],
              map.count == 1 else {
            throw businessFailure(from: data)
        }
        return map
    }

    static func finalStatus(
        from data: Data,
        feature: PaymentFeature
    ) -> PaymentOrderStatus {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = integer(root["code"]) else {
            return .unknown("支付结果无法解析，请稍后核验")
        }
        let success = root["success"] as? Bool
        let confirmed: Bool
        switch feature {
        case .cardRecharge, .bathroom:
            confirmed = code == 200 && success != false
        case .electricity:
            confirmed = code == 200 && success == true
        case .networkRecharge:
            confirmed = code == 200
                && success == true
                && (root["data"] as? String)?.isEmpty == false
        }
        if confirmed {
            return .confirmed("学校支付服务已确认成功")
        }
        return .rejected("学校支付服务拒绝了本次支付")
    }

    static func requireReadSuccess(_ data: Data) throws {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = integer(root["code"]),
              code == 0 || code == 200 else {
            throw YCardProductionPaymentError.invalidResponse
        }
    }

    private static func businessFailure(from data: Data) -> YCardProductionPaymentError {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              integer(root["code"]) != nil else { return .invalidResponse }
        return .rejected
    }

    private static func findOrderID(in object: Any) -> String? {
        guard let dictionary = object as? [String: Any] else { return nil }
        if let value = dictionary["orderid"] as? String { return value }
        if let data = dictionary["data"] as? [String: Any],
           let value = data["orderid"] as? String { return value }
        return nil
    }

    private static func isExplicitOrderCreationRejection(_ data: Data) -> Bool {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return false
        }
        if let success = root["success"] as? Bool, success == false {
            return true
        }
        if let code = integer(root["code"]), code != 200 {
            return true
        }
        return false
    }

    private static func integer(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func isValidOrderID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 256 && value.unicodeScalars.allSatisfy {
            $0.value >= 0x21 && $0.value <= 0x7e
        }
    }
}

actor YCardProductionPaymentGateway: PaymentGateway {
    private struct OrderRecord: Sendable {
        let feature: PaymentFeature
        let method: PaymentMethod
        let context: PaymentTransactionContext
        var terminalStatus: PaymentOrderStatus?
    }

    private final class Prepared:
        PreparedPaymentConfirmation,
        @unchecked Sendable
    {
        struct Payload: Sendable {
            let orderID: String
            let feature: PaymentFeature
            let operation: YCardProductionPaymentOperation
            let uuid: String?
            var mappedPassword: [UInt8]?
        }

        private let lock = NSLock()
        private let orderID: String
        private let feature: PaymentFeature
        private let operation: YCardProductionPaymentOperation
        private let uuid: String?
        private var mappedPassword: [UInt8]?
        private var consumed = false

        init(
            orderID: String,
            feature: PaymentFeature,
            operation: YCardProductionPaymentOperation,
            uuid: String? = nil,
            mappedPassword: [UInt8]? = nil
        ) {
            self.orderID = orderID
            self.feature = feature
            self.operation = operation
            self.uuid = uuid
            self.mappedPassword = mappedPassword
        }

        deinit {
            clear()
        }

        func take() throws -> Payload {
            try lock.withLock {
                guard !consumed else {
                    throw PaymentGatewayError.invalidResponse
                }
                consumed = true
                let bytes = mappedPassword
                mappedPassword = nil
                return Payload(
                    orderID: orderID,
                    feature: feature,
                    operation: operation,
                    uuid: uuid,
                    mappedPassword: bytes
                )
            }
        }

        func clear() {
            lock.withLock {
                consumed = true
                if mappedPassword != nil {
                    for index in mappedPassword!.indices {
                        mappedPassword![index] = 0
                    }
                }
                mappedPassword = nil
            }
        }
    }

    private let client: YCardProductionPaymentClient
    private let signer: YCardProductionPaymentSigner
    private var orders: [String: OrderRecord] = [:]
    private var orderByIdempotencyKey: [String: String] = [:]
    private var creatingKeys: Set<String> = []
    private var uncertainCreationKeys: Set<String> = []
    private var networkSessionPrepared = false

    init(campusAPI: any CampusCoreAPI) {
        client = YCardProductionPaymentClient(campusAPI: campusAPI)
        signer = YCardProductionPaymentSigner()
    }

    init(
        campusAPI: any CampusCoreAPI,
        configuration: URLSessionConfiguration,
        mockTransportEnabled: Bool,
        signer: YCardProductionPaymentSigner = YCardProductionPaymentSigner()
    ) {
        client = YCardProductionPaymentClient(
            campusAPI: campusAPI,
            configuration: configuration,
            mockTransportEnabled: mockTransportEnabled
        )
        self.signer = signer
    }

    func createOrder(
        request: PaymentRequest,
        idempotencyKey: String
    ) async throws -> PaymentOrder {
        guard !idempotencyKey.isEmpty, idempotencyKey.utf8.count <= 256 else {
            throw PaymentGatewayError.featureMismatch
        }
        if let existing = orderByIdempotencyKey[idempotencyKey],
           orders[existing] != nil {
            return PaymentOrder(id: existing, externalURL: nil)
        }
        guard !uncertainCreationKeys.contains(idempotencyKey) else {
            throw PaymentGatewayError.timedOut
        }
        guard creatingKeys.insert(idempotencyKey).inserted else {
            throw PaymentGatewayError.timedOut
        }
        defer { creatingKeys.remove(idempotencyKey) }

        if request.feature == .cardRecharge, request.method == .alipay {
            guard case .card = request.context else {
                throw PaymentGatewayError.featureMismatch
            }
            let orderID = Self.localHandoffID(idempotencyKey)
            orders[orderID] = OrderRecord(
                feature: .cardRecharge,
                method: .alipay,
                context: request.context,
                terminalStatus: nil
            )
            orderByIdempotencyKey[idempotencyKey] = orderID
            return PaymentOrder(
                id: orderID,
                externalURL: AlipayCampusCardHandoff.appURL
            )
        }

        let result: YCardProductionHTTPResult
        do {
            switch (request.feature, request.method, request.context) {
            case let (.cardRecharge, .bankCard, .card(cardType)):
                result = try await client.execute(
                    .cardCreate,
                    formFields: try signer.cardCreate(
                        amount: request.amount.text,
                        cardType: cardType
                    ).fields
                )
            case let (
                .bathroom,
                .campusAccount,
                .bathroom(feeItemID, thirdPartyJSON)
            ):
                let fields = try Self.bathroomCreateFields(
                    feeItemID: feeItemID,
                    amount: request.amount.text,
                    thirdPartyJSON: thirdPartyJSON
                )
                result = try await client.execute(
                    .bathroomCreate(feeItemID: feeItemID),
                    formFields: fields
                )
            case let (
                .electricity,
                .campusAccount,
                .electricity(thirdPartyJSON)
            ):
                result = try await client.execute(
                    .electricityCreate,
                    formFields: try signer.chargeCreate(
                        feeItemID: "488",
                        amount: request.amount.text,
                        thirdPartyJSON: thirdPartyJSON
                    ).fields
                )
            case let (
                .networkRecharge,
                .campusAccount,
                .networkRecharge(thirdPartyJSON)
            ):
                do {
                    try await ensureNetworkSessionPrepared()
                } catch {
                    throw Self.networkPreflightFailure(error)
                }
                result = try await client.execute(
                    .networkCreate,
                    formFields: try signer.chargeCreate(
                        feeItemID: "431",
                        amount: request.amount.text,
                        thirdPartyJSON: thirdPartyJSON
                    ).fields
                )
            default:
                throw PaymentGatewayError.featureMismatch
            }
        } catch {
            if request.feature == .networkRecharge,
               Self.invalidatesNetworkSession(error) {
                networkSessionPrepared = false
            }
            let mapped = Self.gatewayError(error, definiteRejection: true)
            if !Self.isDefiniteCreateFailure(mapped) {
                uncertainCreationKeys.insert(idempotencyKey)
            }
            throw mapped
        }

        let orderID: String
        do {
            orderID = try YCardProductionPaymentDecoder.orderID(from: result)
        } catch let error as YCardProductionPaymentError where error == .rejected {
            throw PaymentGatewayError.definitelyRejected(
                "学校支付服务明确拒绝创建本次订单"
            )
        } catch {
            uncertainCreationKeys.insert(idempotencyKey)
            throw PaymentGatewayError.invalidResponse
        }
        orders[orderID] = OrderRecord(
            feature: request.feature,
            method: request.method,
            context: request.context,
            terminalStatus: nil
        )
        orderByIdempotencyKey[idempotencyKey] = orderID
        return PaymentOrder(id: orderID, externalURL: nil)
    }

    func prepareConfirmation(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod,
        authorization: TransientPaymentAuthorization?
    ) async throws -> any PreparedPaymentConfirmation {
        if orders[orderID] == nil,
           Self.isRecoverablePair(feature: feature, method: method) {
            // PendingPayment intentionally persists no account, amount, JSON,
            // map, UUID, or authorization. Every native final endpoint only
            // needs the persisted order id plus feature/method, so a fresh
            // gateway can safely resume the exact order without creating one.
            orders[orderID] = OrderRecord(
                feature: feature,
                method: method,
                context: .demo,
                terminalStatus: nil
            )
        }
        guard let record = orders[orderID],
              record.feature == feature,
              record.method == method else {
            authorization?.clear()
            throw PaymentGatewayError.invalidResponse
        }
        if feature == .cardRecharge && method == .bankCard {
            authorization?.clear()
            return Prepared(
                orderID: orderID,
                feature: feature,
                operation: .cardBankSubmit
            )
        }
        guard method == .campusAccount,
              let authorization else {
            authorization?.clear()
            throw PaymentValidationError.invalidPassword
        }

        let preparation: (uuid: String, mapped: [UInt8])
        do {
            switch feature {
            case .bathroom:
                var consumed = try authorization.consumeASCIIBytes()
                defer {
                    for index in consumed.indices { consumed[index] = 0 }
                }
                var bytes = Array(consumed)
                preparation = try YCardSecureKeyboardMapper.bathroomPreparation(
                    authorization: &bytes
                )
            case .electricity, .networkRecharge:
                if feature == .networkRecharge {
                    try await ensureNetworkSessionPrepared()
                }
                let operation: YCardProductionPaymentOperation = feature == .electricity
                    ? .electricityKeyboard
                    : .networkKeyboard
                let response = try await client.execute(
                    operation,
                    formFields: try signer.dynamicKeyboardRequest(orderID: orderID).fields
                )
                let map = try YCardProductionPaymentDecoder.passwordMap(from: response.data)
                var consumed = try authorization.consumeASCIIBytes()
                defer {
                    for index in consumed.indices { consumed[index] = 0 }
                }
                var bytes = Array(consumed)
                preparation = try YCardSecureKeyboardMapper.dynamicPreparation(
                    authorization: &bytes,
                    passwordMap: map
                )
            case .cardRecharge:
                authorization.clear()
                throw PaymentGatewayError.featureMismatch
            }
        } catch {
            authorization.clear()
            if feature == .networkRecharge,
               Self.invalidatesNetworkSession(error) {
                networkSessionPrepared = false
            }
            throw Self.gatewayError(error, definiteRejection: false)
        }

        let operation: YCardProductionPaymentOperation
        switch feature {
        case .bathroom: operation = .bathroomSubmit
        case .electricity: operation = .electricitySubmit
        case .networkRecharge: operation = .networkSubmit
        case .cardRecharge:
            var mapped = preparation.mapped
            YCardSecureKeyboardMapper.clear(&mapped)
            throw PaymentGatewayError.featureMismatch
        }
        return Prepared(
            orderID: orderID,
            feature: feature,
            operation: operation,
            uuid: preparation.uuid,
            mappedPassword: preparation.mapped
        )
    }

    func submitPreparedConfirmation(
        _ preparedConfirmation: any PreparedPaymentConfirmation
    ) async throws -> PaymentOrderStatus {
        guard let prepared = preparedConfirmation as? Prepared else {
            preparedConfirmation.clear()
            throw PaymentGatewayError.invalidResponse
        }
        defer { prepared.clear() }
        var payload = try prepared.take()
        defer {
            if var bytes = payload.mappedPassword {
                payload.mappedPassword = nil
                YCardSecureKeyboardMapper.clear(&bytes)
            }
        }
        guard var record = orders[payload.orderID],
              record.feature == payload.feature else {
            throw PaymentGatewayError.invalidResponse
        }

        let fields: [YCardPaymentFormField]
        do {
            switch payload.operation {
            case .cardBankSubmit:
                fields = try signer.cardBankSubmit(orderID: payload.orderID).fields
            case .bathroomSubmit:
                guard let uuid = payload.uuid,
                      let mapped = payload.mappedPassword else {
                    throw YCardProductionPaymentError.invalidRequest
                }
                fields = try Self.campusAccountSubmitFields(
                    orderID: payload.orderID,
                    uuid: uuid,
                    mappedPassword: mapped
                )
            case .electricitySubmit, .networkSubmit:
                guard let uuid = payload.uuid,
                      let mapped = payload.mappedPassword else {
                    throw YCardProductionPaymentError.invalidRequest
                }
                let mappedString = String(decoding: mapped, as: UTF8.self)
                fields = try signer.signedCampusAccountSubmit(
                    orderID: payload.orderID,
                    uuid: uuid,
                    mappedPassword: mappedString
                ).fields
            default:
                throw YCardProductionPaymentError.invalidRequest
            }
            let response = try await client.execute(
                payload.operation,
                formFields: fields
            )
            let status = YCardProductionPaymentDecoder.finalStatus(
                from: response.data,
                feature: record.feature
            )
            switch status {
            case .confirmed:
                try? await refreshBalance(for: record)
            case .rejected, .pending, .unknown:
                break
            }
            record.terminalStatus = status
            orders[payload.orderID] = record
            return status
        } catch let error as YCardProductionPaymentError where error == .rejected {
            let status = PaymentOrderStatus.rejected("学校支付服务拒绝了本次支付")
            record.terminalStatus = status
            orders[payload.orderID] = record
            return status
        } catch {
            if record.feature == .networkRecharge,
               Self.invalidatesNetworkSession(error) {
                networkSessionPrepared = false
            }
            record.terminalStatus = .unknown("订单结果待核验，请勿重复提交")
            orders[payload.orderID] = record
            throw Self.gatewayError(error, definiteRejection: false)
        }
    }

    func status(
        orderID: String,
        feature: PaymentFeature,
        method: PaymentMethod
    ) async throws -> PaymentOrderStatus {
        guard let record = orders[orderID] else {
            return .unknown("本机已恢复待处理订单，但学校未提供可安全重放的订单查询接口")
        }
        guard record.feature == feature, record.method == method else {
            throw PaymentGatewayError.featureMismatch
        }
        if let terminalStatus = record.terminalStatus {
            switch terminalStatus {
            case .confirmed, .rejected:
                return terminalStatus
            case .pending, .unknown:
                try? await refreshBalance(for: record)
                return terminalStatus
            }
        }
        if method == .alipay {
            return .unknown("请在支付宝中核验充值结果")
        }
        try? await refreshBalance(for: record)
        return .unknown("余额已重新查询，订单仍需人工核验，请勿重复提交")
    }

    private func ensureNetworkSessionPrepared() async throws {
        guard !networkSessionPrepared else { return }
        _ = try await client.execute(.networkWarmUp)
        let select = try await client.execute(
            .networkSelect,
            formFields: [
                YCardPaymentFormField("feeitemid", "431"),
                YCardPaymentFormField("type", "select"),
                YCardPaymentFormField("level", "0")
            ]
        )
        try YCardProductionPaymentDecoder.requireReadSuccess(select.data)
        let feeItem = try await client.execute(
            .networkFeeItem,
            queryItems: [URLQueryItem(name: "feeitemid", value: "431")]
        )
        try YCardProductionPaymentDecoder.requireReadSuccess(feeItem.data)
        let account = try await client.execute(
            .networkAccount,
            formFields: Self.networkAccountFields()
        )
        try YCardProductionPaymentDecoder.requireReadSuccess(account.data)
        networkSessionPrepared = true
    }

    private func refreshBalance(for record: OrderRecord) async throws {
        let result: YCardProductionHTTPResult
        switch record.context {
        case .card:
            result = try await client.execute(
                .cardBalance,
                queryItems: [
                    URLQueryItem(name: "scene", value: "cardRecharge"),
                    URLQueryItem(name: "synAccessSource", value: "h5")
                ]
            )
        case let .bathroom(feeItemID, thirdPartyJSON):
            guard let phone = Self.stringValue("telPhone", in: thirdPartyJSON),
                  phone.utf8.count == 11,
                  phone.utf8.allSatisfy({ (48...57).contains($0) }) else {
                throw YCardProductionPaymentError.invalidRequest
            }
            result = try await client.execute(
                .bathroomBalance(feeItemID: feeItemID),
                formFields: [
                    YCardPaymentFormField("feeitemid", feeItemID),
                    YCardPaymentFormField("type", "IEC"),
                    YCardPaymentFormField("level", "1"),
                    YCardPaymentFormField("telPhone", phone)
                ]
            )
        case let .electricity(thirdPartyJSON):
            guard let campus = Self.stringValue("area", in: thirdPartyJSON),
                  let building = Self.stringValue("building", in: thirdPartyJSON),
                  let floor = Self.stringValue("floor", in: thirdPartyJSON),
                  let room = Self.stringValue("room", in: thirdPartyJSON) else {
                throw YCardProductionPaymentError.invalidRequest
            }
            result = try await client.execute(
                .electricityRoom,
                formFields: [
                    YCardPaymentFormField("feeitemid", "488"),
                    YCardPaymentFormField("type", "IEC"),
                    YCardPaymentFormField("level", "4"),
                    YCardPaymentFormField("campus", campus),
                    YCardPaymentFormField("building", building),
                    YCardPaymentFormField("floor", floor),
                    YCardPaymentFormField("room", room)
                ]
            )
        case .networkRecharge:
            do {
                result = try await client.execute(
                    .networkAccount,
                    formFields: Self.networkAccountFields()
                )
            } catch {
                if Self.invalidatesNetworkSession(error) {
                    networkSessionPrepared = false
                }
                throw error
            }
        case .demo:
            throw YCardProductionPaymentError.invalidRequest
        }
        try YCardProductionPaymentDecoder.requireReadSuccess(result.data)
    }

    private static func bathroomCreateFields(
        feeItemID: String,
        amount: String,
        thirdPartyJSON: String
    ) throws -> [YCardPaymentFormField] {
        guard feeItemID == "409" || feeItemID == "430",
              isJSONObject(thirdPartyJSON) else {
            throw YCardProductionPaymentError.invalidRequest
        }
        return [
            YCardPaymentFormField("feeitemid", feeItemID),
            YCardPaymentFormField("tranamt", amount),
            YCardPaymentFormField("flag", "choose"),
            YCardPaymentFormField("source", "app"),
            YCardPaymentFormField("paystep", "0"),
            YCardPaymentFormField("abstracts", ""),
            YCardPaymentFormField("third_party", thirdPartyJSON)
        ]
    }

    private static func campusAccountSubmitFields(
        orderID: String,
        uuid: String,
        mappedPassword: [UInt8]
    ) throws -> [YCardPaymentFormField] {
        guard mappedPassword.count == 6,
              mappedPassword.allSatisfy({ (48...57).contains($0) }) else {
            throw YCardProductionPaymentError.invalidRequest
        }
        return [
            YCardPaymentFormField("orderid", orderID),
            YCardPaymentFormField("paystep", "2"),
            YCardPaymentFormField("paytype", "ACCOUNTTSM"),
            YCardPaymentFormField("paytypeid", "64"),
            YCardPaymentFormField("userAgent", "h5"),
            YCardPaymentFormField("ccctype", "000"),
            YCardPaymentFormField("password", String(decoding: mappedPassword, as: UTF8.self)),
            YCardPaymentFormField("uuid", uuid),
            YCardPaymentFormField("isWX", "0")
        ]
    }

    private static func networkAccountFields() -> [YCardPaymentFormField] {
        [
            YCardPaymentFormField("feeitemid", "431"),
            YCardPaymentFormField("type", "IEC"),
            YCardPaymentFormField("level", "0")
        ]
    }

    private static func stringValue(_ key: String, in json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let value = object[key] as? String,
              !value.isEmpty else { return nil }
        return value
    }

    private static func isJSONObject(_ value: String) -> Bool {
        guard let data = value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return false }
        return object is [String: Any]
    }

    private static func localHandoffID(_ idempotencyKey: String) -> String {
        let digest = SHA256.hash(data: Data(idempotencyKey.utf8))
            .prefix(12)
            .map { String(format: "%02x", $0) }
            .joined()
        return "ALIPAY-HANDOFF-\(digest)"
    }

    private static func isRecoverablePair(
        feature: PaymentFeature,
        method: PaymentMethod
    ) -> Bool {
        switch (feature, method) {
        case (.cardRecharge, .bankCard),
             (.bathroom, .campusAccount),
             (.electricity, .campusAccount),
             (.networkRecharge, .campusAccount):
            true
        default:
            false
        }
    }

    private static func gatewayError(
        _ error: Error,
        definiteRejection: Bool
    ) -> Error {
        if let error = error as? PaymentGatewayError { return error }
        guard let error = error as? YCardProductionPaymentError else {
            return definiteRejection
                ? PaymentGatewayError.invalidResponse
                : PaymentGatewayError.timedOut
        }
        switch error {
        case .automatedDebitDisabled:
            return PaymentGatewayError.automatedDebitDisabled
        case .credentialsUnavailable:
            return PaymentGatewayError.definitelyRejected("校园卡登录状态已失效，请重新登录后重试")
        case .disallowedEndpoint, .invalidRequest:
            return PaymentGatewayError.featureMismatch
        case .rejected:
            return PaymentGatewayError.definitelyRejected("学校支付服务拒绝了本次请求")
        case .timedOut, .unknownResult:
            return PaymentGatewayError.timedOut
        case .invalidResponse:
            return PaymentGatewayError.invalidResponse
        }
    }

    private static func networkPreflightFailure(_ error: Error) -> Error {
        if let gatewayError = error as? PaymentGatewayError {
            return gatewayError
        }
        if let error = error as? YCardProductionPaymentError {
            switch error {
            case .disallowedEndpoint, .invalidRequest:
                return PaymentGatewayError.featureMismatch
            case .credentialsUnavailable:
                return PaymentGatewayError.definitelyRejected(
                    "校园卡登录状态已失效，网费订单尚未创建"
                )
            case .automatedDebitDisabled,
                 .invalidResponse,
                 .rejected,
                 .timedOut,
                 .unknownResult:
                break
            }
        }
        return PaymentGatewayError.definitelyRejected(
            "网费充值预检失败，订单尚未创建，请重试"
        )
    }

    private static func invalidatesNetworkSession(_ error: Error) -> Bool {
        (error as? YCardProductionPaymentError) == .credentialsUnavailable
    }

    private static func isDefiniteCreateFailure(_ error: Error) -> Bool {
        guard let error = error as? PaymentGatewayError else { return false }
        switch error {
        case .automatedDebitDisabled, .featureMismatch, .definitelyRejected:
            return true
        case .timedOut, .invalidResponse, .server:
            return false
        }
    }
}

private extension Character {
    var isASCIIDigit: Bool {
        unicodeScalars.count == 1
            && unicodeScalars.first.map { (48...57).contains($0.value) } == true
    }
}
