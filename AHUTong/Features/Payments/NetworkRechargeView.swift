import Foundation
import SafariServices
import SwiftUI

enum NetworkRechargeOperation: Equatable, Sendable {
    case warmUpEntry
    case readConfiguration
    case readAccount
    case nativeDebit
}

enum NetworkRechargeSafetyError: LocalizedError, Equatable {
    case disallowedEndpoint
    case nativeDebitDisabled
    case invalidResponse
    case unavailable

    var errorDescription: String? {
        switch self {
        case .disallowedEndpoint:
            "已阻止不在只读白名单中的校园卡请求"
        case .nativeDebitDisabled:
            "iOS 客户端不在本机生成扣款签名，请前往学校官方门户完成充值"
        case .invalidResponse:
            "学校网费服务返回了无法识别的数据"
        case .unavailable:
            "学校网费服务暂不可用，请稍后重试"
        }
    }
}

enum NetworkRechargeRequestPolicy {
    static let nativeDebitEnabled = false
    static let credentialPersistence: CMBRechargeCredentialPersistence = .memoryOnly

    private static let allowedRequests: Set<String> = [
        "GET /charge/feeitem/singleFeeitem",
        "GET /charge/feeitem/toAppitem",
        "POST /charge/feeitem/getThirdData"
    ]

    static func authorize(_ operation: NetworkRechargeOperation) throws {
        if operation == .nativeDebit {
            throw NetworkRechargeSafetyError.nativeDebitDisabled
        }
    }

    static func authorize(_ request: URLRequest) throws {
        guard let url = request.url,
              url.scheme?.lowercased() == "https",
              url.host?.lowercased() == "ycard.ahu.edu.cn" else {
            throw NetworkRechargeSafetyError.disallowedEndpoint
        }
        let method = request.httpMethod?.uppercased() ?? "GET"
        guard allowedRequests.contains("\(method) \(url.path)") else {
            throw NetworkRechargeSafetyError.disallowedEndpoint
        }
    }
}

enum NetworkRechargeSessionCredentials {
    static func authorizationHeader(accessToken: String) -> String? {
        let token = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : "bearer \(token)"
    }

    static func cookieHeader(
        cookies: [CampusCookie],
        for url: URL
    ) -> String? {
        let value = cookies
            .filter(CampusCookieWebBridge.isTrustedSchoolCookie)
            .filter { $0.matches(url) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
        return value.isEmpty ? nil : value
    }
}

enum NetworkRechargeHeaderProfile: Equatable, Sendable {
    case entry
    case chargeAPI

    var referer: String {
        switch self {
        case .entry:
            "https://ycard.ahu.edu.cn/plat/dating?index=1"
        case .chargeAPI:
            "https://ycard.ahu.edu.cn/charge-app/"
        }
    }

    var accept: String {
        switch self {
        case .entry:
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        case .chargeAPI:
            "application/json, text/plain, */*"
        }
    }

    var sendsOrigin: Bool {
        self == .chargeAPI
    }
}

struct NetworkRechargeFeeItem: Decodable, Equatable, Sendable {
    let name: String?
    let layout: String?
    let maxMoney: String?
    let dayMaxMoney: String?
    let billingUnit: String?

    enum CodingKeys: String, CodingKey {
        case name
        case layout
        case maxMoney = "maxmoney"
        case dayMaxMoney = "daymaxmoney"
        case billingUnit = "billing_unit"
    }
}

struct NetworkRechargeAccountDetail: Decodable, Equatable, Sendable {
    let account: String?
}

private struct NetworkRechargeFeeEnvelope: Decodable {
    let code: Int
    let feeitem: NetworkRechargeFeeItem?
}

private struct NetworkRechargeAccountEnvelope: Decodable {
    struct Payload: Decodable {
        let showData: [String: String]?
        let data: NetworkRechargeAccountDetail?
    }

    let code: Int
    let map: Payload?
}

private struct NetworkRechargeStatusEnvelope: Decodable {
    let code: Int
}

struct NetworkRechargeSnapshot: Equatable, Sendable {
    let feeName: String
    let account: String
    let statistics: [(label: String, value: String)]
    let quickAmounts: [String]
    let maximumAmountText: String?
    let billingUnit: String?

    static func == (lhs: NetworkRechargeSnapshot, rhs: NetworkRechargeSnapshot) -> Bool {
        let statisticsMatch = lhs.statistics.elementsEqual(rhs.statistics) {
            $0.label == $1.label && $0.value == $1.value
        }
        return lhs.feeName == rhs.feeName &&
            lhs.account == rhs.account &&
            statisticsMatch &&
            lhs.quickAmounts == rhs.quickAmounts &&
            lhs.maximumAmountText == rhs.maximumAmountText &&
            lhs.billingUnit == rhs.billingUnit
    }

    var maximumAmount: Decimal? {
        maximumAmountText.flatMap(NetworkRechargeAmountParser.decimal(from:))
    }

    static let demo = NetworkRechargeSnapshot(
        feeName: "校园网充值",
        account: "DEMO-NETWORK-001",
        statistics: [
            ("用户状态", "正常"),
            ("储值余额", "32.80 元"),
            ("本期已使用费用", "18.20 元"),
            ("本期已使用时长", "126 小时"),
            ("本期已使用流量", "48.6 GB")
        ],
        quickAmounts: ["10 元", "20 元", "50 元", "100 元"],
        maximumAmountText: "200",
        billingUnit: "元"
    )
}

enum NetworkRechargeDecoder {
    private static let priorityLabels = [
        "用户状态",
        "储值余额",
        "本期已使用费用",
        "本期已使用时长",
        "本期已使用流量"
    ]

    static func decode(
        configurationData: Data,
        accountData: Data
    ) throws -> NetworkRechargeSnapshot {
        let decoder = JSONDecoder()
        let configuration = try decoder.decode(NetworkRechargeFeeEnvelope.self, from: configurationData)
        let account = try decoder.decode(NetworkRechargeAccountEnvelope.self, from: accountData)
        guard configuration.code == 200,
              let feeItem = configuration.feeitem,
              account.code == 200,
              let payload = account.map,
              let detail = payload.data else {
            throw NetworkRechargeSafetyError.invalidResponse
        }

        let showData = payload.showData ?? [:]
        let priority = Set(priorityLabels)
        var statistics = priorityLabels.compactMap { label -> (String, String)? in
            guard let value = showData[label], !value.isEmpty else { return nil }
            return (label, value)
        }
        statistics.append(contentsOf: showData
            .filter { !priority.contains($0.key) && !$0.value.isEmpty }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { ($0.key, $0.value) })

        let quickAmounts = feeItem.layout?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? []

        return NetworkRechargeSnapshot(
            feeName: feeItem.name?.trimmingCharacters(in: .whitespacesAndNewlines)
                .nilIfEmpty ?? "网费充值",
            account: detail.account?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            statistics: statistics,
            quickAmounts: quickAmounts,
            maximumAmountText: feeItem.maxMoney?.nilIfEmpty ?? feeItem.dayMaxMoney?.nilIfEmpty,
            billingUnit: feeItem.billingUnit?.nilIfEmpty
        )
    }
}

enum NetworkRechargeAmountError: LocalizedError, Equatable {
    case missing
    case invalid
    case tooManyFractionDigits
    case exceedsLimit(Decimal)

    var errorDescription: String? {
        switch self {
        case .missing:
            "请输入充值金额"
        case .invalid:
            "请输入有效金额"
        case .tooManyFractionDigits:
            "金额最多保留两位小数"
        case let .exceedsLimit(limit):
            "单次最高可充值 \(NetworkRechargeAmountParser.displayText(for: limit)) 元"
        }
    }
}

struct NetworkRechargeAmount: Equatable, Sendable {
    static let fallbackMaximum = Decimal(500)

    let value: Decimal

    init(_ rawValue: String, maximum: Decimal?) throws {
        let rawValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            throw NetworkRechargeAmountError.missing
        }
        guard rawValue.range(
            of: #"^\d+(?:\.\d{0,2})?$"#,
            options: .regularExpression
        ) != nil else {
            if rawValue.range(
                of: #"^\d+\.\d{3,}$"#,
                options: .regularExpression
            ) != nil {
                throw NetworkRechargeAmountError.tooManyFractionDigits
            }
            throw NetworkRechargeAmountError.invalid
        }
        guard let amount = Decimal(
            string: rawValue,
            locale: Locale(identifier: "en_US_POSIX")
        ), amount > 0 else {
            throw NetworkRechargeAmountError.invalid
        }

        let limit = maximum ?? Self.fallbackMaximum
        guard amount <= limit else {
            throw NetworkRechargeAmountError.exceedsLimit(limit)
        }
        value = amount
    }

    var text: String {
        String(format: "%.2f", NSDecimalNumber(decimal: value).doubleValue)
    }
}

enum NetworkRechargeAmountParser {
    static func decimal(from rawValue: String) -> Decimal? {
        guard let match = rawValue.range(
            of: #"\d+(?:\.\d{1,2})?"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return Decimal(
            string: String(rawValue[match]),
            locale: Locale(identifier: "en_US_POSIX")
        )
    }

    static func inputText(from quickAmount: String) -> String {
        guard let value = decimal(from: quickAmount) else { return quickAmount }
        return displayText(for: value)
    }

    static func displayText(for value: Decimal) -> String {
        let number = NSDecimalNumber(decimal: value).doubleValue
        return number.rounded() == number
            ? String(format: "%.0f", number)
            : String(format: "%.2f", number)
    }
}

protocol NetworkRechargeDataSource: Sendable {
    func load() async throws -> NetworkRechargeSnapshot
}

private final class NetworkRechargeNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        // A token-bearing entry request must never be redirected to a host
        // selected by a remote response. The first 3xx response is sufficient
        // to establish this session's in-memory school cookies.
        completionHandler(nil)
    }
}

actor OfficialNetworkRechargeDataSource: NetworkRechargeDataSource {
    private static let origin = URL(string: "https://ycard.ahu.edu.cn")!

    private let campusAPI: any CampusCoreAPI
    private let session: URLSession
    private var accessToken: String?
    private var sessionCookies: [CampusCookie] = []

    init(campusAPI: any CampusCoreAPI) {
        self.campusAPI = campusAPI
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        configuration.urlCache = nil
        configuration.urlCredentialStorage = nil
        configuration.httpShouldSetCookies = true
        configuration.httpCookieAcceptPolicy = .onlyFromMainDocumentDomain
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        session = URLSession(
            configuration: configuration,
            delegate: NetworkRechargeNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func load() async throws -> NetworkRechargeSnapshot {
        let token = try await campusAPI.cardAccessToken()
        accessToken = token
        let rawCookies = (try? await campusAPI.cookiesFlat()) ?? "[]"
        let decodedCookies = (try? JSONDecoder().decode(
            [CampusCookie].self,
            from: Data(rawCookies.utf8)
        )) ?? []
        sessionCookies = decodedCookies.filter(CampusCookieWebBridge.isTrustedSchoolCookie)
        defer {
            accessToken = nil
            sessionCookies = []
        }
        try await warmUp(accessToken: token)
        try await selectNetworkFeeItem()
        let configuration = try await request(
            operation: .readConfiguration,
            method: "GET",
            path: "/charge/feeitem/singleFeeitem",
            queryItems: [URLQueryItem(name: "feeitemid", value: "431")]
        )
        let account = try await request(
            operation: .readAccount,
            method: "POST",
            path: "/charge/feeitem/getThirdData",
            formItems: [
                URLQueryItem(name: "feeitemid", value: "431"),
                URLQueryItem(name: "type", value: "IEC"),
                URLQueryItem(name: "level", value: "0")
            ]
        )
        return try NetworkRechargeDecoder.decode(
            configurationData: configuration,
            accountData: account
        )
    }

    private func warmUp(accessToken: String) async throws {
        try NetworkRechargeRequestPolicy.authorize(.warmUpEntry)
        let response = try await response(
            method: "GET",
            path: "/charge/feeitem/toAppitem",
            queryItems: [
                URLQueryItem(name: "feeitemid", value: "431"),
                URLQueryItem(name: "appId", value: "75"),
                URLQueryItem(name: "loginFrom", value: "h5"),
                URLQueryItem(name: "synAccessSource", value: "h5"),
                URLQueryItem(name: "synjones-auth", value: accessToken)
            ],
            headerProfile: .entry
        )
        guard (200..<400).contains(response.statusCode) else {
            throw NetworkRechargeSafetyError.unavailable
        }
    }

    private func selectNetworkFeeItem() async throws {
        let data = try await request(
            operation: .readAccount,
            method: "POST",
            path: "/charge/feeitem/getThirdData",
            formItems: [
                URLQueryItem(name: "feeitemid", value: "431"),
                URLQueryItem(name: "type", value: "select"),
                URLQueryItem(name: "level", value: "0")
            ]
        )
        guard (try? JSONDecoder().decode(NetworkRechargeStatusEnvelope.self, from: data).code) == 200 else {
            throw NetworkRechargeSafetyError.invalidResponse
        }
    }

    private func request(
        operation: NetworkRechargeOperation,
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        formItems: [URLQueryItem] = []
    ) async throws -> Data {
        try NetworkRechargeRequestPolicy.authorize(operation)
        let (data, response) = try await dataAndResponse(
            method: method,
            path: path,
            queryItems: queryItems,
            formItems: formItems
        )
        guard (200..<300).contains(response.statusCode), !data.isEmpty else {
            throw NetworkRechargeSafetyError.unavailable
        }
        return data
    }

    private func response(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        headerProfile: NetworkRechargeHeaderProfile = .chargeAPI
    ) async throws -> HTTPURLResponse {
        let (_, response) = try await dataAndResponse(
            method: method,
            path: path,
            queryItems: queryItems,
            headerProfile: headerProfile
        )
        return response
    }

    private func dataAndResponse(
        method: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        formItems: [URLQueryItem] = [],
        headerProfile: NetworkRechargeHeaderProfile = .chargeAPI
    ) async throws -> (Data, HTTPURLResponse) {
        var components = URLComponents(
            url: Self.origin.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )
        if !queryItems.isEmpty {
            components?.queryItems = queryItems
        }
        guard let url = components?.url else {
            throw NetworkRechargeSafetyError.disallowedEndpoint
        }

        var request = URLRequest(
            url: url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 15
        )
        request.httpMethod = method
        request.setValue(headerProfile.referer, forHTTPHeaderField: "Referer")
        request.setValue(headerProfile.accept, forHTTPHeaderField: "Accept")
        if let accessToken,
           let authorization = NetworkRechargeSessionCredentials.authorizationHeader(
               accessToken: accessToken
           ) {
            request.setValue(authorization, forHTTPHeaderField: "Synjones-Auth")
        }
        if let cookieHeader = NetworkRechargeSessionCredentials.cookieHeader(
            cookies: sessionCookies,
            for: url
        ) {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        if headerProfile.sendsOrigin {
            request.setValue(Self.origin.absoluteString, forHTTPHeaderField: "Origin")
        }
        request.setValue("no-store", forHTTPHeaderField: "Cache-Control")
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148",
            forHTTPHeaderField: "User-Agent"
        )
        if !formItems.isEmpty {
            var formComponents = URLComponents()
            formComponents.queryItems = formItems
            request.httpBody = formComponents.percentEncodedQuery?.data(using: .utf8)
            request.setValue(
                "application/x-www-form-urlencoded; charset=utf-8",
                forHTTPHeaderField: "Content-Type"
            )
        }
        try NetworkRechargeRequestPolicy.authorize(request)

        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw NetworkRechargeSafetyError.invalidResponse
        }
        captureResponseCookies(response, requestURL: url)
        return (data, response)
    }

    private func captureResponseCookies(
        _ response: HTTPURLResponse,
        requestURL: URL
    ) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            guard let key = item.key as? String else { return }
            result[key] = String(describing: item.value)
        }
        let received = HTTPCookie.cookies(
            withResponseHeaderFields: fields,
            for: response.url ?? requestURL
        )
        for cookie in received {
            let value = CampusCookie(
                name: cookie.name,
                value: cookie.value,
                domain: cookie.domain,
                path: cookie.path,
                secure: cookie.isSecure,
                httpOnly: cookie.properties?[HTTPCookiePropertyKey(rawValue: "HttpOnly")] != nil
            )
            guard CampusCookieWebBridge.isTrustedSchoolCookie(value) else { continue }
            sessionCookies.removeAll {
                $0.name == value.name
                    && $0.domain.caseInsensitiveCompare(value.domain) == .orderedSame
                    && ($0.path ?? "/") == (value.path ?? "/")
            }
            sessionCookies.append(value)
        }
    }
}

struct DemoNetworkRechargeDataSource: NetworkRechargeDataSource {
    enum Mode: Sendable {
        case ready
        case failed
    }

    let mode: Mode

    init(mode: Mode = .ready) {
        self.mode = mode
    }

    func load() async throws -> NetworkRechargeSnapshot {
        try await Task.sleep(for: .milliseconds(120))
        if mode == .failed {
            throw NetworkRechargeSafetyError.unavailable
        }
        return .demo
    }
}

@MainActor
final class NetworkRechargeViewModel: ObservableObject {
    enum State: Equatable {
        case loading
        case ready(NetworkRechargeSnapshot)
        case failed(String)
    }

    @Published private(set) var state: State = .loading
    private let dataSource: any NetworkRechargeDataSource

    init(dataSource: any NetworkRechargeDataSource) {
        self.dataSource = dataSource
    }

    func load() async {
        state = .loading
        do {
            state = .ready(try await dataSource.load())
        } catch is CancellationError {
            return
        } catch let error as NetworkRechargeSafetyError {
            state = .failed(error.localizedDescription)
        } catch let error as CampusCoreError where error == .unauthorized {
            state = .failed("校园卡登录状态已失效，请重新登录后重试")
        } catch {
            state = .failed(NetworkRechargeSafetyError.unavailable.localizedDescription)
        }
    }
}

struct NetworkRechargeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: NetworkRechargeViewModel
    @State private var amount = ""
    @State private var validationMessage: String?
    @State private var showsOfficialPortal = false
    @State private var demoVerificationMessage: String?

    private let demo: Bool

    init(
        appModel: AppModel,
        dataSource: (any NetworkRechargeDataSource)? = nil
    ) {
        let isDemo = AppRuntime.isDemoSession
        demo = isDemo
        let resolvedDataSource: any NetworkRechargeDataSource
        if let dataSource {
            resolvedDataSource = dataSource
        } else if isDemo {
            let mode: DemoNetworkRechargeDataSource.Mode =
                ProcessInfo.processInfo.arguments.contains("--demo-network-recharge-error")
                ? .failed
                : .ready
            resolvedDataSource = DemoNetworkRechargeDataSource(mode: mode)
        } else {
            resolvedDataSource = OfficialNetworkRechargeDataSource(
                campusAPI: appModel.campusAPI
            )
        }
        _model = StateObject(
            wrappedValue: NetworkRechargeViewModel(dataSource: resolvedDataSource)
        )
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "网费充值", large: true)
                        .accessibilityIdentifier("payment.network.screen")

                    switch model.state {
                    case .loading:
                        loadingCard
                    case let .failed(message):
                        errorCard(message)
                    case let .ready(snapshot):
                        accountCard(snapshot)
                        amountCard(snapshot)
                        safetyCard
                        actionButton(snapshot)
                        if let demoVerificationMessage {
                            verificationCard(demoVerificationMessage)
                        }
                    }
                }
                .padding(.bottom, 48)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .task {
            await model.load()
        }
        .sheet(isPresented: $showsOfficialPortal) {
            NetworkRechargeOfficialPortalView(url: OfficialSchoolPaymentPortal.loginURL)
                .ignoresSafeArea()
        }
        .alert("无法继续", isPresented: Binding(
            get: { validationMessage != nil },
            set: { if !$0 { validationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) {
                validationMessage = nil
            }
        } message: {
            Text(validationMessage ?? "")
        }
    }

    private var loadingCard: some View {
        AndroidCard(radius: 24) {
            VStack(spacing: 16) {
                ProgressView()
                Text("正在查询网费账户…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(32)
        }
        .padding(.horizontal, 16)
    }

    private func errorCard(_ message: String) -> some View {
        AndroidCard(radius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Label("查询失败", systemImage: "exclamationmark.triangle")
                    .font(.headline)
                Text(message)
                    .foregroundStyle(.secondary)
                Button("重试") {
                    Task { await model.load() }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("payment.network.retry")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .padding(.horizontal, 16)
    }

    private func accountCard(_ snapshot: NetworkRechargeSnapshot) -> some View {
        AndroidCard(radius: 24) {
            VStack(alignment: .leading, spacing: 0) {
                Text(snapshot.feeName)
                    .font(.title3.bold())
                    .padding(20)
                valueRow(title: "充值账号", value: snapshot.account.nilIfEmpty ?? "--")
                if snapshot.statistics.isEmpty {
                    Text("暂未返回账户统计")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(20)
                } else {
                    ForEach(
                        Array(snapshot.statistics.enumerated()),
                        id: \.offset
                    ) { _, statistic in
                        valueRow(title: statistic.label, value: statistic.value)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("payment.network.account")
    }

    private func amountCard(_ snapshot: NetworkRechargeSnapshot) -> some View {
        AndroidCard(radius: 24) {
            VStack(alignment: .leading, spacing: 16) {
                Text("充值金额")
                    .font(.headline)

                if !snapshot.quickAmounts.isEmpty {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 72), spacing: 12)
                        ],
                        alignment: .leading,
                        spacing: 12
                    ) {
                        ForEach(snapshot.quickAmounts, id: \.self) { quickAmount in
                            Button(quickAmount) {
                                amount = NetworkRechargeAmountParser.inputText(
                                    from: quickAmount
                                )
                                validationMessage = nil
                                demoVerificationMessage = nil
                            }
                            .buttonStyle(.bordered)
                            .accessibilityIdentifier("payment.network.quick-amount")
                        }
                    }
                }

                TextField(amountPrompt(snapshot), text: $amount)
                    .keyboardType(.decimalPad)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("payment.network.amount")
                    .onChange(of: amount) { _, value in
                        amount = sanitizeAmountInput(value)
                        validationMessage = nil
                        demoVerificationMessage = nil
                    }
            }
            .padding(20)
        }
        .padding(.horizontal, 16)
    }

    private var safetyCard: some View {
        AndroidCard(radius: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Label("学校官方支付", systemImage: "checkmark.shield.fill")
                    .font(.headline)
                Text(
                    demo
                    ? "Demo 模式只验证账户、金额、限额和完成状态，不请求真实扣款。"
                    : "账户和统计仅做只读查询。App 不保存校园卡密码，也不在本机生成扣款签名；确认后会进入学校官方 HTTPS 门户。"
                )
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
        }
        .padding(.horizontal, 16)
    }

    private func actionButton(_ snapshot: NetworkRechargeSnapshot) -> some View {
        HStack {
            Spacer()
            Button {
                continueSafely(with: snapshot)
            } label: {
                Label(
                    demo ? "验证充值流程" : "进入学校官方门户",
                    systemImage: demo ? "checkmark.circle" : "safari"
                )
                .fontWeight(.semibold)
                .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("payment.network.continue")
        }
        .padding(.horizontal, 16)
    }

    private func verificationCard(_ message: String) -> some View {
        AndroidCard(radius: 20, background: AndroidParityPalette.success.opacity(0.16)) {
            Label(message, systemImage: "checkmark.circle.fill")
                .foregroundStyle(AndroidParityPalette.success)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(20)
        }
        .padding(.horizontal, 16)
        .accessibilityIdentifier("payment.network.demo-success")
    }

    private func valueRow(title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Text(title)
                .font(.headline)
            Spacer(minLength: 12)
            Text(value.nilIfEmpty ?? "--")
                .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                .multilineTextAlignment(.trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func amountPrompt(_ snapshot: NetworkRechargeSnapshot) -> String {
        guard let maximum = snapshot.maximumAmount else {
            return "请输入金额"
        }
        return "请输入金额，单次最高 \(NetworkRechargeAmountParser.displayText(for: maximum)) 元"
    }

    private func sanitizeAmountInput(_ value: String) -> String {
        let allowed = value.filter { $0.isNumber || $0 == "." }
        guard let decimalIndex = allowed.firstIndex(of: ".") else {
            return allowed
        }
        let integer = allowed[..<decimalIndex]
        let fraction = allowed[allowed.index(after: decimalIndex)...]
            .filter(\.isNumber)
            .prefix(2)
        return "\(integer).\(String(fraction))"
    }

    private func continueSafely(with snapshot: NetworkRechargeSnapshot) {
        do {
            let validated = try NetworkRechargeAmount(
                amount,
                maximum: snapshot.maximumAmount
            )
            if demo {
                demoVerificationMessage = "Demo 验证完成：\(validated.text) 元，未发起任何扣款"
            } else {
                try NetworkRechargeRequestPolicy.authorize(.nativeDebit)
            }
        } catch NetworkRechargeSafetyError.nativeDebitDisabled {
            // Production never executes a native debit. A user gesture opens
            // the official school portal, where the amount must be confirmed
            // again before any payment can occur.
            showsOfficialPortal = true
        } catch {
            validationMessage = error.localizedDescription
        }
    }
}

private struct NetworkRechargeOfficialPortalView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let configuration = SFSafariViewController.Configuration()
        configuration.entersReaderIfAvailable = false
        configuration.barCollapsingEnabled = true
        return SFSafariViewController(url: url, configuration: configuration)
    }

    func updateUIViewController(
        _ controller: SFSafariViewController,
        context: Context
    ) { }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
