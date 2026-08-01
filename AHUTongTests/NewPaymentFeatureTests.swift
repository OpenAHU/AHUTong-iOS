import Foundation
import WebKit
import XCTest
@testable import AHUTong

final class CMBRechargeSecurityTests: XCTestCase {
    func testEntryURLUsesSchoolHTTPSAndCMBAppID() throws {
        let token = "temporary token+/="
        let url = try CMBRechargeSecurityPolicy.makeEntryURL(accessToken: token)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )
        let query = Dictionary(
            uniqueKeysWithValues: try XCTUnwrap(components.queryItems).map {
                ($0.name, $0.value)
            }
        )

        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "ycard.ahu.edu.cn")
        XCTAssertEqual(url.path, "/berserker-base/redirect")
        XCTAssertEqual(query["appId"]!, "253")
        XCTAssertEqual(query["synjones-auth"]!, token)
        XCTAssertEqual(query["type"]!, "app")
    }

    func testSchoolAllowlistRejectsSuffixConfusionAndPlainHTTP() throws {
        XCTAssertTrue(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn/charge-app/"))
        ))
        XCTAssertTrue(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://epay92.ahu.edu.cn/"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://pay.ahu.edu.cn/"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://ahu.edu.cn.attacker.example/"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "https://evilahu.edu.cn/"))
        ))
        XCTAssertFalse(CMBRechargeSecurityPolicy.isAllowedSchoolURL(
            try XCTUnwrap(URL(string: "http://ycard.ahu.edu.cn/"))
        ))
    }

    func testOnlyKnownCMBHandoffsPreserveBankParametersAndBlockCampusToken() throws {
        let appURL = try XCTUnwrap(URL(
            string: "cmbmobilebank://pay?order=123&token=bank-session#confirm"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: appURL),
            .openExternal(appURL)
        )

        let webURL = try XCTUnwrap(URL(
            string: "https://pay.cmbchina.com/checkout?order=123&token=bank-session#confirm"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: webURL),
            .openExternal(webURL)
        )

        let leakingURL = try XCTUnwrap(URL(
            string: "cmbmobilebank://pay?order=123&synjones-auth=campus-secret"
        ))
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(for: leakingURL),
            .block
        )
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(
                for: try XCTUnwrap(URL(string: "https://pay.example.com/checkout?order=123"))
            ),
            .block
        )
        XCTAssertEqual(
            CMBRechargeSecurityPolicy.navigationDecision(
                for: try XCTUnwrap(URL(string: "unknownbank://pay?order=123"))
            ),
            .block
        )
    }

    @MainActor
    func testWebConfigurationAndCredentialPolicyAreNonPersistent() {
        let configuration = CMBRechargeWebConfigurationFactory.make()

        XCTAssertEqual(
            CMBRechargeWebConfigurationFactory.credentialPersistence,
            .memoryOnly
        )
        XCTAssertFalse(
            configuration.websiteDataStore === WKWebsiteDataStore.default()
        )
        XCTAssertTrue(
            configuration.userContentController.userScripts.isEmpty
        )
    }

    func testCookieBridgePreservesTrustedCrossPathAndCrossSubdomainCookies() throws {
        let cookies = [
            CampusCookie(
                name: "YCardSession",
                value: "temporary",
                domain: ".ahu.edu.cn",
                path: "/",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "ChargePath",
                value: "cross-path",
                domain: "ycard.ahu.edu.cn",
                path: "/charge-app",
                secure: true,
                httpOnly: false
            ),
            CampusCookie(
                name: "CashierSubdomain",
                value: "cross-subdomain",
                domain: ".cashier.ahu.edu.cn",
                path: "/cashier-mobile",
                secure: true,
                httpOnly: false
            ),
            CampusCookie(
                name: "Untrusted",
                value: "ignore",
                domain: "ahu.edu.cn.attacker.example",
                path: "/",
                secure: true,
                httpOnly: false
            )
        ]

        let bridged = CampusCookieWebBridge.httpCookies(cookies)

        XCTAssertEqual(
            bridged.map(\.name),
            ["YCardSession", "ChargePath", "CashierSubdomain"]
        )
        XCTAssertEqual(bridged.first?.value, "temporary")
        XCTAssertTrue(bridged.first?.isSecure == true)
        XCTAssertEqual(bridged[1].domain, "ycard.ahu.edu.cn")
        XCTAssertEqual(bridged[1].path, "/charge-app")
        XCTAssertEqual(
            bridged[2].domain.trimmingCharacters(
                in: CharacterSet(charactersIn: ".")
            ),
            "cashier.ahu.edu.cn"
        )
        XCTAssertEqual(bridged[2].path, "/cashier-mobile")
    }

    func testAndroidCMBStyleScriptOnlyTargetsSchoolChargePages() throws {
        XCTAssertTrue(CMBRechargeWebStyle.script.contains("ahutong-cmb-style"))
        XCTAssertTrue(CMBRechargeWebStyle.script.contains(".weui-btn_primary"))
        XCTAssertTrue(CMBRechargeWebStyle.script.contains(".van-button--primary"))
        XCTAssertTrue(CMBRechargeWebStyle.shouldInject(
            for: try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn/cashier-mobile/charge"))
        ))
        XCTAssertTrue(CMBRechargeWebStyle.shouldInject(
            for: try XCTUnwrap(URL(string: "https://epay92.ahu.edu.cn/charge-app/index"))
        ))
        XCTAssertFalse(CMBRechargeWebStyle.shouldInject(
            for: try XCTUnwrap(URL(string: "https://epay92.ahu.edu.cn/fake/charge-app-result"))
        ))
        XCTAssertFalse(CMBRechargeWebStyle.shouldInject(
            for: try XCTUnwrap(URL(string: "https://ycard.ahu.edu.cn/berserker-base/redirect"))
        ))
        XCTAssertFalse(CMBRechargeWebStyle.shouldInject(
            for: try XCTUnwrap(URL(string: "https://attacker.example/charge-app"))
        ))
        XCTAssertFalse(CMBRechargeWebStyle.shouldInject(
            for: try XCTUnwrap(URL(string: "http://ycard.ahu.edu.cn/charge-app"))
        ))
    }
}

final class NetworkRechargeModelTests: XCTestCase {
    func testSessionCredentialsUseBearerAndOnlyTrustedMatchingCookiesInMemory() throws {
        let target = try XCTUnwrap(URL(
            string: "https://ycard.ahu.edu.cn/charge/feeitem/toAppitem"
        ))
        let cookies = [
            CampusCookie(
                name: "ROOT",
                value: "school",
                domain: ".ahu.edu.cn",
                path: "/",
                secure: true,
                httpOnly: true
            ),
            CampusCookie(
                name: "OTHER_PATH",
                value: "skip",
                domain: "ycard.ahu.edu.cn",
                path: "/unrelated",
                secure: true,
                httpOnly: false
            ),
            CampusCookie(
                name: "ATTACKER",
                value: "skip",
                domain: "ahu.edu.cn.attacker.example",
                path: "/",
                secure: true,
                httpOnly: false
            )
        ]

        XCTAssertEqual(
            NetworkRechargeSessionCredentials.authorizationHeader(
                accessToken: " temporary-token "
            ),
            "bearer temporary-token"
        )
        XCTAssertEqual(
            NetworkRechargeSessionCredentials.cookieHeader(
                cookies: cookies,
                for: target
            ),
            "ROOT=school"
        )
        XCTAssertEqual(
            NetworkRechargeRequestPolicy.credentialPersistence,
            .memoryOnly
        )
    }

    func testEntryWarmUpAndChargeAPIUseAndroidHeaderProfiles() {
        XCTAssertEqual(
            NetworkRechargeHeaderProfile.entry.referer,
            "https://ycard.ahu.edu.cn/plat/dating?index=1"
        )
        XCTAssertEqual(
            NetworkRechargeHeaderProfile.entry.accept,
            "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
        )
        XCTAssertFalse(NetworkRechargeHeaderProfile.entry.sendsOrigin)
        XCTAssertEqual(
            NetworkRechargeHeaderProfile.chargeAPI.referer,
            "https://ycard.ahu.edu.cn/charge-app/"
        )
        XCTAssertTrue(NetworkRechargeHeaderProfile.chargeAPI.sendsOrigin)
    }

    func testDecodesAccountStatisticsQuickAmountsAndLimit() throws {
        let configuration = Data(#"""
        {
          "code": 200,
          "feeitem": {
            "name": "校园网充值",
            "layout": "10 元, 20 元,50.00 元",
            "maxmoney": "200",
            "daymaxmoney": "300",
            "billing_unit": "元"
          }
        }
        """#.utf8)
        let account = Data(#"""
        {
          "code": 200,
          "map": {
            "showData": {
              "本期已使用流量": "48.6 GB",
              "储值余额": "32.80 元",
              "用户状态": "正常",
              "自定义统计": "保留"
            },
            "data": {
              "account": "AB220001",
              "balance": "32.80",
              "state_memo": "正常",
              "nested": { "preserved": true }
            }
          }
        }
        """#.utf8)

        let snapshot = try NetworkRechargeDecoder.decode(
            configurationData: configuration,
            accountData: account
        )

        XCTAssertEqual(snapshot.feeName, "校园网充值")
        XCTAssertEqual(snapshot.account, "AB220001")
        XCTAssertEqual(snapshot.quickAmounts, ["10 元", "20 元", "50.00 元"])
        XCTAssertEqual(snapshot.maximumAmount, Decimal(200))
        XCTAssertEqual(snapshot.billingUnit, "元")
        XCTAssertEqual(
            snapshot.statistics.map { $0.label },
            ["用户状态", "储值余额", "本期已使用流量", "自定义统计"]
        )
        let contextData = try XCTUnwrap(snapshot.thirdPartyJSON)
        let context = try XCTUnwrap(
            JSONSerialization.jsonObject(with: contextData) as? [String: Any]
        )
        XCTAssertEqual(context["account"] as? String, "AB220001")
        XCTAssertEqual(context["balance"] as? String, "32.80")
        XCTAssertNil(context["nested"])
        XCTAssertEqual(
            Set(context.keys),
            ["state_memo", "balance", "account"]
        )
    }

    func testAmountValidationEnforcesFormatPositiveValueAndServerLimit() throws {
        XCTAssertEqual(
            try NetworkRechargeAmount("12.30", maximum: 200).text,
            "12.30"
        )
        XCTAssertThrowsError(
            try NetworkRechargeAmount("", maximum: 200)
        ) { error in
            XCTAssertEqual(error as? NetworkRechargeAmountError, .missing)
        }
        XCTAssertThrowsError(
            try NetworkRechargeAmount("1.234", maximum: 200)
        ) { error in
            XCTAssertEqual(
                error as? NetworkRechargeAmountError,
                .tooManyFractionDigits
            )
        }
        XCTAssertThrowsError(
            try NetworkRechargeAmount("200.01", maximum: 200)
        ) { error in
            XCTAssertEqual(
                error as? NetworkRechargeAmountError,
                .exceedsLimit(200)
            )
        }
        XCTAssertThrowsError(
            try NetworkRechargeAmount("501", maximum: nil)
        )
        XCTAssertEqual(
            NetworkRechargeAmountParser.inputText(from: "50.00 元"),
            "50"
        )
    }

    func testReadPolicyBlocksMutationEndpoints() throws {
        let allowed = try XCTUnwrap(URL(
            string: "https://ycard.ahu.edu.cn/charge/feeitem/getThirdData"
        ))
        var readRequest = URLRequest(url: allowed)
        readRequest.httpMethod = "POST"
        XCTAssertNoThrow(try NetworkRechargeRequestPolicy.authorize(readRequest))

        let mutation = try XCTUnwrap(URL(
            string: "https://ycard.ahu.edu.cn/blade-pay/pay"
        ))
        var mutationRequest = URLRequest(url: mutation)
        mutationRequest.httpMethod = "POST"
        XCTAssertThrowsError(
            try NetworkRechargeRequestPolicy.authorize(mutationRequest)
        )
    }

    func testDemoFixtureCoversCompleteReadyStateWithoutProductionAccount() async throws {
        let snapshot = try await DemoNetworkRechargeDataSource().load()

        XCTAssertTrue(snapshot.account.hasPrefix("DEMO-"))
        XCTAssertFalse(snapshot.statistics.isEmpty)
        XCTAssertFalse(snapshot.quickAmounts.isEmpty)
        XCTAssertNotNil(snapshot.maximumAmount)
        XCTAssertNoThrow(
            try NetworkRechargeAmount(
                NetworkRechargeAmountParser.inputText(
                    from: try XCTUnwrap(snapshot.quickAmounts.first)
                ),
                maximum: snapshot.maximumAmount
            )
        )
    }

    func testOfficialDataSourceDisablesAutomaticCookieCredentialAndCacheStores() {
        let configuration = OfficialNetworkRechargeDataSource.makeConfiguration()

        XCTAssertFalse(configuration.httpShouldSetCookies)
        XCTAssertNil(configuration.httpCookieStorage)
        XCTAssertEqual(configuration.httpCookieAcceptPolicy, .never)
        XCTAssertNil(configuration.urlCredentialStorage)
        XCTAssertNil(configuration.urlCache)
        XCTAssertEqual(
            configuration.requestCachePolicy,
            .reloadIgnoringLocalAndRemoteCacheData
        )
    }

    func testStrictServerFormDecoderReadsURLProtocolBodyStream() throws {
        var request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://fixture.invalid/form"))
        )
        request.httpMethod = "POST"
        request.httpBodyStream = InputStream(
            data: Data("fixture=value".utf8)
        )

        let values = try StrictServerFormTestDecoder.values(request)

        XCTAssertTrue(values.count == 1 && values["fixture"] == "value")
    }

    func testConcurrentOfficialLoadsShareOneCredentialScopeAndOneRequestChain() async throws {
        let capture = NetworkRechargeTestLockedBox(
            NetworkRechargeRequestCapture()
        )
        NetworkRechargeTestURLProtocol.handler = { request in
            let decodedForm = try? StrictServerFormTestDecoder.values(request)
            let index = capture.withValue { value in
                value.requestCount += 1
                value.synjonesAuthHeaders.append(
                    request.value(forHTTPHeaderField: "Synjones-Auth")
                )
                value.cookieHeaders.append(
                    request.value(forHTTPHeaderField: "Cookie")
                )
                value.requestSteps.append(
                    "\(request.httpMethod ?? "") \(request.url?.path ?? "")"
                )
                if request.httpMethod == "POST" {
                    let expectedType = value.requestCount == 2 ? "select" : "IEC"
                    value.formSemantics.append(
                        decodedForm?["feeitemid"] == "431"
                            && decodedForm?["type"] == expectedType
                            && decodedForm?["level"] == "0"
                            && decodedForm?.count == 3
                    )
                }
                return value.requestCount
            }
            if index == 1 {
                Thread.sleep(forTimeInterval: 0.05)
            }
            guard let url = request.url,
                  let response = HTTPURLResponse(
                    url: url,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                  ) else {
                throw URLError(.badServerResponse)
            }
            return (
                response,
                try NetworkRechargeTestFixtures.responseData(at: index)
            )
        }
        defer { NetworkRechargeTestURLProtocol.handler = nil }

        let configuration = OfficialNetworkRechargeDataSource.makeConfiguration(
            protocolClasses: [NetworkRechargeTestURLProtocol.self]
        )
        let api = NetworkRechargeCampusAPIStub()
        let source = OfficialNetworkRechargeDataSource(
            campusAPI: api,
            configuration: configuration
        )

        async let first: NetworkRechargeSnapshot = source.load()
        async let second: NetworkRechargeSnapshot = source.load()
        let snapshots = try await (first, second)

        XCTAssertEqual(snapshots.0, snapshots.1)
        let tokenRequestCount = await api.tokenRequestCount()
        let cookieRequestCount = await api.cookieRequestCount()
        XCTAssertEqual(tokenRequestCount, 1)
        XCTAssertEqual(cookieRequestCount, 1)
        let captured = capture.value
        XCTAssertEqual(captured.requestCount, 4)
        XCTAssertEqual(
            captured.requestSteps,
            [
                "GET /charge/feeitem/toAppitem",
                "POST /charge/feeitem/getThirdData",
                "GET /charge/feeitem/singleFeeitem",
                "POST /charge/feeitem/getThirdData"
            ]
        )
        XCTAssertEqual(captured.synjonesAuthHeaders.compactMap { $0 }.count, 4)
        XCTAssertEqual(
            Set(captured.synjonesAuthHeaders.compactMap { $0 }).count,
            1
        )
        XCTAssertTrue(captured.cookieHeaders.allSatisfy { $0 == nil })
        XCTAssertTrue(captured.formSemantics == [true, true])
    }

    @MainActor
    func testOlderViewModelLoadCannotOverwriteNewerResult() async {
        let older = NetworkRechargeSnapshot(
            feeName: "older",
            account: "older-account",
            statistics: [],
            quickAmounts: [],
            maximumAmountText: nil,
            billingUnit: nil
        )
        let newer = NetworkRechargeSnapshot(
            feeName: "newer",
            account: "newer-account",
            statistics: [],
            quickAmounts: [],
            maximumAmountText: nil,
            billingUnit: nil
        )
        let source = OutOfOrderNetworkRechargeDataSource(
            older: older,
            newer: newer
        )
        let model = NetworkRechargeViewModel(dataSource: source)

        let first = Task { await model.load() }
        await source.waitUntilFirstLoadStarts()
        let second = Task { await model.load() }
        await second.value
        await source.finishFirstLoad()
        await first.value

        XCTAssertEqual(model.state, .ready(newer))
    }
}

final class PaymentThirdPartyCanonicalizationTests: XCTestCase {
    override func tearDown() {
        PaymentCanonicalizationTestURLProtocol.handler = nil
        super.tearDown()
    }

    func testBathroomDecoderToCreateOrderUsesAndroidCanonicalFieldOrderAndNullRules() async throws {
        let lookup = try YCardPaymentDecoder.decodeBathroomAccount(
            PaymentCanonicalizationFixtures.bathroomLookup,
            bathroomName: "fixture-bathroom",
            requestedPhone: "fixture-phone"
        )
        let account = try XCTUnwrap(lookup.account)
        let contextData = try XCTUnwrap(lookup.thirdPartyJSON)
        let contextJSON = try XCTUnwrap(String(data: contextData, encoding: .utf8))
        let observation = NetworkRechargeTestLockedBox(PaymentCanonicalObservation())

        PaymentCanonicalizationTestURLProtocol.handler = { request in
            guard request.url?.path == "/blade-pay/pay" else {
                throw PaymentCanonicalizationTestError.unexpectedRequest
            }
            let form = paymentCanonicalFormValues(request)
            let thirdParty = form["third_party"]
            let payload = paymentCanonicalJSONObject(thirdParty)
            observation.withValue { value in
                value.createRequestCount += 1
                value.canonicalJSONMatches =
                    thirdParty == PaymentCanonicalizationFixtures.bathroomCanonical
                value.payloadFields = Set(payload?.keys.map { $0 } ?? [])
                value.payloadSemanticsMatch =
                    payload?["myCustomInfo"] as? String == "手机号：fixture-phone" &&
                    payload?["message"] == nil &&
                    payload?["unknown"] == nil
                value.formSemanticsMatch =
                    form["paystep"] == "0" &&
                    form["feeitemid"] == "409" &&
                    form.keys.contains("third_party")
            }
            return try paymentCanonicalResponse(
                request,
                json: PaymentCanonicalizationFixtures.orderResponse
            )
        }

        let request = try PaymentRequest(
            feature: .bathroom,
            method: .campusAccount,
            amount: PaymentAmount("10"),
            accountID: account.id,
            accountLabel: account.name,
            context: .bathroom(feeItemID: "409", thirdPartyJSON: contextJSON)
        )
        _ = try await makePaymentCanonicalizationGateway().createOrder(
            request: request,
            idempotencyKey: "canonical-bathroom"
        )

        let captured = observation.value
        XCTAssertEqual(captured.createRequestCount, 1)
        XCTAssertTrue(captured.canonicalJSONMatches)
        XCTAssertTrue(captured.formSemanticsMatch)
        XCTAssertTrue(captured.payloadSemanticsMatch)
        XCTAssertEqual(
            captured.payloadFields,
            PaymentCanonicalizationFixtures.bathroomFields
        )
    }

    func testElectricityDecoderToCreateOrderUsesAndroidPaymentDataDefaultsAndOrder() async throws {
        let lookup = try YCardPaymentDecoder.decodeElectricityRoomLookup(
            PaymentCanonicalizationFixtures.electricityLookup,
            campus: YCardSelectionOption(name: "fixture-campus", value: "campus-code"),
            building: YCardSelectionOption(name: "fixture-building", value: "building-code"),
            floor: YCardSelectionOption(name: "fixture-floor", value: "floor-code"),
            room: YCardSelectionOption(name: "fixture-room", value: "room-code")
        )
        let contextData = try XCTUnwrap(lookup.thirdPartyJSON)
        let contextJSON = try XCTUnwrap(String(data: contextData, encoding: .utf8))
        let observation = NetworkRechargeTestLockedBox(PaymentCanonicalObservation())

        PaymentCanonicalizationTestURLProtocol.handler = { request in
            guard request.url?.path == "/blade-pay/pay" else {
                throw PaymentCanonicalizationTestError.unexpectedRequest
            }
            let form = paymentCanonicalFormValues(request)
            let thirdParty = form["third_party"]
            let payload = paymentCanonicalJSONObject(thirdParty)
            observation.withValue { value in
                value.createRequestCount += 1
                value.canonicalJSONMatches =
                    thirdParty == PaymentCanonicalizationFixtures.electricityCanonical
                value.payloadFields = Set(payload?.keys.map { $0 } ?? [])
                value.payloadSemanticsMatch =
                    payload?["extdata"] as? String == "" &&
                    payload?["floorName"] as? String == "" &&
                    payload?["floor"] as? String == "" &&
                    payload?["aid"] as? String == "" &&
                    payload?["myCustomInfo"] as? String ==
                        "房间：fixture-campus fixture-building null fixture-room" &&
                    payload?["unknown"] == nil
                value.formSemanticsMatch =
                    form["paystep"] == "0" &&
                    form["feeitemid"] == "488" &&
                    form.keys.contains("third_party")
            }
            return try paymentCanonicalResponse(
                request,
                json: PaymentCanonicalizationFixtures.orderResponse
            )
        }

        let request = try PaymentRequest(
            feature: .electricity,
            method: .campusAccount,
            amount: PaymentAmount("10"),
            accountID: lookup.room.id,
            accountLabel: lookup.room.label,
            context: .electricity(thirdPartyJSON: contextJSON)
        )
        _ = try await makePaymentCanonicalizationGateway().createOrder(
            request: request,
            idempotencyKey: "canonical-electricity"
        )

        let captured = observation.value
        XCTAssertEqual(captured.createRequestCount, 1)
        XCTAssertTrue(captured.canonicalJSONMatches)
        XCTAssertTrue(captured.formSemanticsMatch)
        XCTAssertTrue(captured.payloadSemanticsMatch)
        XCTAssertEqual(
            captured.payloadFields,
            PaymentCanonicalizationFixtures.electricityFields
        )
    }

    func testNetworkDecoderToCreateOrderUsesAndroidTenFieldNullOmissionAndOrder() async throws {
        let snapshot = try NetworkRechargeDecoder.decode(
            configurationData: PaymentCanonicalizationFixtures.networkConfiguration,
            accountData: PaymentCanonicalizationFixtures.networkAccount
        )
        let contextData = try XCTUnwrap(snapshot.thirdPartyJSON)
        let contextJSON = try XCTUnwrap(String(data: contextData, encoding: .utf8))
        let observation = NetworkRechargeTestLockedBox(PaymentCanonicalObservation())

        PaymentCanonicalizationTestURLProtocol.handler = { request in
            let path = request.url?.path
            if path == "/blade-pay/pay" {
                let form = paymentCanonicalFormValues(request)
                let thirdParty = form["third_party"]
                let payload = paymentCanonicalJSONObject(thirdParty)
                observation.withValue { value in
                    value.createRequestCount += 1
                    value.canonicalJSONMatches =
                        thirdParty == PaymentCanonicalizationFixtures.networkCanonical
                    value.payloadFields = Set(payload?.keys.map { $0 } ?? [])
                    value.payloadSemanticsMatch =
                        payload?["start_date"] == nil &&
                        payload?["unknown"] == nil
                    value.formSemanticsMatch =
                        form["paystep"] == "0" &&
                        form["feeitemid"] == "431" &&
                        form.keys.contains("third_party")
                }
                return try paymentCanonicalResponse(
                    request,
                    json: PaymentCanonicalizationFixtures.orderResponse
                )
            }
            switch path {
            case "/charge/feeitem/toAppitem":
                return try paymentCanonicalResponse(request, status: 302)
            case "/charge/feeitem/singleFeeitem":
                return try paymentCanonicalResponse(
                    request,
                    json: PaymentCanonicalizationFixtures.networkConfigurationResponse
                )
            case "/charge/feeitem/getThirdData":
                return try paymentCanonicalResponse(
                    request,
                    json: PaymentCanonicalizationFixtures.networkPreflightResponse
                )
            default:
                throw PaymentCanonicalizationTestError.unexpectedRequest
            }
        }

        let request = try PaymentRequest(
            feature: .networkRecharge,
            method: .campusAccount,
            amount: PaymentAmount("10"),
            accountID: snapshot.account,
            accountLabel: snapshot.feeName,
            context: .networkRecharge(thirdPartyJSON: contextJSON)
        )
        _ = try await makePaymentCanonicalizationGateway().createOrder(
            request: request,
            idempotencyKey: "canonical-network"
        )

        let captured = observation.value
        XCTAssertEqual(captured.createRequestCount, 1)
        XCTAssertTrue(captured.canonicalJSONMatches)
        XCTAssertTrue(captured.formSemanticsMatch)
        XCTAssertTrue(captured.payloadSemanticsMatch)
        XCTAssertEqual(
            captured.payloadFields,
            PaymentCanonicalizationFixtures.networkFields
        )
    }
}

private enum PaymentCanonicalizationFixtures {
    static let bathroomLookup = Data(#"""
    {
      "code": 200,
      "map": {
        "showData": {
          "手机号": "fixture-phone",
          "现金金额（单位：元）": "18.60",
          "赠送金额（单位：元）": "2.00"
        },
        "data": {
          "projectId": 12,
          "projectName": "Fixture <Bath>&",
          "accountId": 456,
          "telPhone": "fixture-phone",
          "identifier": "fixture-identifier",
          "sex": "X",
          "name": "fixture-name",
          "statusId": 1,
          "accountMoney": 1860,
          "accountGivenMoney": 200,
          "alias": "fixture-alias",
          "tags": "fixture-tag",
          "isCard": 1,
          "cardStatusId": 2,
          "isUseCode": 1,
          "cardPhysicalId": "fixture-physical",
          "tsmAbstract": "fixture-abstract",
          "myCustomInfo": "server-value-must-be-replaced",
          "message": null,
          "unknown": "must-be-dropped"
        }
      }
    }
    """#.utf8)

    static let bathroomCanonical =
        #"{"projectId":12,"projectName":"Fixture \u003cBath\u003e\u0026","accountId":456,"telPhone":"fixture-phone","identifier":"fixture-identifier","# +
        #""sex":"X","name":"fixture-name","statusId":1,"accountMoney":1860,"accountGivenMoney":200,"alias":"fixture-alias","tags":"fixture-tag","# +
        #""isCard":1,"cardStatusId":2,"isUseCode":1,"cardPhysicalId":"fixture-physical","tsmAbstract":"fixture-abstract","# +
        #""myCustomInfo":"手机号：fixture-phone"}"#

    static let bathroomFields: Set<String> = [
        "projectId", "projectName", "accountId", "telPhone", "identifier",
        "sex", "name", "statusId", "accountMoney", "accountGivenMoney", "alias",
        "tags", "isCard", "cardStatusId", "isUseCode", "cardPhysicalId",
        "tsmAbstract", "myCustomInfo"
    ]

    static let electricityLookup = Data(#"""
    {
      "code": 200,
      "map": {
        "showData": { "信息": "fixture" },
        "data": {
          "area": "campus-code",
          "buildingName": "fixture-building",
          "areaName": "fixture-campus",
          "extdata": "server-value-must-be-replaced",
          "floorName": null,
          "aid": null,
          "account": "fixture-account",
          "building": "building-code",
          "room": "room-code",
          "roomName": "fixture-room",
          "myCustomInfo": "server-value-must-be-replaced",
          "unknown": "must-be-dropped"
        }
      }
    }
    """#.utf8)

    static let electricityCanonical = [
        #"{"area":"campus-code","buildingName":"fixture-building","areaName":"fixture-campus","extdata":"","#,
        #""floorName":"","floor":"","aid":"","account":"fixture-account","#,
        #""building":"building-code","room":"room-code","roomName":"fixture-room","#,
        #""myCustomInfo":"房间：fixture-campus fixture-building null fixture-room"}"#
    ].joined()

    static let electricityFields: Set<String> = [
        "area", "buildingName", "areaName", "extdata", "floorName", "floor",
        "aid", "account", "building", "room", "roomName", "myCustomInfo"
    ]

    static let networkConfiguration = Data(#"""
    {
      "code": 200,
      "feeitem": {
        "name": "fixture-network",
        "layout": "10,20",
        "maxmoney": "200",
        "billing_unit": "CNY"
      }
    }
    """#.utf8)

    static let networkAccount = Data(#"""
    {
      "code": 200,
      "map": {
        "showData": {},
        "data": {
          "state_time": "fixture-time",
          "state_memo": "fixture-memo",
          "balance": "10.00",
          "use_time": "1",
          "tsmAbstract": "fixture-abstract",
          "use_money": "2",
          "use_flow": "fixture-flow",
          "account": "fixture-account",
          "user_state": "active",
          "start_date": null,
          "unknown": "must-be-dropped"
        }
      }
    }
    """#.utf8)

    static let networkCanonical = [
        #"{"state_time":"fixture-time","state_memo":"fixture-memo","balance":"10.00","use_time":"1","#,
        #""tsmAbstract":"fixture-abstract","use_money":"2","use_flow":"fixture-flow","#,
        #""account":"fixture-account","user_state":"active"}"#
    ].joined()

    static let networkFields: Set<String> = [
        "state_time", "state_memo", "balance", "use_time", "tsmAbstract",
        "use_money", "use_flow", "account", "user_state"
    ]

    static let orderResponse =
        #"{"code":200,"success":true,"data":{"orderid":"fixture-order"},"msg":"ok"}"#
    static let networkConfigurationResponse =
        #"{"code":200,"feeitem":{"name":"fixture"},"msg":"ok"}"#
    static let networkPreflightResponse =
        #"{"code":200,"map":{"showData":{},"data":{"account":"fixture"}},"msg":"ok"}"#
}

private struct PaymentCanonicalObservation: Sendable {
    var createRequestCount = 0
    var canonicalJSONMatches = false
    var formSemanticsMatch = false
    var payloadSemanticsMatch = false
    var payloadFields: Set<String> = []
}

private enum PaymentCanonicalizationTestError: Error {
    case unexpectedRequest
}

private func makePaymentCanonicalizationGateway() -> YCardProductionPaymentGateway {
    YCardProductionPaymentGateway(
        campusAPI: NetworkRechargeCampusAPIStub(),
        configuration: YCardProductionPaymentClient.makeConfiguration(
            protocolClasses: [PaymentCanonicalizationTestURLProtocol.self]
        ),
        mockTransportEnabled: true,
        signer: YCardProductionPaymentSigner(
            clock: { Date(timeIntervalSince1970: 1_767_326_645) },
            nonce: { "abc123def45" },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    )
}

private func paymentCanonicalFormValues(_ request: URLRequest) -> [String: String] {
    (try? StrictServerFormTestDecoder.values(request)) ?? [:]
}

private func paymentCanonicalJSONObject(_ rawValue: String?) -> [String: Any]? {
    guard let rawValue,
          let data = rawValue.data(using: .utf8) else {
        return nil
    }
    return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
}

private func paymentCanonicalResponse(
    _ request: URLRequest,
    status: Int = 200,
    json: String? = nil
) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: json == nil ? nil : ["Content-Type": "application/json"]
          ) else {
        throw PaymentCanonicalizationTestError.unexpectedRequest
    }
    return (response, json.map { Data($0.utf8) } ?? Data())
}

private final class PaymentCanonicalizationTestURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerBox = NetworkRechargeTestLockedBox<Handler?>(nil)

    static var handler: Handler? {
        get { handlerBox.value }
        set { handlerBox.set(newValue) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw PaymentCanonicalizationTestError.unexpectedRequest
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

private enum NetworkRechargeTestFixtures {
    static let selection = Data(#"{"code":200}"#.utf8)
    static let configuration = Data(#"""
    {
      "code": 200,
      "feeitem": {
        "name": "Test network recharge",
        "layout": "10,20",
        "maxmoney": "200",
        "daymaxmoney": "300",
        "billing_unit": "CNY"
      }
    }
    """#.utf8)
    static let account = Data(#"""
    {
      "code": 200,
      "map": {
        "showData": { "status": "ready" },
        "data": { "account": "TEST-NETWORK-ACCOUNT" }
      }
    }
    """#.utf8)

    static func responseData(at index: Int) throws -> Data {
        switch index {
        case 1: Data()
        case 2: selection
        case 3: configuration
        case 4: account
        default: throw URLError(.badServerResponse)
        }
    }
}

private struct NetworkRechargeRequestCapture: Sendable {
    var requestCount = 0
    var synjonesAuthHeaders: [String?] = []
    var cookieHeaders: [String?] = []
    var requestSteps: [String] = []
    var formSemantics: [Bool] = []
}

private final class NetworkRechargeTestURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerBox = NetworkRechargeTestLockedBox<Handler?>(nil)

    static var handler: Handler? {
        get { handlerBox.value }
        set { handlerBox.set(newValue) }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.cannotLoadFromNetwork)
            }
            let (response, data) = try handler(request)
            client?.urlProtocol(
                self,
                didReceive: response,
                cacheStoragePolicy: .notAllowed
            )
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() { }
}

private final class NetworkRechargeTestLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.withLock { storedValue }
    }

    func set(_ value: Value) {
        lock.withLock { storedValue = value }
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.withLock { body(&storedValue) }
    }
}

private actor NetworkRechargeCampusAPIStub: CampusCoreAPI {
    private var tokenRequests = 0
    private var cookieRequests = 0

    func initialize(cookiesJSON: String) { }
    func login(studentID: String, password: String) throws -> User {
        throw CampusCoreError.invalidResponse
    }
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String {
        cookieRequests += 1
        return "[]"
    }
    func schedule() throws -> [Course] { throw CampusCoreError.invalidResponse }
    func currentWeek() throws -> Int { throw CampusCoreError.invalidResponse }
    func exams() throws -> [CampusExam] { throw CampusCoreError.invalidResponse }
    func grades() throws -> CampusGradeReport { throw CampusCoreError.invalidResponse }
    func cardBalance() throws -> Double { throw CampusCoreError.invalidResponse }
    func cardQRCode() throws -> String { throw CampusCoreError.invalidResponse }
    func cardAccessToken() -> String {
        tokenRequests += 1
        return "network-test-access-token"
    }

    func tokenRequestCount() -> Int { tokenRequests }
    func cookieRequestCount() -> Int { cookieRequests }
}

private actor OutOfOrderNetworkRechargeDataSource: NetworkRechargeDataSource {
    private let older: NetworkRechargeSnapshot
    private let newer: NetworkRechargeSnapshot
    private var loadCount = 0
    private var firstLoadStarted = false
    private var firstLoadWaiters: [CheckedContinuation<Void, Never>] = []
    private var firstLoadContinuation:
        CheckedContinuation<NetworkRechargeSnapshot, Error>?

    init(older: NetworkRechargeSnapshot, newer: NetworkRechargeSnapshot) {
        self.older = older
        self.newer = newer
    }

    func load() async throws -> NetworkRechargeSnapshot {
        loadCount += 1
        if loadCount == 1 {
            firstLoadStarted = true
            let waiters = firstLoadWaiters
            firstLoadWaiters.removeAll()
            waiters.forEach { $0.resume() }
            return try await withCheckedThrowingContinuation { continuation in
                firstLoadContinuation = continuation
            }
        }
        return newer
    }

    func waitUntilFirstLoadStarts() async {
        guard !firstLoadStarted else { return }
        await withCheckedContinuation { continuation in
            firstLoadWaiters.append(continuation)
        }
    }

    func finishFirstLoad() {
        firstLoadContinuation?.resume(returning: older)
        firstLoadContinuation = nil
    }
}
