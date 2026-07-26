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
            try XCTUnwrap(URL(string: "https://ahu.edu.cn/"))
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
            for: try XCTUnwrap(URL(string: "https://pay.ahu.edu.cn/charge-app/index"))
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
              "account": "AB220001"
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

    func testReadOnlyPolicyBlocksNativeDebitAndMutationEndpoints() throws {
        XCTAssertFalse(NetworkRechargeRequestPolicy.nativeDebitEnabled)
        XCTAssertThrowsError(
            try NetworkRechargeRequestPolicy.authorize(.nativeDebit)
        ) { error in
            XCTAssertEqual(
                error as? NetworkRechargeSafetyError,
                .nativeDebitDisabled
            )
        }

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
}
