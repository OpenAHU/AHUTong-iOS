import Combine
import Foundation

enum YCardReadOnlyError: LocalizedError, Equatable {
    case disallowedEndpoint
    case credentialsUnavailable
    case invalidResponse
    case server
    case unavailable

    var errorDescription: String? {
        switch self {
        case .disallowedEndpoint:
            "已阻止不在只读白名单中的校园卡请求"
        case .credentialsUnavailable:
            "校园卡登录状态已失效，请重新登录后重试"
        case .invalidResponse:
            "学校校园卡服务返回了无法识别的数据"
        case .server:
            "学校校园卡服务暂时无法完成查询，请稍后重试"
        case .unavailable:
            "学校校园卡服务暂不可用，请稍后重试"
        }
    }
}

private func finiteYCardReadOnlyError(
    _ error: Error,
    fallback: YCardReadOnlyError = .unavailable
) -> Error {
    if error is CancellationError { return error }
    return (error as? YCardReadOnlyError) ?? fallback
}

private func finiteYCardReadOnlyMessage(_ error: Error) -> String {
    let error = (error as? YCardReadOnlyError) ?? .unavailable
    return error.errorDescription ?? "学校校园卡服务暂不可用，请稍后重试"
}

enum YCardReadOnlyEndpoint: Equatable, Sendable {
    case cardAccount
    case feeItemData

    var method: String {
        switch self {
        case .cardAccount: "GET"
        case .feeItemData: "POST"
        }
    }

    var path: String {
        switch self {
        case .cardAccount: "/berserker-app/ykt/tsm/queryCard"
        case .feeItemData: "/charge/feeitem/getThirdData"
        }
    }
}

enum YCardReadOnlyContract {
    static let cardAccountQuery = [
        URLQueryItem(name: "scene", value: "cardRecharge"),
        URLQueryItem(name: "synAccessSource", value: "h5")
    ]

    static func bathroomForm(
        feeItemID: String,
        phone: String
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "feeitemid", value: feeItemID),
            URLQueryItem(name: "type", value: "IEC"),
            URLQueryItem(name: "level", value: "1"),
            URLQueryItem(name: "telPhone", value: phone)
        ]
    }

    static func isValidPhone(_ value: String) -> Bool {
        value.count == 11 && value.allSatisfy { isASCIIDigit($0) }
    }

    static func normalizedPhone(_ value: String) -> String {
        String(value.filter { isASCIIDigit($0) })
    }

    static func electricitySelectionForm(
        level: String,
        values: [URLQueryItem] = []
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "feeitemid", value: "488"),
            URLQueryItem(name: "type", value: "select"),
            URLQueryItem(name: "level", value: level)
        ] + values
    }

    static func electricityRoomForm(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) -> [URLQueryItem] {
        [
            URLQueryItem(name: "feeitemid", value: "488"),
            URLQueryItem(name: "type", value: "IEC"),
            URLQueryItem(name: "level", value: "4"),
            URLQueryItem(name: "campus", value: campus.value),
            URLQueryItem(name: "building", value: building.value),
            URLQueryItem(name: "floor", value: floor.value),
            URLQueryItem(name: "room", value: room.value)
        ]
    }

    private static func isASCIIDigit(_ character: Character) -> Bool {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first else {
            return false
        }
        return (48...57).contains(scalar.value)
    }
}

enum YCardReadOnlyRequestPolicy {
    static let credentialPersistence: CMBRechargeCredentialPersistence = .memoryOnly

    static func authorize(_ request: URLRequest) throws {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "ycard.ahu.edu.cn",
              url.user == nil,
              url.password == nil,
              url.port == nil || url.port == 443 else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        let method = request.httpMethod?.uppercased() ?? "GET"
        switch (method, url.path) {
        case ("GET", "/berserker-app/ykt/tsm/queryCard"):
            try authorizeCardAccountRequest(request)
        case ("POST", "/charge/feeitem/getThirdData"):
            try authorizeFeeItemRequest(request)
        default:
            throw YCardReadOnlyError.disallowedEndpoint
        }
    }

    private static func authorizeCardAccountRequest(
        _ request: URLRequest
    ) throws {
        guard request.httpBody == nil,
              let url = request.url,
              let items = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              )?.queryItems else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        guard Set(items.map(\.name)).count == items.count else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        let values = Dictionary(uniqueKeysWithValues:
            items.map { ($0.name, $0.value ?? "") }
        )
        guard Set(values.keys) == ["scene", "synAccessSource"],
              values["scene"] == "cardRecharge",
              values["synAccessSource"] == "h5" else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
    }

    private static func authorizeFeeItemRequest(
        _ request: URLRequest
    ) throws {
        guard let url = request.url,
              URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              )?.queryItems?.isEmpty != false else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        guard let body = request.httpBody,
              let query = String(data: body, encoding: .utf8) else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        var components = URLComponents()
        components.percentEncodedQuery = query
        guard let items = components.queryItems else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        guard Set(items.map(\.name)).count == items.count else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
        let values = Dictionary(uniqueKeysWithValues:
            items.map { ($0.name, $0.value ?? "") }
        )
        guard values.values.allSatisfy({ !$0.isEmpty }),
              let feeItemID = values["feeitemid"],
              let type = values["type"],
              let level = values["level"] else {
            throw YCardReadOnlyError.disallowedEndpoint
        }

        let expectedKeys: Set<String>
        switch (feeItemID, type, level) {
        case ("409", "IEC", "1"), ("430", "IEC", "1"):
            guard let phone = values["telPhone"],
                  YCardReadOnlyContract.isValidPhone(phone) else {
                throw YCardReadOnlyError.disallowedEndpoint
            }
            expectedKeys = ["feeitemid", "type", "level", "telPhone"]
        case ("488", "select", "0"):
            expectedKeys = ["feeitemid", "type", "level"]
        case ("488", "select", "1"):
            expectedKeys = ["feeitemid", "type", "level", "campus"]
        case ("488", "select", "2"):
            expectedKeys = [
                "feeitemid",
                "type",
                "level",
                "campus",
                "building"
            ]
        case ("488", "select", "3"):
            expectedKeys = [
                "feeitemid",
                "type",
                "level",
                "campus",
                "building",
                "floor"
            ]
        case ("488", "IEC", "4"):
            expectedKeys = [
                "feeitemid",
                "type",
                "level",
                "campus",
                "building",
                "floor",
                "room"
            ]
        default:
            throw YCardReadOnlyError.disallowedEndpoint
        }
        guard Set(values.keys) == expectedKeys else {
            throw YCardReadOnlyError.disallowedEndpoint
        }
    }
}

private final class YCardReadOnlyNoRedirectDelegate:
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

actor YCardReadOnlyClient {
    private static let origin = URL(string: "https://ycard.ahu.edu.cn")!

    private let campusAPI: any CampusCoreAPI
    private let session: URLSession
    private var accessToken: String?
    private var sessionCookies: [CampusCookie] = []

    init(campusAPI: any CampusCoreAPI) {
        self.campusAPI = campusAPI
        let configuration = Self.makeConfiguration()
        session = URLSession(
            configuration: configuration,
            delegate: YCardReadOnlyNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    init(
        campusAPI: any CampusCoreAPI,
        configuration: URLSessionConfiguration
    ) {
        self.campusAPI = campusAPI
        session = URLSession(
            configuration: configuration,
            delegate: YCardReadOnlyNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    static func makeConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
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

    deinit {
        session.invalidateAndCancel()
    }

    func request(
        _ endpoint: YCardReadOnlyEndpoint,
        queryItems: [URLQueryItem] = [],
        formItems: [URLQueryItem] = []
    ) async throws -> Data {
        try await prepareCredentialsIfNeeded()
        let request = try Self.makeRequest(
            endpoint,
            queryItems: queryItems,
            formItems: formItems,
            accessToken: accessToken,
            cookies: sessionCookies
        )
        let result: (Data, URLResponse)
        do {
            result = try await session.data(for: request)
        } catch {
            if Task.isCancelled { throw CancellationError() }
            throw finiteYCardReadOnlyError(error)
        }
        let (data, rawResponse) = result
        guard let response = rawResponse as? HTTPURLResponse else {
            throw YCardReadOnlyError.invalidResponse
        }
        guard response.url == request.url else {
            clearCredentials()
            throw YCardReadOnlyError.invalidResponse
        }
        if (300..<400).contains(response.statusCode)
            || response.statusCode == 401
            || response.statusCode == 403 {
            clearCredentials()
            throw YCardReadOnlyError.credentialsUnavailable
        }
        captureResponseCookies(response, requestURL: request.url)
        guard (200..<300).contains(response.statusCode), !data.isEmpty else {
            throw YCardReadOnlyError.unavailable
        }
        return data
    }

    func clearCredentials() {
        accessToken = nil
        sessionCookies.removeAll(keepingCapacity: false)
    }

    static func makeRequest(
        _ endpoint: YCardReadOnlyEndpoint,
        queryItems: [URLQueryItem] = [],
        formItems: [URLQueryItem] = [],
        accessToken: String?,
        cookies: [CampusCookie]
    ) throws -> URLRequest {
        var components = URLComponents(
            string: "\(origin.absoluteString)\(endpoint.path)"
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw YCardReadOnlyError.disallowedEndpoint
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = endpoint.method
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        if endpoint == .feeItemData {
            request.setValue(
                "https://ycard.ahu.edu.cn/charge-app/",
                forHTTPHeaderField: "Referer"
            )
            request.setValue(
                origin.absoluteString,
                forHTTPHeaderField: "Origin"
            )
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
        if !formItems.isEmpty {
            var formComponents = URLComponents()
            formComponents.queryItems = formItems
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
        }
        try YCardReadOnlyRequestPolicy.authorize(request)
        return request
    }

    private func prepareCredentialsIfNeeded() async throws {
        guard accessToken == nil else { return }
        let token: String
        do {
            token = try await campusAPI.cardAccessToken()
        } catch let error as CampusCoreError where error == .unauthorized {
            throw YCardReadOnlyError.credentialsUnavailable
        } catch {
            throw YCardReadOnlyError.credentialsUnavailable
        }
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw YCardReadOnlyError.credentialsUnavailable
        }
        accessToken = token
        let rawCookies = (try? await campusAPI.cookiesFlat()) ?? "[]"
        let cookies = (try? JSONDecoder().decode(
            [CampusCookie].self,
            from: Data(rawCookies.utf8)
        )) ?? []
        sessionCookies = cookies.filter(CampusCookieWebBridge.isTrustedSchoolCookie)
    }

    private func captureResponseCookies(
        _ response: HTTPURLResponse,
        requestURL: URL?
    ) {
        guard let requestURL else { return }
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
}

struct CardRechargeAccountSnapshot: Equatable, Sendable {
    let id: String
    let name: String
    let type: String
    let balance: Decimal

    var displayName: String {
        [name, type]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }
}

struct BathroomLookupResult: Equatable, Sendable {
    let account: BathroomPaymentAccount?
    let message: String?
}

struct YCardSelectionOption:
    Identifiable,
    Codable,
    Equatable,
    Hashable,
    Sendable
{
    let name: String
    let value: String

    var id: String { value }
}

enum YCardPaymentDecoder {
    static func decodeCardAccount(_ data: Data) throws -> CardRechargeAccountSnapshot? {
        let envelope: CardAccountEnvelope
        do {
            envelope = try JSONDecoder().decode(CardAccountEnvelope.self, from: data)
        } catch {
            throw YCardReadOnlyError.invalidResponse
        }
        if let success = envelope.success, !success {
            throw YCardReadOnlyError.server
        }
        guard envelope.code == 200 else {
            throw YCardReadOnlyError.server
        }
        guard let account = envelope.data?.card.first?.accounts.first else {
            return nil
        }
        return CardRechargeAccountSnapshot(
            id: account.type,
            name: account.name,
            type: account.type,
            balance: Decimal(account.balance) / Decimal(100)
        )
    }

    static func decodeBathroomAccount(
        _ data: Data,
        bathroomName: String,
        requestedPhone: String
    ) throws -> BathroomLookupResult {
        let envelope: BathroomEnvelope
        do {
            envelope = try JSONDecoder().decode(BathroomEnvelope.self, from: data)
        } catch {
            throw YCardReadOnlyError.invalidResponse
        }
        guard envelope.code == 0 || envelope.code == 200 else {
            throw YCardReadOnlyError.server
        }
        guard let payload = envelope.map,
              let display = payload.showData else {
            return BathroomLookupResult(
                account: nil,
                message: "未查询到浴室账户"
            )
        }
        let phone = display.phone.nilIfEmpty
            ?? payload.data?.phone?.nilIfEmpty
            ?? requestedPhone
        let identifier = payload.data?.accountID.map { String($0) }
            ?? payload.data?.identifier?.nilIfEmpty
            ?? "\(bathroomName)-\(phone)"
        guard let cashBalance = decimal(from: display.cashAmount),
              let giftBalance = decimal(from: display.giftAmount) else {
            throw YCardReadOnlyError.invalidResponse
        }
        return BathroomLookupResult(
            account: BathroomPaymentAccount(
                id: identifier,
                name: bathroomName,
                phone: phone,
                cashBalance: cashBalance,
                giftBalance: giftBalance
            ),
            message: nil
        )
    }

    static func decodeSelectionOptions(_ data: Data) throws -> [YCardSelectionOption] {
        let envelope: SelectionEnvelope
        do {
            envelope = try JSONDecoder().decode(SelectionEnvelope.self, from: data)
        } catch {
            throw YCardReadOnlyError.invalidResponse
        }
        guard envelope.code == 0 || envelope.code == 200 else {
            throw YCardReadOnlyError.server
        }
        return envelope.map?.data ?? []
    }

    static func decodeElectricityRoom(
        _ data: Data,
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) throws -> ElectricityRoom {
        let envelope: ElectricityRoomEnvelope
        do {
            envelope = try JSONDecoder().decode(
                ElectricityRoomEnvelope.self,
                from: data
            )
        } catch {
            throw YCardReadOnlyError.invalidResponse
        }
        guard (envelope.code == 0 || envelope.code == 200),
              let payload = envelope.map else {
            throw YCardReadOnlyError.server
        }
        let information = payload.showData?.information?.nilIfEmpty
        let details = payload.data
        let resolvedCampus = details?.areaName?.nilIfEmpty ?? campus.name
        let resolvedBuilding = details?.buildingName?.nilIfEmpty ?? building.name
        let resolvedFloor = details?.floorName?.nilIfEmpty ?? floor.name
        let resolvedRoom = details?.roomName?.nilIfEmpty ?? room.name
        let identifier = details?.account?.nilIfEmpty
            ?? [campus.value, building.value, floor.value, room.value]
                .joined(separator: "|")
        return ElectricityRoom(
            id: identifier,
            campus: resolvedCampus,
            building: resolvedBuilding,
            floor: resolvedFloor,
            room: resolvedRoom,
            balance: balance(from: information),
            information: information
        )
    }

    private static func decimal(from rawValue: String?) -> Decimal? {
        guard let rawValue,
              let range = rawValue.range(
                  of: #"-?\d+(?:\.\d{1,2})?"#,
                  options: .regularExpression
              ) else {
            return nil
        }
        return Decimal(
            string: String(rawValue[range]),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    private static func balance(from information: String?) -> Decimal? {
        guard let information,
              let range = information.range(
                   of: #"(?:余额|剩余电量)[^0-9-]*-?\d+(?:\.\d{1,2})?"#,
                  options: .regularExpression
              ) else {
            return nil
        }
        return decimal(from: String(information[range]))
    }
}

private struct CardAccountEnvelope: Decodable {
    struct Payload: Decodable {
        struct Card: Decodable {
            struct Account: Decodable {
                let balance: Int
                let name: String
                let type: String
            }

            let accounts: [Account]

            enum CodingKeys: String, CodingKey {
                case accounts = "accinfo"
            }
        }

        let card: [Card]
    }

    let code: Int
    let data: Payload?
    let msg: String?
    let success: Bool?
}

private struct BathroomEnvelope: Decodable {
    struct Payload: Decodable {
        struct Display: Decodable {
            let phone: String
            let cashAmount: String
            let giftAmount: String

            enum CodingKeys: String, CodingKey {
                case phone = "手机号"
                case cashAmount = "现金金额（单位：元）"
                case giftAmount = "赠送金额（单位：元）"
            }
        }

        struct Detail: Decodable {
            let accountID: Int?
            let phone: String?
            let identifier: String?
            let message: String?

            enum CodingKeys: String, CodingKey {
                case accountID = "accountId"
                case phone = "telPhone"
                case identifier
                case message
            }
        }

        let showData: Display?
        let data: Detail?
    }

    let msg: String?
    let code: Int
    let map: Payload?
    let message: String?
}

private struct SelectionEnvelope: Decodable {
    struct Payload: Decodable {
        let data: [YCardSelectionOption]?
    }

    let msg: String?
    let code: Int
    let map: Payload?
}

private struct ElectricityRoomEnvelope: Decodable {
    struct Payload: Decodable {
        struct Display: Decodable {
            let information: String?

            enum CodingKeys: String, CodingKey {
                case information = "信息"
            }
        }

        struct Detail: Decodable {
            let area: String?
            let areaName: String?
            let building: String?
            let buildingName: String?
            let floor: String?
            let floorName: String?
            let aid: String?
            let account: String?
            let room: String?
            let roomName: String?
        }

        let showData: Display?
        let data: Detail?
    }

    let msg: String?
    let code: Int
    let map: Payload?
}

protocol CardRechargeAccountDataSource: Sendable {
    func load() async throws -> CardRechargeAccountSnapshot?
}

actor OfficialCardRechargeAccountDataSource: CardRechargeAccountDataSource {
    private let client: YCardReadOnlyClient

    init(campusAPI: any CampusCoreAPI) {
        client = YCardReadOnlyClient(campusAPI: campusAPI)
    }

    init(
        campusAPI: any CampusCoreAPI,
        configuration: URLSessionConfiguration
    ) {
        client = YCardReadOnlyClient(
            campusAPI: campusAPI,
            configuration: configuration
        )
    }

    func load() async throws -> CardRechargeAccountSnapshot? {
        do {
            let data = try await client.request(
                .cardAccount,
                queryItems: YCardReadOnlyContract.cardAccountQuery
            )
            let account = try YCardPaymentDecoder.decodeCardAccount(data)
            await client.clearCredentials()
            return account
        } catch {
            await client.clearCredentials()
            throw finiteYCardReadOnlyError(error)
        }
    }
}

struct DemoCardRechargeAccountDataSource: CardRechargeAccountDataSource {
    func load() async throws -> CardRechargeAccountSnapshot? {
        CardRechargeAccountSnapshot(
            id: PaymentDemoCatalog.cardAccountID,
            name: PaymentDemoCatalog.cardAccountLabel,
            type: "",
            balance: PaymentDemoCatalog.cardBalance
        )
    }
}

protocol BathroomAccountDataSource: Sendable {
    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult
}

actor OfficialBathroomAccountDataSource: BathroomAccountDataSource {
    private let client: YCardReadOnlyClient

    init(campusAPI: any CampusCoreAPI) {
        client = YCardReadOnlyClient(campusAPI: campusAPI)
    }

    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult {
        let feeItemID: String
        switch bathroomName {
        case "竹园/龙河": feeItemID = "409"
        case "桔园/蕙园": feeItemID = "430"
        default:
            throw YCardReadOnlyError.invalidResponse
        }

        do {
            let data = try await client.request(
                .feeItemData,
                formItems: YCardReadOnlyContract.bathroomForm(
                    feeItemID: feeItemID,
                    phone: phone
                )
            )
            let result = try YCardPaymentDecoder.decodeBathroomAccount(
                data,
                bathroomName: bathroomName,
                requestedPhone: phone
            )
            await client.clearCredentials()
            return result
        } catch {
            await client.clearCredentials()
            throw finiteYCardReadOnlyError(error)
        }
    }
}

struct DemoBathroomAccountDataSource: BathroomAccountDataSource {
    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult {
        let prefix = bathroomName.components(separatedBy: "/").first ?? bathroomName
        guard let fixture = PaymentDemoCatalog.bathrooms.first(
            where: { $0.name.hasPrefix(prefix) }
        ) else {
            return BathroomLookupResult(
                account: nil,
                message: "未查询到浴室账户"
            )
        }
        return BathroomLookupResult(
            account: BathroomPaymentAccount(
                id: fixture.id,
                name: bathroomName,
                phone: phone,
                cashBalance: fixture.cashBalance,
                giftBalance: fixture.giftBalance
            ),
            message: nil
        )
    }
}

protocol ElectricityAccountDataSource: Sendable {
    func campuses() async throws -> [YCardSelectionOption]
    func buildings(campus: YCardSelectionOption) async throws -> [YCardSelectionOption]
    func floors(
        campus: YCardSelectionOption,
        building: YCardSelectionOption
    ) async throws -> [YCardSelectionOption]
    func rooms(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption
    ) async throws -> [YCardSelectionOption]
    func room(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) async throws -> ElectricityRoom
    func clearCredentials() async
}

actor OfficialElectricityAccountDataSource: ElectricityAccountDataSource {
    private let client: YCardReadOnlyClient

    init(campusAPI: any CampusCoreAPI) {
        client = YCardReadOnlyClient(campusAPI: campusAPI)
    }

    func campuses() async throws -> [YCardSelectionOption] {
        try await selection(level: "0")
    }

    func buildings(
        campus: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        try await selection(
            level: "1",
            values: [URLQueryItem(name: "campus", value: campus.value)]
        )
    }

    func floors(
        campus: YCardSelectionOption,
        building: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        try await selection(
            level: "2",
            values: [
                URLQueryItem(name: "campus", value: campus.value),
                URLQueryItem(name: "building", value: building.value)
            ]
        )
    }

    func rooms(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        try await selection(
            level: "3",
            values: [
                URLQueryItem(name: "campus", value: campus.value),
                URLQueryItem(name: "building", value: building.value),
                URLQueryItem(name: "floor", value: floor.value)
            ]
        )
    }

    func room(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) async throws -> ElectricityRoom {
        do {
            let data = try await client.request(
                .feeItemData,
                formItems: YCardReadOnlyContract.electricityRoomForm(
                    campus: campus,
                    building: building,
                    floor: floor,
                    room: room
                )
            )
            return try YCardPaymentDecoder.decodeElectricityRoom(
                data,
                campus: campus,
                building: building,
                floor: floor,
                room: room
            )
        } catch {
            throw finiteYCardReadOnlyError(error)
        }
    }

    func clearCredentials() async {
        await client.clearCredentials()
    }

    private func selection(
        level: String,
        values: [URLQueryItem] = []
    ) async throws -> [YCardSelectionOption] {
        do {
            let data = try await client.request(
                .feeItemData,
                formItems: YCardReadOnlyContract.electricitySelectionForm(
                    level: level,
                    values: values
                )
            )
            return try YCardPaymentDecoder.decodeSelectionOptions(data)
        } catch {
            throw finiteYCardReadOnlyError(error)
        }
    }
}

struct DemoElectricityAccountDataSource: ElectricityAccountDataSource {
    func campuses() async throws -> [YCardSelectionOption] {
        options(PaymentDemoCatalog.electricityRooms.map(\.campus))
    }

    func buildings(
        campus: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        options(
            PaymentDemoCatalog.electricityRooms
                .filter { $0.campus == campus.name }
                .map(\.building)
        )
    }

    func floors(
        campus: YCardSelectionOption,
        building: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        options(
            PaymentDemoCatalog.electricityRooms
                .filter {
                    $0.campus == campus.name
                        && $0.building == building.name
                }
                .map(\.floor)
        )
    }

    func rooms(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        options(
            PaymentDemoCatalog.electricityRooms
                .filter {
                    $0.campus == campus.name
                        && $0.building == building.name
                        && $0.floor == floor.name
                }
                .map(\.room)
        )
    }

    func room(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) async throws -> ElectricityRoom {
        guard let result = PaymentDemoCatalog.electricityRooms.first(where: {
            $0.campus == campus.name
                && $0.building == building.name
                && $0.floor == floor.name
                && $0.room == room.name
        }) else {
            throw YCardReadOnlyError.invalidResponse
        }
        return result
    }

    func clearCredentials() async { }

    private func options(_ values: [String]) -> [YCardSelectionOption] {
        values.reduce(into: []) { result, value in
            guard !result.contains(where: { $0.name == value }) else { return }
            result.append(YCardSelectionOption(name: value, value: value))
        }
    }
}

@MainActor
final class CardRechargeAccountViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready(CardRechargeAccountSnapshot)
        case empty
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    private let dataSource: any CardRechargeAccountDataSource
    private var revision = 0

    init(dataSource: any CardRechargeAccountDataSource) {
        self.dataSource = dataSource
    }

    var readyAccount: CardRechargeAccountSnapshot? {
        guard case let .ready(account) = state else { return nil }
        return account
    }

    func requireReadyAccount() throws -> CardRechargeAccountSnapshot {
        guard let readyAccount else {
            throw PaymentValidationError.missingAccount
        }
        return readyAccount
    }

    func load() async {
        revision += 1
        let requestRevision = revision
        state = .loading
        do {
            let account = try await dataSource.load()
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            if let account {
                state = .ready(account)
            } else {
                state = .empty
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            state = .failed(finiteYCardReadOnlyMessage(error))
        }
    }
}

@MainActor
final class BathroomAccountViewModel: ObservableObject {
    enum State: Equatable {
        case idle
        case loading
        case ready(BathroomPaymentAccount)
        case empty(String)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    private let dataSource: any BathroomAccountDataSource
    private var revision = 0

    init(dataSource: any BathroomAccountDataSource) {
        self.dataSource = dataSource
    }

    var account: BathroomPaymentAccount? {
        guard case let .ready(account) = state else { return nil }
        return account
    }

    func lookup(bathroomName: String, phone: String) async {
        revision += 1
        let requestRevision = revision
        guard YCardReadOnlyContract.isValidPhone(phone) else {
            state = .idle
            return
        }
        state = .loading
        do {
            let result = try await dataSource.lookup(
                bathroomName: bathroomName,
                phone: phone
            )
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            if let account = result.account {
                state = .ready(account)
            } else {
                state = .empty(result.message ?? "未查询到浴室账户")
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            state = .failed(finiteYCardReadOnlyMessage(error))
        }
    }

    func reset() {
        revision += 1
        state = .idle
    }
}

@MainActor
final class ElectricityAccountViewModel: ObservableObject {
    @Published private(set) var campuses: [YCardSelectionOption] = []
    @Published private(set) var buildings: [YCardSelectionOption] = []
    @Published private(set) var floors: [YCardSelectionOption] = []
    @Published private(set) var rooms: [YCardSelectionOption] = []
    @Published private(set) var selectedCampus: YCardSelectionOption?
    @Published private(set) var selectedBuilding: YCardSelectionOption?
    @Published private(set) var selectedFloor: YCardSelectionOption?
    @Published private(set) var selectedRoomOption: YCardSelectionOption?
    @Published private(set) var selectedRoom: ElectricityRoom?
    @Published private(set) var isLoading = false
    @Published private(set) var emptyMessage: String?
    @Published private(set) var errorMessage: String?

    private let dataSource: any ElectricityAccountDataSource
    private var task: Task<Void, Never>?
    private var revision = 0

    init(dataSource: any ElectricityAccountDataSource) {
        self.dataSource = dataSource
    }

    func load() async {
        task?.cancel()
        task = nil
        revision += 1
        let requestRevision = revision
        await loadCampuses(revision: requestRevision)
    }

    @discardableResult
    func selectCampus(named name: String) -> Task<Void, Never>? {
        guard let option = campuses.first(where: { $0.name == name }) else {
            return nil
        }
        let requestRevision = beginRequest()
        selectedCampus = option
        selectedBuilding = nil
        selectedFloor = nil
        selectedRoomOption = nil
        selectedRoom = nil
        buildings = []
        floors = []
        rooms = []
        let loadTask = Task<Void, Never> { [weak self] in
            guard let self else { return }
            await self.loadBuildings(
                campus: option,
                revision: requestRevision
            )
        }
        task = loadTask
        return loadTask
    }

    func selectBuilding(named name: String) {
        guard let campus = selectedCampus,
              let option = buildings.first(where: { $0.name == name }) else {
            return
        }
        let requestRevision = beginRequest()
        selectedBuilding = option
        selectedFloor = nil
        selectedRoomOption = nil
        selectedRoom = nil
        floors = []
        rooms = []
        task = Task { [weak self] in
            await self?.loadFloors(
                campus: campus,
                building: option,
                revision: requestRevision
            )
        }
    }

    func selectFloor(named name: String) {
        guard let campus = selectedCampus,
              let building = selectedBuilding,
              let option = floors.first(where: { $0.name == name }) else {
            return
        }
        let requestRevision = beginRequest()
        selectedFloor = option
        selectedRoomOption = nil
        selectedRoom = nil
        rooms = []
        task = Task { [weak self] in
            await self?.loadRooms(
                campus: campus,
                building: building,
                floor: option,
                revision: requestRevision
            )
        }
    }

    func selectRoom(named name: String) {
        guard let campus = selectedCampus,
              let building = selectedBuilding,
              let floor = selectedFloor,
              let option = rooms.first(where: { $0.name == name }) else {
            return
        }
        let requestRevision = beginRequest()
        selectedRoomOption = option
        selectedRoom = nil
        task = Task { [weak self] in
            await self?.loadRoom(
                campus: campus,
                building: building,
                floor: floor,
                room: option,
                revision: requestRevision
            )
        }
    }

    func select(_ room: ElectricityRoom) {
        _ = beginRequest()
        isLoading = false
        selectedCampus = campuses.first(where: { $0.name == room.campus })
            ?? YCardSelectionOption(name: room.campus, value: room.campus)
        selectedBuilding = YCardSelectionOption(
            name: room.building,
            value: room.building
        )
        selectedFloor = YCardSelectionOption(name: room.floor, value: room.floor)
        selectedRoomOption = YCardSelectionOption(name: room.room, value: room.room)
        selectedRoom = room
    }

    func retry() {
        let requestRevision = beginRequest()
        if let campus = selectedCampus,
           let building = selectedBuilding,
           let floor = selectedFloor,
           let room = selectedRoomOption {
            task = Task { [weak self] in
                await self?.loadRoom(
                    campus: campus,
                    building: building,
                    floor: floor,
                    room: room,
                    revision: requestRevision
                )
            }
        } else if let campus = selectedCampus,
                  let building = selectedBuilding,
                  let floor = selectedFloor {
            task = Task { [weak self] in
                await self?.loadRooms(
                    campus: campus,
                    building: building,
                    floor: floor,
                    revision: requestRevision
                )
            }
        } else if let campus = selectedCampus,
                  let building = selectedBuilding {
            task = Task { [weak self] in
                await self?.loadFloors(
                    campus: campus,
                    building: building,
                    revision: requestRevision
                )
            }
        } else if let campus = selectedCampus {
            task = Task { [weak self] in
                await self?.loadBuildings(
                    campus: campus,
                    revision: requestRevision
                )
            }
        } else {
            task = Task { [weak self] in
                await self?.loadCampuses(revision: requestRevision)
            }
        }
    }

    func clearCredentials() async {
        task?.cancel()
        task = nil
        revision += 1
        isLoading = false
        await dataSource.clearCredentials()
    }

    private func beginRequest() -> Int {
        task?.cancel()
        task = nil
        revision += 1
        isLoading = false
        emptyMessage = nil
        errorMessage = nil
        return revision
    }

    private func loadCampuses(revision requestRevision: Int) async {
        guard startLoading(revision: requestRevision) else { return }
        defer { finishLoading(revision: requestRevision) }
        do {
            let result = try await dataSource.campuses()
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            campuses = result
            if result.isEmpty {
                emptyMessage = "学校服务暂未返回可用校区"
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            errorMessage = finiteYCardReadOnlyMessage(error)
        }
    }

    private func loadBuildings(
        campus: YCardSelectionOption,
        revision requestRevision: Int
    ) async {
        guard startLoading(revision: requestRevision) else { return }
        defer { finishLoading(revision: requestRevision) }
        do {
            let result = try await dataSource.buildings(campus: campus)
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            buildings = result
            if result.isEmpty {
                emptyMessage = "该校区暂未返回可用楼栋"
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            errorMessage = finiteYCardReadOnlyMessage(error)
        }
    }

    private func loadFloors(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        revision requestRevision: Int
    ) async {
        guard startLoading(revision: requestRevision) else { return }
        defer { finishLoading(revision: requestRevision) }
        do {
            let result = try await dataSource.floors(
                campus: campus,
                building: building
            )
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            floors = result
            if result.isEmpty {
                emptyMessage = "该楼栋暂未返回可用楼层"
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            errorMessage = finiteYCardReadOnlyMessage(error)
        }
    }

    private func loadRooms(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        revision requestRevision: Int
    ) async {
        guard startLoading(revision: requestRevision) else { return }
        defer { finishLoading(revision: requestRevision) }
        do {
            let result = try await dataSource.rooms(
                campus: campus,
                building: building,
                floor: floor
            )
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            rooms = result
            if result.isEmpty {
                emptyMessage = "该楼层暂未返回可用房间"
            }
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            errorMessage = finiteYCardReadOnlyMessage(error)
        }
    }

    private func loadRoom(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption,
        revision requestRevision: Int
    ) async {
        guard startLoading(revision: requestRevision) else { return }
        defer { finishLoading(revision: requestRevision) }
        do {
            let result = try await dataSource.room(
                campus: campus,
                building: building,
                floor: floor,
                room: room
            )
            try Task.checkCancellation()
            guard requestRevision == revision else { return }
            selectedRoom = result
        } catch is CancellationError {
            return
        } catch {
            guard requestRevision == revision else { return }
            errorMessage = finiteYCardReadOnlyMessage(error)
        }
    }

    private func startLoading(revision requestRevision: Int) -> Bool {
        guard requestRevision == revision else { return false }
        isLoading = true
        emptyMessage = nil
        errorMessage = nil
        return true
    }

    private func finishLoading(revision requestRevision: Int) {
        guard requestRevision == revision else { return }
        isLoading = false
    }
}

enum AlipayCampusCardHandoff {
    static let appURL = URL(
        string: "alipays://platformapi/startapp?appId=2019090967125695&page=pages%2Findex%2Findex&chInfo=ch_share__chsub_CopyLink"
    )!

    static func isAllowed(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "alipays",
              url.host?.lowercased() == "platformapi",
              url.path == "/startapp",
              let components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ),
              let appID = components.queryItems?
                  .first(where: { $0.name == "appId" })?
                  .value else {
            return false
        }
        return appID == "2019090967125695"
            && components.queryItems?.contains(where: {
                $0.name == "order"
                    || $0.name == "token"
                    || $0.name == "synjones-auth"
                    || $0.name == "studentID"
                    || $0.name == "name"
            }) == false
    }
}

private extension String {
    var nilIfEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
