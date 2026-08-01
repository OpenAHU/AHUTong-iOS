import Foundation
import XCTest
@testable import AHUTong

final class YCardFormURLEncodingTests: XCTestCase {
    func testOkHttp51FixedBytesAndIndependentServerRoundTrip() throws {
        let name = "key +"
        let value = "a+b c%d&e=f~中文"
        let encoded = YCardFormURLEncoder.data([(name: name, value: value)])
        let expected = Data(
            "key+%2B=a%2Bb+c%25d%26e%3Df%7E%E4%B8%AD%E6%96%87".utf8
        )

        XCTAssertTrue(encoded == expected)
        let decoded = try StrictServerFormTestDecoder.values(encoded)
        XCTAssertTrue(decoded == [name: value])
    }

    func testIndependentServerDecoderReadsURLLoadingBodyStream() throws {
        let expected = ["field": "value with + marker"]
        let encoded = YCardFormURLEncoder.data(
            expected.map { (name: $0.key, value: $0.value) }
        )
        var request = URLRequest(
            url: try XCTUnwrap(URL(string: "https://example.invalid/form"))
        )
        request.httpBodyStream = InputStream(data: encoded)

        XCTAssertTrue(
            try StrictServerFormTestDecoder.values(request) == expected
        )
    }

    func testProductionServerDecoderRejectsMalformedOrAmbiguousForms() {
        for body in [
            Data("a".utf8),
            Data("a=%".utf8),
            Data("a=%0G".utf8),
            Data("a=%FF".utf8),
            Data("a=1&%61=2".utf8)
        ] {
            XCTAssertThrowsError(try YCardServerFormDecoder.values(body))
        }
    }
}

final class YCardProductionPaymentSigningTests: XCTestCase {
    private let fixedDate = Date(timeIntervalSince1970: 1_767_326_645)
    private let fixedNonce = "abc123def45"

    func testProductionMaterialMatchesAuditedAndroidReferenceAsBooleanOnly() {
        XCTAssertTrue(YCardProductionPaymentSigner.verifyProductionConstantFingerprints())
        XCTAssertTrue(YCardSecureKeyboardMapper.verifyProductionConstantFingerprints())
    }

    func testCardCreateUsesExactFieldsAndAndroidFixedVector() throws {
        let form = try signer().cardCreate(amount: "12.34", cardType: "01")
        XCTAssertEqual(form.fields.map(\.name), [
            "feeitemid", "appid", "tranamt", "source", "yktcard",
            "synAccessSource", "APP_ID", "TIMESTAMP", "SIGN_TYPE", "NONCE", "SIGN"
        ])
        let values = dictionary(form.fields)
        XCTAssertEqual(values["feeitemid"], "401")
        XCTAssertEqual(values["tranamt"], "12.34")
        XCTAssertEqual(values["source"], "app")
        XCTAssertEqual(values["yktcard"], "01")
        XCTAssertEqual(values["synAccessSource"], "h5")
        XCTAssertTrue(form.signature == "E66B91E667F985C688BF018E93C4FE80861BBD3B80BA011291171A8D99A300FC")
    }

    func testCardBankBodyKeepsSynAccessSourceOutsideAndroidSignature() throws {
        let form = try signer().cardBankSubmit(orderID: "ORDER-FIXED-01")
        XCTAssertEqual(form.fields.map(\.name), [
            "paytypeid", "paytype", "paystep", "orderid", "redirect_url",
            "userAgent", "APP_ID", "TIMESTAMP", "SIGN_TYPE", "NONCE", "SIGN",
            "synAccessSource"
        ])
        var values = dictionary(form.fields)
        XCTAssertEqual(values["paytypeid"], "63")
        XCTAssertEqual(values["paytype"], "BANKCARD")
        XCTAssertEqual(values["paystep"], "2")
        XCTAssertEqual(values["synAccessSource"], "h5")
        XCTAssertTrue(form.signature == "3C6C21D2AC46C75A1C051D53090F761AE07990B341F421B3A4F0D2DEC8C921C3")

        values["synAccessSource"] = "body-only-fixture"
        XCTAssertTrue(YCardProductionPaymentSigner.verifiesCardBankSubmit(values))
    }

    func testGeneralSignerKeepsEmptyBodyFieldButExcludesItFromFixedVector() throws {
        let form = try signer().chargeCreate(
            feeItemID: "488",
            amount: "20.00",
            thirdPartyJSON: #"{"room":"fixture"}"#
        )
        XCTAssertEqual(form.fields.map(\.name), [
            "feeitemid", "tranamt", "flag", "source", "paystep", "abstracts",
            "redirect_url", "third_party", "APP_ID", "TIMESTAMP", "SIGN_TYPE",
            "NONCE", "SIGN"
        ])
        let values = dictionary(form.fields)
        XCTAssertEqual(values["abstracts"], "")
        XCTAssertTrue(YCardProductionPaymentSigner.verifiesGeneralSignedForm(values))
        XCTAssertTrue(form.signature == "6054BB015824347F1FC892E7033BC95C3C06FD7F830FF458C03A4D24057CB0EB")
    }

    func testProductionPolicyRejectsTamperedSignatureAndAdditionalFields() throws {
        let form = try signer().chargeCreate(
            feeItemID: "431",
            amount: "10.00",
            thirdPartyJSON: #"{"account":"fixture"}"#
        )
        let valid = try YCardProductionPaymentClient.makeRequest(
            .networkCreate,
            formFields: form.fields,
            accessToken: "fixture-token",
            cookies: []
        )
        XCTAssertNoThrow(
            try YCardProductionPaymentRequestPolicy.authorize(
                valid,
                operation: .networkCreate
            )
        )

        var fields = form.fields
        let signatureIndex = try XCTUnwrap(fields.firstIndex(where: { $0.name == "SIGN" }))
        fields[signatureIndex] = YCardPaymentFormField("SIGN", String(repeating: "A", count: 64))
        XCTAssertThrowsError(try YCardProductionPaymentClient.makeRequest(
            .networkCreate,
            formFields: fields,
            accessToken: "fixture-token",
            cookies: []
        ))

        XCTAssertThrowsError(try YCardProductionPaymentClient.makeRequest(
            .networkCreate,
            formFields: form.fields + [YCardPaymentFormField("extra", "blocked")],
            accessToken: "fixture-token",
            cookies: []
        ))
    }

    private func signer() -> YCardProductionPaymentSigner {
        let date = fixedDate
        let nonce = fixedNonce
        return YCardProductionPaymentSigner(
            clock: { date },
            nonce: { nonce },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
    }

    private func dictionary(
        _ fields: [YCardPaymentFormField]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues: fields.map { ($0.name, $0.value) })
    }
}

final class YCardSecureKeyboardMapperTests: XCTestCase {
    func testInverseIndexMappingClearsOriginalAuthorization() throws {
        var authorization: [UInt8] = [48, 52, 57, 50, 55, 53]
        let mapped = try YCardSecureKeyboardMapper.map(
            authorization: &authorization,
            permutation: "9081726354"
        )
        let expected: [UInt8] = [49, 57, 48, 53, 52, 56]
        XCTAssertTrue(authorization.isEmpty)
        XCTAssertTrue(mapped == expected)
    }

    func testInvalidPermutationAndAuthorizationFailClosedAndClearInput() {
        for permutation in ["012345678", "0012345678", "012345678x"] {
            var authorization: [UInt8] = [49, 50, 51, 52, 53, 54]
            XCTAssertThrowsError(try YCardSecureKeyboardMapper.map(
                authorization: &authorization,
                permutation: permutation
            ))
            XCTAssertTrue(authorization.isEmpty)
        }

        var malformed: [UInt8] = [49, 50, 51, 52, 53, 120]
        XCTAssertThrowsError(try YCardSecureKeyboardMapper.map(
            authorization: &malformed,
            permutation: "0123456789"
        ))
        XCTAssertTrue(malformed.isEmpty)
    }

    func testDynamicMapRequiresExactlyOneUUIDAndOnePermutation() {
        var authorization: [UInt8] = [49, 50, 51, 52, 53, 54]
        XCTAssertThrowsError(try YCardSecureKeyboardMapper.dynamicPreparation(
            authorization: &authorization,
            passwordMap: [:]
        ))
        XCTAssertTrue(authorization.isEmpty)

        authorization = [49, 50, 51, 52, 53, 54]
        XCTAssertThrowsError(try YCardSecureKeyboardMapper.dynamicPreparation(
            authorization: &authorization,
            passwordMap: [
                String(repeating: "a", count: 32): "0123456789",
                String(repeating: "b", count: 32): "9081726354"
            ]
        ))
        XCTAssertTrue(authorization.isEmpty)
    }
}

final class YCardProductionPaymentRequestPolicyTests: XCTestCase {
    func testEphemeralTransportHasNoPersistentCookieCredentialOrCacheStores() {
        let configuration = YCardProductionPaymentClient.makeConfiguration()
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

    func testExplicitCIDisableFlagBlocksLiveDebitTransport() {
        XCTAssertTrue(YCardProductionPaymentClient.liveDebitIsDisabled(
            environment: ["AHUTONG_CI_DISABLE_LIVE_PAYMENT": "1"],
            arguments: []
        ))
        XCTAssertTrue(YCardProductionPaymentClient.liveDebitIsDisabled(
            environment: ["AHUTONG_CI_DISABLE_LIVE_PAYMENT": "true"],
            arguments: []
        ))
        XCTAssertFalse(YCardProductionPaymentClient.liveDebitIsDisabled(
            environment: [:],
            arguments: []
        ))
    }

    func testBathroomCreateAllowsOnly409And430WithExactAndroidFields() throws {
        for feeItemID in ["409", "430"] {
            let fields = [
                YCardPaymentFormField("feeitemid", feeItemID),
                YCardPaymentFormField("tranamt", "10.00"),
                YCardPaymentFormField("flag", "choose"),
                YCardPaymentFormField("source", "app"),
                YCardPaymentFormField("paystep", "0"),
                YCardPaymentFormField("abstracts", ""),
                YCardPaymentFormField("third_party", #"{"telPhone":"13800000000"}"#)
            ]
            let request = try YCardProductionPaymentClient.makeRequest(
                .bathroomCreate(feeItemID: feeItemID),
                formFields: fields,
                accessToken: "fixture-token",
                cookies: []
            )
            XCTAssertEqual(formFieldNames(request), Set([
                "feeitemid", "tranamt", "flag", "source", "paystep", "abstracts", "third_party"
            ]))
        }

        XCTAssertThrowsError(try YCardProductionPaymentClient.makeRequest(
            .bathroomCreate(feeItemID: "999"),
            formFields: [],
            accessToken: "fixture-token",
            cookies: []
        ))
    }

    func testRequestPolicyRejectsBadEscapesInvalidUTF8AndDecodedDuplicates() throws {
        let valid = try YCardProductionPaymentClient.makeRequest(
            .bathroomCreate(feeItemID: "409"),
            formFields: [
                YCardPaymentFormField("feeitemid", "409"),
                YCardPaymentFormField("tranamt", "10.00"),
                YCardPaymentFormField("flag", "choose"),
                YCardPaymentFormField("source", "app"),
                YCardPaymentFormField("paystep", "0"),
                YCardPaymentFormField("abstracts", ""),
                YCardPaymentFormField("third_party", #"{"fixture":"value"}"#)
            ],
            accessToken: "fixture-token",
            cookies: []
        )
        let suffixes = ["&extra=%", "&extra=%FF", "&%66eeitemid=409"]
        for suffix in suffixes {
            var request = valid
            var body = try XCTUnwrap(valid.httpBody)
            body.append(contentsOf: suffix.utf8)
            request.httpBody = body
            XCTAssertThrowsError(
                try YCardProductionPaymentRequestPolicy.authorize(
                    request,
                    operation: .bathroomCreate(feeItemID: "409")
                )
            )
        }
    }

    func testUnregisteredHostPathMethodAndQueryFailClosed() throws {
        let signer = YCardProductionPaymentSigner(
            clock: { Date(timeIntervalSince1970: 1_767_326_645) },
            nonce: { "abc123def45" },
            timeZone: TimeZone(secondsFromGMT: 0)!
        )
        let form = try signer.cardBankSubmit(orderID: "ORDER-FIXTURE")
        let valid = try YCardProductionPaymentClient.makeRequest(
            .cardBankSubmit,
            formFields: form.fields,
            accessToken: "fixture-token",
            cookies: []
        )

        for rawURL in [
            "https://attacker.example/blade-pay/pay",
            "http://ycard.ahu.edu.cn/blade-pay/pay",
            "https://ycard.ahu.edu.cn/plat/",
            "https://ycard.ahu.edu.cn/blade-pay/pay?extra=blocked"
        ] {
            var request = valid
            request.url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertThrowsError(
                try YCardProductionPaymentRequestPolicy.authorize(
                    request,
                    operation: .cardBankSubmit
                )
            )
        }
    }

    private func formFieldNames(_ request: URLRequest) -> Set<String> {
        guard let values = try? StrictServerFormTestDecoder.values(request) else { return [] }
        return Set(values.keys)
    }
}

final class YCardProductionPaymentGatewayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        YCardProductionTestURLProtocol.reset()
    }

    override func tearDown() {
        YCardProductionTestURLProtocol.reset()
        super.tearDown()
    }

    func testCardAlipayKeepsAllowlistedMiniAppHandoffWithoutSchoolWebPage() async throws {
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try paymentRequest(
                feature: .cardRecharge,
                method: .alipay,
                context: .card(cardType: "01")
            ),
            idempotencyKey: "card-alipay-key"
        )

        XCTAssertEqual(order.externalURL, AlipayCampusCardHandoff.appURL)
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 0)
    }

    func testCardBankCreateSubmitAndBalanceRefresh() async throws {
        let paths = YCardProductionLockedBox<[String]>([])
        YCardProductionTestURLProtocol.handler = { request, index in
            paths.withValue { $0.append(request.url?.path ?? "") }
            switch index {
            case 1:
                return try response(
                    request,
                    status: 302,
                    headers: [
                        "Location": "https://ycard.ahu.edu.cn/payment/?orderid=CARD-ORDER-1&next=1"
                    ]
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            case 3:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"card":[]},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try paymentRequest(
                feature: .cardRecharge,
                method: .bankCard,
                context: .card(cardType: "01")
            ),
            idempotencyKey: "card-key"
        )
        XCTAssertEqual(order.id, "CARD-ORDER-1")
        let prepared = try await gateway.prepareConfirmation(
            orderID: order.id,
            feature: .cardRecharge,
            method: .bankCard,
            authorization: nil
        )
        let status = try await gateway.submitPreparedConfirmation(prepared)
        assertConfirmed(status)
        XCTAssertEqual(paths.value, [
            "/charge/order/thirdOrder",
            "/blade-pay/pay",
            "/berserker-app/ykt/tsm/queryCard"
        ])
    }

    func testBathroom409And430CreateMapSubmitAndRefresh() async throws {
        for (offset, feeItemID) in ["409", "430"].enumerated() {
            YCardProductionTestURLProtocol.reset()
            YCardProductionTestURLProtocol.handler = { request, index in
                switch index {
                case 1:
                    return try response(
                        request,
                        json: "{\"code\":200,\"success\":true,\"data\":{\"orderid\":\"BATH-ORDER-\(offset)\"},\"msg\":\"ok\"}"
                    )
                case 2:
                    return try response(
                        request,
                        json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                    )
                case 3:
                    return try response(
                        request,
                        json: #"{"code":200,"map":{"showData":{},"data":{}},"msg":"ok"}"#
                    )
                default:
                    throw YCardProductionMockError.unexpectedRequest
                }
            }
            let gateway = makeGateway()
            let order = try await gateway.createOrder(
                request: try paymentRequest(
                    feature: .bathroom,
                    method: .campusAccount,
                    context: .bathroom(
                        feeItemID: feeItemID,
                        thirdPartyJSON: #"{"telPhone":"13800000000","accountId":1}"#
                    )
                ),
                idempotencyKey: "bath-key-\(offset)"
            )
            let authorization = try transientAuthorization()
            let prepared = try await gateway.prepareConfirmation(
                orderID: order.id,
                feature: .bathroom,
                method: .campusAccount,
                authorization: authorization
            )
            XCTAssertTrue(authorization.isCleared)
            assertConfirmed(try await gateway.submitPreparedConfirmation(prepared))
            XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 3)
        }
    }

    func testElectricityUsesPerOrderMapThenSubmitsAndRefreshesRoom() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-ORDER-1"},"msg":"ok"}"#
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa":"9081726354"}},"msg":"ok"}"#
                )
            case 3:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            case 4:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{"信息":"fixture"},"data":{}},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try paymentRequest(
                feature: .electricity,
                method: .campusAccount,
                context: .electricity(
                    thirdPartyJSON: #"{"area":"A","building":"B","floor":"F","room":"R"}"#
                )
            ),
            idempotencyKey: "electricity-key"
        )
        let authorization = try transientAuthorization()
        let prepared = try await gateway.prepareConfirmation(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount,
            authorization: authorization
        )
        XCTAssertTrue(authorization.isCleared)
        assertConfirmed(try await gateway.submitPreparedConfirmation(prepared))
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 4)
    }

    func testNetworkRechargeWarmsEntryReadsAccountUsesDynamicMapAndRefreshes() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(request, status: 302)
            case 2:
                return try response(request, json: #"{"code":200,"msg":"ok"}"#)
            case 3:
                return try response(
                    request,
                    json: #"{"code":200,"feeitem":{"name":"fixture"},"msg":"ok"}"#
                )
            case 4, 8:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{"account":"fixture"}},"msg":"ok"}"#
                )
            case 5:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"NET-ORDER-1"},"msg":"ok"}"#
                )
            case 6:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb":"1029384756"}},"msg":"ok"}"#
                )
            case 7:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try paymentRequest(
                feature: .networkRecharge,
                method: .campusAccount,
                context: .networkRecharge(
                    thirdPartyJSON: #"{"account":"fixture","balance":"10.00"}"#
                )
            ),
            idempotencyKey: "network-key"
        )
        let authorization = try transientAuthorization()
        let prepared = try await gateway.prepareConfirmation(
            orderID: order.id,
            feature: .networkRecharge,
            method: .campusAccount,
            authorization: authorization
        )
        XCTAssertTrue(authorization.isCleared)
        assertConfirmed(try await gateway.submitPreparedConfirmation(prepared))
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 8)
    }

    func testNetworkPreflightFailureIsRetryableAndNeverCountsAsUnknownCreate() async throws {
        let createCount = YCardProductionLockedBox(0)
        YCardProductionTestURLProtocol.handler = { request, index in
            if request.url?.path == "/blade-pay/pay",
               formValues(request)["paystep"] == "0" {
                createCount.withValue { $0 += 1 }
            }
            switch index {
            case 1:
                throw URLError(.timedOut)
            case 2:
                return try response(request, status: 302)
            case 3:
                return try response(request, json: #"{"code":200,"msg":"ok"}"#)
            case 4:
                return try response(
                    request,
                    json: #"{"code":200,"feeitem":{"name":"fixture"},"msg":"ok"}"#
                )
            case 5:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{"account":"fixture"}},"msg":"ok"}"#
                )
            case 6:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"NET-RETRY-1"},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let request = try paymentRequest(
            feature: .networkRecharge,
            method: .campusAccount,
            context: .networkRecharge(
                thirdPartyJSON: #"{"account":"fixture","balance":"10.00"}"#
            )
        )

        do {
            _ = try await gateway.createOrder(
                request: request,
                idempotencyKey: "network-preflight-retry-key"
            )
            XCTFail("Expected preflight failure")
        } catch let error as PaymentGatewayError {
            guard case .definitelyRejected(_) = error else {
                return XCTFail("Preflight must be a definite no-create failure")
            }
        }
        XCTAssertEqual(createCount.value, 0)

        let order = try await gateway.createOrder(
            request: request,
            idempotencyKey: "network-preflight-retry-key"
        )
        XCTAssertEqual(order.id, "NET-RETRY-1")
        XCTAssertEqual(createCount.value, 1)
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 6)
    }

    func testNetworkCreateUnauthorizedInvalidatesSessionAndRetryRewarms() async throws {
        let warmUpCount = YCardProductionLockedBox(0)
        let createCount = YCardProductionLockedBox(0)
        YCardProductionTestURLProtocol.handler = { request, index in
            if request.url?.path == "/charge/feeitem/toAppitem" {
                warmUpCount.withValue { $0 += 1 }
            }
            if request.url?.path == "/blade-pay/pay",
               formValues(request)["paystep"] == "0" {
                createCount.withValue { $0 += 1 }
            }
            switch index {
            case 1, 6:
                return try response(request, status: 302)
            case 2, 7:
                return try response(request, json: #"{"code":200,"msg":"ok"}"#)
            case 3, 8:
                return try response(
                    request,
                    json: #"{"code":200,"feeitem":{"name":"fixture"},"msg":"ok"}"#
                )
            case 4, 9:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{"account":"fixture"}},"msg":"ok"}"#
                )
            case 5:
                return try response(request, status: 401)
            case 10:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"NET-REAUTH-1"},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let request = try paymentRequest(
            feature: .networkRecharge,
            method: .campusAccount,
            context: .networkRecharge(
                thirdPartyJSON: #"{"account":"fixture","balance":"10.00"}"#
            )
        )

        do {
            _ = try await gateway.createOrder(
                request: request,
                idempotencyKey: "network-reauth-key"
            )
            XCTFail("Expected authentication rejection")
        } catch let error as PaymentGatewayError {
            guard case .definitelyRejected(_) = error else {
                return XCTFail("Authentication rejection must be definite")
            }
        }

        let order = try await gateway.createOrder(
            request: request,
            idempotencyKey: "network-reauth-key"
        )
        XCTAssertEqual(order.id, "NET-REAUTH-1")
        XCTAssertEqual(warmUpCount.value, 2)
        XCTAssertEqual(createCount.value, 2)
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 10)
    }

    func testBusinessRejectionIsTerminalAndDoesNotRefreshBalance() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-REJECT-1"},"msg":"ok"}"#
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"cccccccccccccccccccccccccccccccc":"0123456789"}},"msg":"ok"}"#
                )
            case 3:
                return try response(
                    request,
                    json: #"{"code":400,"success":false,"data":null,"msg":"rejected"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try electricityRequest(),
            idempotencyKey: "reject-key"
        )
        let prepared = try await gateway.prepareConfirmation(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount,
            authorization: try transientAuthorization()
        )
        let status = try await gateway.submitPreparedConfirmation(prepared)
        guard case .rejected = status else {
            return XCTFail("Expected terminal rejection")
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 3)
    }

    func testFinalTimeoutBecomesUnknownAndStatusRefreshesWithoutReplayingFinal() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-TIMEOUT-1"},"msg":"ok"}"#
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"dddddddddddddddddddddddddddddddd":"9081726354"}},"msg":"ok"}"#
                )
            case 3:
                throw URLError(.timedOut)
            case 4:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{}},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try electricityRequest(),
            idempotencyKey: "timeout-key"
        )
        let prepared = try await gateway.prepareConfirmation(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount,
            authorization: try transientAuthorization()
        )
        var timedOut = false
        do {
            _ = try await gateway.submitPreparedConfirmation(prepared)
        } catch let error as PaymentGatewayError {
            timedOut = error == .timedOut
        }
        XCTAssertTrue(timedOut)
        let status = try await gateway.status(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount
        )
        guard case .unknown = status else {
            return XCTFail("Expected unknown result")
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 4)
    }

    func testCreateTimeoutBlocksSameIdempotencyKeyFromCreatingAgain() async throws {
        YCardProductionTestURLProtocol.handler = { _, index in
            guard index == 1 else { throw YCardProductionMockError.unexpectedRequest }
            throw URLError(.timedOut)
        }
        let gateway = makeGateway()
        let request = try electricityRequest()

        for _ in 0..<2 {
            do {
                _ = try await gateway.createOrder(
                    request: request,
                    idempotencyKey: "create-timeout-key"
                )
                XCTFail("Expected unknown creation result")
            } catch let error as PaymentGatewayError {
                XCTAssertEqual(error, .timedOut)
            }
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 1)
    }

    func testCreateHTTP408IsUnknownAndBlocksSameIdempotencyKey() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            guard index == 1 else { throw YCardProductionMockError.unexpectedRequest }
            return try response(request, status: 408)
        }
        let gateway = makeGateway()
        let request = try electricityRequest()

        for _ in 0..<2 {
            do {
                _ = try await gateway.createOrder(
                    request: request,
                    idempotencyKey: "create-http-408-key"
                )
                XCTFail("Expected unknown creation result")
            } catch let error as PaymentGatewayError {
                XCTAssertEqual(error, .timedOut)
            }
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 1)
    }

    func testFinalHTTP408IsUnknownAndStatusNeverReplaysFinalSubmission() async throws {
        let finalSubmissionCount = YCardProductionLockedBox(0)
        YCardProductionTestURLProtocol.handler = { request, index in
            if formFieldNames(request).contains("password") {
                finalSubmissionCount.withValue { $0 += 1 }
            }
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-HTTP-408-1"},"msg":"ok"}"#
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"abababababababababababababababab":"9081726354"}},"msg":"ok"}"#
                )
            case 3:
                return try response(request, status: 408)
            case 4:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{}},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let order = try await gateway.createOrder(
            request: try electricityRequest(),
            idempotencyKey: "final-http-408-key"
        )
        let prepared = try await gateway.prepareConfirmation(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount,
            authorization: try transientAuthorization()
        )

        do {
            _ = try await gateway.submitPreparedConfirmation(prepared)
            XCTFail("Expected unknown final result")
        } catch let error as PaymentGatewayError {
            XCTAssertEqual(error, .timedOut)
        }
        let status = try await gateway.status(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount
        )
        guard case .unknown = status else {
            return XCTFail("Expected unknown status after HTTP 408")
        }
        XCTAssertEqual(finalSubmissionCount.value, 1)
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 4)
    }

    func testMalformedCreateResponseBlocksSameIdempotencyKeyFromCreatingAgain() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            guard index == 1 else { throw YCardProductionMockError.unexpectedRequest }
            return try response(
                request,
                json: #"{"code":200,"success":true,"data":{},"msg":"accepted"}"#
            )
        }
        let gateway = makeGateway()
        let request = try electricityRequest()

        do {
            _ = try await gateway.createOrder(
                request: request,
                idempotencyKey: "create-malformed-key"
            )
            XCTFail("Expected unknown creation result")
        } catch let error as PaymentGatewayError {
            XCTAssertEqual(error, .invalidResponse)
        }
        do {
            _ = try await gateway.createOrder(
                request: request,
                idempotencyKey: "create-malformed-key"
            )
            XCTFail("Expected duplicate creation to remain blocked")
        } catch let error as PaymentGatewayError {
            XCTAssertEqual(error, .timedOut)
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 1)
    }

    func testExplicitCreateBusinessRejectionDoesNotLockIdempotencyKey() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":400,"success":false,"data":null,"msg":"rejected"}"#
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-AFTER-REJECT-1"},"msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        let request = try electricityRequest()

        do {
            _ = try await gateway.createOrder(
                request: request,
                idempotencyKey: "explicit-create-rejection-key"
            )
            XCTFail("Expected definite business rejection")
        } catch let error as PaymentGatewayError {
            guard case .definitelyRejected(_) = error else {
                return XCTFail("Explicit business rejection must be definite")
            }
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 1)

        let order = try await gateway.createOrder(
            request: request,
            idempotencyKey: "explicit-create-rejection-key"
        )
        XCTAssertEqual(order.id, "ELEC-AFTER-REJECT-1")
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 2)
    }

    func testFreshGatewayResumesSameOrderWithoutCreatingAnotherOrder() async throws {
        let createFlags = YCardProductionLockedBox<[Bool]>([])
        YCardProductionTestURLProtocol.handler = { request, index in
            let names = formFieldNames(request)
            createFlags.withValue { $0.append(names.contains("feeitemid")) }
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-RESTORE-1"},"msg":"ok"}"#
                )
            case 2:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee":"1029384756"}},"msg":"ok"}"#
                )
            case 3:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let firstGateway = makeGateway()
        let order = try await firstGateway.createOrder(
            request: try electricityRequest(),
            idempotencyKey: "restore-key"
        )

        let restoredGateway = makeGateway()
        let prepared = try await restoredGateway.prepareConfirmation(
            orderID: order.id,
            feature: .electricity,
            method: .campusAccount,
            authorization: try transientAuthorization()
        )
        assertConfirmed(
            try await restoredGateway.submitPreparedConfirmation(prepared)
        )
        XCTAssertEqual(order.id, "ELEC-RESTORE-1")
        XCTAssertEqual(createFlags.value.filter { $0 }.count, 1)
    }

    func testFreshGatewayRewarmsNetworkSessionAndResumesSameOrder() async throws {
        let createCount = YCardProductionLockedBox(0)
        YCardProductionTestURLProtocol.handler = { request, index in
            if request.url?.path == "/blade-pay/pay",
               formValues(request)["paystep"] == "0" {
                createCount.withValue { $0 += 1 }
            }
            switch index {
            case 1, 6:
                return try response(request, status: 302)
            case 2, 7:
                return try response(request, json: #"{"code":200,"msg":"ok"}"#)
            case 3, 8:
                return try response(
                    request,
                    json: #"{"code":200,"feeitem":{"name":"fixture"},"msg":"ok"}"#
                )
            case 4, 9:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{"account":"fixture"}},"msg":"ok"}"#
                )
            case 5:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"NET-RESTORE-1"},"msg":"ok"}"#
                )
            case 10:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"ffffffffffffffffffffffffffffffff":"9081726354"}},"msg":"ok"}"#
                )
            case 11:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let request = try paymentRequest(
            feature: .networkRecharge,
            method: .campusAccount,
            context: .networkRecharge(
                thirdPartyJSON: #"{"account":"fixture","balance":"10.00"}"#
            )
        )
        let firstGateway = makeGateway()
        let order = try await firstGateway.createOrder(
            request: request,
            idempotencyKey: "network-restore-key"
        )

        let restoredGateway = makeGateway()
        let prepared = try await restoredGateway.prepareConfirmation(
            orderID: order.id,
            feature: .networkRecharge,
            method: .campusAccount,
            authorization: try transientAuthorization()
        )
        assertConfirmed(
            try await restoredGateway.submitPreparedConfirmation(prepared)
        )
        XCTAssertEqual(order.id, "NET-RESTORE-1")
        XCTAssertEqual(createCount.value, 1)
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 11)
    }

    func testFreshGatewayStatusFailsClosedWithoutReplayingAnyPaymentRequest() async throws {
        let gateway = makeGateway()
        let status = try await gateway.status(
            orderID: "NET-PERSISTED-UNKNOWN-1",
            feature: .networkRecharge,
            method: .campusAccount
        )

        guard case .unknown = status else {
            return XCTFail("A fresh gateway must fail closed for status-only recovery")
        }
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 0)
    }

    func testSameIdempotencyKeyReturnsExistingOrderWithoutSecondCreate() async throws {
        YCardProductionTestURLProtocol.handler = { request, index in
            guard index == 1 else { throw YCardProductionMockError.unexpectedRequest }
            return try response(
                request,
                json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-IDEMPOTENT-1"},"msg":"ok"}"#
            )
        }
        let gateway = makeGateway()
        let request = try electricityRequest()
        let first = try await gateway.createOrder(
            request: request,
            idempotencyKey: "same-key"
        )
        let second = try await gateway.createOrder(
            request: request,
            idempotencyKey: "same-key"
        )
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 1)
    }

    func testEachElectricityOrderUsesItsOwnFreshPasswordMapAndUUID() async throws {
        let keyboardOrderBindings = YCardProductionLockedBox<[Bool]>([])
        let finalMaterialBindings = YCardProductionLockedBox<[Bool]>([])
        let firstUUID = String(repeating: "1", count: 32)
        let secondUUID = String(repeating: "2", count: 32)
        let firstExpected = String(decoding: [51, 53, 55, 57, 56, 54], as: UTF8.self)
        let secondExpected = String(decoding: [48, 50, 52, 54, 56, 57], as: UTF8.self)
        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-MAP-1"},"msg":"ok"}"#
                )
            case 2:
                keyboardOrderBindings.withValue {
                    $0.append(formValues(request)["orderid"] == "ELEC-MAP-1")
                }
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"11111111111111111111111111111111":"9081726354"}},"msg":"ok"}"#
                )
            case 3:
                let form = formValues(request)
                finalMaterialBindings.withValue {
                    $0.append(
                        form["orderid"] == "ELEC-MAP-1"
                            && form["uuid"] == firstUUID
                            && form["password"] == firstExpected
                    )
                }
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            case 4, 8:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{}},"msg":"ok"}"#
                )
            case 5:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"ELEC-MAP-2"},"msg":"ok"}"#
                )
            case 6:
                keyboardOrderBindings.withValue {
                    $0.append(formValues(request)["orderid"] == "ELEC-MAP-2")
                }
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"passwordMap":{"22222222222222222222222222222222":"1029384756"}},"msg":"ok"}"#
                )
            case 7:
                let form = formValues(request)
                finalMaterialBindings.withValue {
                    $0.append(
                        form["orderid"] == "ELEC-MAP-2"
                            && form["uuid"] == secondUUID
                            && form["password"] == secondExpected
                    )
                }
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }
        let gateway = makeGateway()
        for (index, key) in ["fresh-map-key-1", "fresh-map-key-2"].enumerated() {
            let order = try await gateway.createOrder(
                request: try electricityRequest(),
                idempotencyKey: key
            )
            XCTAssertEqual(order.id, "ELEC-MAP-\(index + 1)")
            let prepared = try await gateway.prepareConfirmation(
                orderID: order.id,
                feature: .electricity,
                method: .campusAccount,
                authorization: try transientAuthorization()
            )
            assertConfirmed(try await gateway.submitPreparedConfirmation(prepared))
        }
        XCTAssertTrue(keyboardOrderBindings.value == [true, true])
        XCTAssertTrue(finalMaterialBindings.value == [true, true])
    }

    func testEachNetworkOrderUsesItsOwnFreshPasswordMapAndUUID() async throws {
        let keyboardOrderBindings = YCardProductionLockedBox<[Bool]>([])
        let finalMaterialBindings = YCardProductionLockedBox<[Bool]>([])
        let firstUUID = String(repeating: "3", count: 32)
        let secondUUID = String(repeating: "4", count: 32)
        let firstMap = String(
            decoding: [57, 48, 56, 49, 55, 50, 54, 51, 53, 52],
            as: UTF8.self
        )
        let secondMap = String(
            decoding: [49, 48, 50, 57, 51, 56, 52, 55, 53, 54],
            as: UTF8.self
        )
        let firstExpected = String(decoding: [51, 53, 55, 57, 56, 54], as: UTF8.self)
        let secondExpected = String(decoding: [48, 50, 52, 54, 56, 57], as: UTF8.self)
        let firstKeyboardResponse = try dynamicKeyboardResponse(
            uuid: firstUUID,
            map: firstMap
        )
        let secondKeyboardResponse = try dynamicKeyboardResponse(
            uuid: secondUUID,
            map: secondMap
        )

        YCardProductionTestURLProtocol.handler = { request, index in
            switch index {
            case 1:
                return try response(request, status: 302)
            case 2:
                return try response(request, json: #"{"code":200,"msg":"ok"}"#)
            case 3:
                return try response(
                    request,
                    json: #"{"code":200,"feeitem":{"name":"fixture"},"msg":"ok"}"#
                )
            case 4, 8, 12:
                return try response(
                    request,
                    json: #"{"code":200,"map":{"showData":{},"data":{"account":"fixture"}},"msg":"ok"}"#
                )
            case 5:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"NET-MAP-1"},"msg":"ok"}"#
                )
            case 6:
                keyboardOrderBindings.withValue {
                    $0.append(formValues(request)["orderid"] == "NET-MAP-1")
                }
                return try response(request, json: firstKeyboardResponse)
            case 7:
                let form = formValues(request)
                finalMaterialBindings.withValue {
                    $0.append(
                        form["orderid"] == "NET-MAP-1"
                            && form["uuid"] == firstUUID
                            && form["password"] == firstExpected
                    )
                }
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            case 9:
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":{"orderid":"NET-MAP-2"},"msg":"ok"}"#
                )
            case 10:
                keyboardOrderBindings.withValue {
                    $0.append(formValues(request)["orderid"] == "NET-MAP-2")
                }
                return try response(request, json: secondKeyboardResponse)
            case 11:
                let form = formValues(request)
                finalMaterialBindings.withValue {
                    $0.append(
                        form["orderid"] == "NET-MAP-2"
                            && form["uuid"] == secondUUID
                            && form["password"] == secondExpected
                    )
                }
                return try response(
                    request,
                    json: #"{"code":200,"success":true,"data":"accepted","msg":"ok"}"#
                )
            default:
                throw YCardProductionMockError.unexpectedRequest
            }
        }

        let gateway = makeGateway()
        let request = try paymentRequest(
            feature: .networkRecharge,
            method: .campusAccount,
            context: .networkRecharge(
                thirdPartyJSON: #"{"account":"fixture","balance":"10.00"}"#
            )
        )
        for (index, key) in ["fresh-network-map-key-1", "fresh-network-map-key-2"].enumerated() {
            let order = try await gateway.createOrder(
                request: request,
                idempotencyKey: key
            )
            XCTAssertEqual(order.id, "NET-MAP-\(index + 1)")
            let prepared = try await gateway.prepareConfirmation(
                orderID: order.id,
                feature: .networkRecharge,
                method: .campusAccount,
                authorization: try transientAuthorization()
            )
            assertConfirmed(try await gateway.submitPreparedConfirmation(prepared))
        }

        XCTAssertTrue(keyboardOrderBindings.value == [true, true])
        XCTAssertTrue(finalMaterialBindings.value == [true, true])
        XCTAssertEqual(YCardProductionTestURLProtocol.requestCount, 12)
    }

    func testMockModeWithoutRegisteredURLProtocolCannotSendDebit() async {
        let client = YCardProductionPaymentClient(
            campusAPI: YCardProductionCampusAPIStub(),
            configuration: YCardProductionPaymentClient.makeConfiguration(),
            mockTransportEnabled: true
        )
        var blocked = false
        do {
            _ = try await client.execute(.cardCreate, formFields: [])
        } catch let error as YCardProductionPaymentError {
            blocked = error == .automatedDebitDisabled
        } catch { }
        XCTAssertTrue(blocked)
    }

    func testMalformedFinalResponseIsUnknownNotSuccess() {
        let status = YCardProductionPaymentDecoder.finalStatus(
            from: Data("not-json".utf8),
            feature: .electricity
        )
        guard case .unknown = status else {
            return XCTFail("Expected unknown result")
        }
    }

    func testCardAndBathroomCode200RemainConfirmedWhenSuccessIsFalse() {
        let response = Data(#"{"code":200,"success":false}"#.utf8)

        for feature in [PaymentFeature.cardRecharge, .bathroom] {
            assertConfirmed(
                YCardProductionPaymentDecoder.finalStatus(
                    from: response,
                    feature: feature
                )
            )
        }
    }

    func testCardAndBathroomNon200RemainRejectedWhenSuccessIsTrue() {
        let response = Data(#"{"code":500,"success":true}"#.utf8)

        for feature in [PaymentFeature.cardRecharge, .bathroom] {
            assertRejected(
                YCardProductionPaymentDecoder.finalStatus(
                    from: response,
                    feature: feature
                )
            )
        }
    }

    func testElectricityAndNetworkKeepTheirFeatureSpecificSuccessRules() {
        let successFalse = Data(#"{"code":200,"success":false,"data":"receipt"}"#.utf8)
        assertRejected(
            YCardProductionPaymentDecoder.finalStatus(
                from: successFalse,
                feature: .electricity
            )
        )
        assertRejected(
            YCardProductionPaymentDecoder.finalStatus(
                from: successFalse,
                feature: .networkRecharge
            )
        )

        let emptyNetworkData = Data(#"{"code":200,"success":true,"data":""}"#.utf8)
        assertRejected(
            YCardProductionPaymentDecoder.finalStatus(
                from: emptyNetworkData,
                feature: .networkRecharge
            )
        )

        let blankNetworkData = Data(#"{"code":200,"success":true,"data":" \n\t"}"#.utf8)
        assertRejected(
            YCardProductionPaymentDecoder.finalStatus(
                from: blankNetworkData,
                feature: .networkRecharge
            )
        )

        let accepted = Data(#"{"code":200,"success":true,"data":"receipt"}"#.utf8)
        assertConfirmed(
            YCardProductionPaymentDecoder.finalStatus(
                from: accepted,
                feature: .electricity
            )
        )
        assertConfirmed(
            YCardProductionPaymentDecoder.finalStatus(
                from: accepted,
                feature: .networkRecharge
            )
        )
    }

    private func makeGateway() -> YCardProductionPaymentGateway {
        YCardProductionPaymentGateway(
            campusAPI: YCardProductionCampusAPIStub(),
            configuration: YCardProductionPaymentClient.makeConfiguration(
                protocolClasses: [YCardProductionTestURLProtocol.self]
            ),
            mockTransportEnabled: true,
            signer: YCardProductionPaymentSigner(
                clock: { Date(timeIntervalSince1970: 1_767_326_645) },
                nonce: { "abc123def45" },
                timeZone: TimeZone(secondsFromGMT: 0)!
            )
        )
    }

    private func paymentRequest(
        feature: PaymentFeature,
        method: PaymentMethod,
        context: PaymentTransactionContext
    ) throws -> PaymentRequest {
        try PaymentRequest(
            feature: feature,
            method: method,
            amount: PaymentAmount("10"),
            accountID: "fixture-account",
            accountLabel: "fixture-label",
            context: context
        )
    }

    private func electricityRequest() throws -> PaymentRequest {
        try paymentRequest(
            feature: .electricity,
            method: .campusAccount,
            context: .electricity(
                thirdPartyJSON: #"{"area":"A","building":"B","floor":"F","room":"R"}"#
            )
        )
    }

    private func transientAuthorization() throws -> TransientPaymentAuthorization {
        try TransientPaymentAuthorization(
            digits: String(decoding: [49, 50, 51, 52, 53, 54], as: UTF8.self)
        )
    }

    private func dynamicKeyboardResponse(uuid: String, map: String) throws -> String {
        let object: [String: Any] = [
            "code": 200,
            "success": true,
            "data": ["passwordMap": [uuid: map]],
            "msg": "ok"
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func assertConfirmed(
        _ status: PaymentOrderStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .confirmed = status else {
            return XCTFail("Expected confirmed status", file: file, line: line)
        }
    }

    private func assertRejected(
        _ status: PaymentOrderStatus,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case .rejected = status else {
            return XCTFail("Expected rejected status", file: file, line: line)
        }
    }
}

private enum YCardProductionMockError: Error {
    case unexpectedRequest
}

private func response(
    _ request: URLRequest,
    status: Int = 200,
    headers: [String: String] = [:],
    data: Data = Data()
) throws -> (HTTPURLResponse, Data) {
    let url = try XCTUnwrap(request.url)
    let response = try XCTUnwrap(HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: "HTTP/1.1",
        headerFields: headers
    ))
    return (response, data)
}

private func response(
    _ request: URLRequest,
    status: Int = 200,
    headers: [String: String] = [:],
    json: String
) throws -> (HTTPURLResponse, Data) {
    try response(
        request,
        status: status,
        headers: headers.merging(["Content-Type": "application/json"]) { current, _ in current },
        data: Data(json.utf8)
    )
}

private func formFieldNames(_ request: URLRequest) -> Set<String> {
    guard let values = try? StrictServerFormTestDecoder.values(request) else { return [] }
    return Set(values.keys)
}

private func formValues(_ request: URLRequest) -> [String: String] {
    (try? StrictServerFormTestDecoder.values(request)) ?? [:]
}

private final class YCardProductionTestURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (
        URLRequest,
        Int
    ) throws -> (HTTPURLResponse, Data)

    private static let handlerBox = YCardProductionLockedBox<Handler?>(nil)
    private static let countBox = YCardProductionLockedBox(0)

    static var handler: Handler? {
        get { handlerBox.value }
        set { handlerBox.set(newValue) }
    }

    static var requestCount: Int { countBox.value }

    static func reset() {
        handler = nil
        countBox.set(0)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            guard let handler = Self.handler else {
                throw URLError(.cannotLoadFromNetwork)
            }
            let index = Self.countBox.withValue { count in
                count += 1
                return count
            }
            let (response, data) = try handler(request, index)
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

private final class YCardProductionLockedBox<Value>: @unchecked Sendable {
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

private actor YCardProductionCampusAPIStub: CampusCoreAPI {
    func initialize(cookiesJSON: String) { }
    func login(studentID: String, password: String) throws -> User {
        throw CampusCoreError.invalidResponse
    }
    func dumpCookies() -> String { "[]" }
    func cookiesFlat() -> String { "[]" }
    func schedule() throws -> [Course] { throw CampusCoreError.invalidResponse }
    func currentWeek() throws -> Int { throw CampusCoreError.invalidResponse }
    func exams() throws -> [CampusExam] { throw CampusCoreError.invalidResponse }
    func grades() throws -> CampusGradeReport { throw CampusCoreError.invalidResponse }
    func cardBalance() throws -> Double { throw CampusCoreError.invalidResponse }
    func cardQRCode() throws -> String { throw CampusCoreError.invalidResponse }
    func cardAccessToken() -> String { "fixture-token" }
}
