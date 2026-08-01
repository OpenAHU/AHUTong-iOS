import Foundation
import XCTest
@testable import AHUTong

final class PaymentReadOnlyRequestPolicyTests: XCTestCase {
    override func tearDown() {
        YCardReadOnlyTestURLProtocol.handler = nil
        super.tearDown()
    }

    func testReadOnlyTransportDoesNotPersistCookiesCredentialsOrCache() {
        let configuration = YCardReadOnlyClient.makeConfiguration()

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

    func testOnlyAndroidReadEndpointsAreAllowed() throws {
        let cardRequest = try YCardReadOnlyClient.makeRequest(
            .cardAccount,
            queryItems: YCardReadOnlyContract.cardAccountQuery,
            accessToken: "temporary-token",
            cookies: []
        )
        let feeItemRequest = try YCardReadOnlyClient.makeRequest(
            .feeItemData,
            formItems: [
                URLQueryItem(name: "feeitemid", value: "488"),
                URLQueryItem(name: "type", value: "select"),
                URLQueryItem(name: "level", value: "0")
            ],
            accessToken: "temporary-token",
            cookies: []
        )
        XCTAssertNoThrow(
            try YCardReadOnlyRequestPolicy.authorize(cardRequest)
        )
        XCTAssertNoThrow(
            try YCardReadOnlyRequestPolicy.authorize(feeItemRequest)
        )

        for (method, rawURL) in [
            ("POST", "https://ycard.ahu.edu.cn/blade-pay/pay"),
            ("POST", "https://ycard.ahu.edu.cn/charge/order/thirdOrder"),
            (
                "POST",
                "https://attacker.example/charge/feeitem/getThirdData"
            ),
            (
                "POST",
                "http://ycard.ahu.edu.cn/charge/feeitem/getThirdData"
            )
        ] {
            var request = URLRequest(url: try XCTUnwrap(URL(string: rawURL)))
            request.httpMethod = method
            XCTAssertThrowsError(
                try YCardReadOnlyRequestPolicy.authorize(request)
            ) { error in
                XCTAssertEqual(
                    error as? YCardReadOnlyError,
                    .disallowedEndpoint
                )
            }
        }
        XCTAssertEqual(
            YCardReadOnlyRequestPolicy.credentialPersistence,
            .memoryOnly
        )
    }

    func testCardAccountRequestUsesBearerTrustedCookiesAndExactQuery() throws {
        let request = try YCardReadOnlyClient.makeRequest(
            .cardAccount,
            queryItems: YCardReadOnlyContract.cardAccountQuery,
            accessToken: "temporary-token",
            cookies: [
                CampusCookie(
                    name: "ROOT",
                    value: "temporary-cookie",
                    domain: ".ahu.edu.cn",
                    path: "/",
                    secure: true,
                    httpOnly: true
                ),
                CampusCookie(
                    name: "ATTACKER",
                    value: "blocked",
                    domain: "ahu.edu.cn.attacker.example",
                    path: "/",
                    secure: true,
                    httpOnly: false
                )
            ]
        )
        let components = try XCTUnwrap(
            URLComponents(
                url: try XCTUnwrap(request.url),
                resolvingAgainstBaseURL: false
            )
        )
        let query = Dictionary(uniqueKeysWithValues:
            try XCTUnwrap(components.queryItems).map {
                ($0.name, $0.value)
            }
        )

        XCTAssertEqual(request.httpMethod, "GET")
        XCTAssertEqual(
            request.url?.path,
            "/berserker-app/ykt/tsm/queryCard"
        )
        XCTAssertEqual(query["scene"]!, "cardRecharge")
        XCTAssertEqual(query["synAccessSource"]!, "h5")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Synjones-Auth"),
            "bearer temporary-token"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Cookie"),
            "ROOT=temporary-cookie"
        )
        XCTAssertNil(request.httpBody)
        XCTAssertNil(request.value(forHTTPHeaderField: "SIGN"))
    }

    func testFeeItemRequestUsesFormBodyAndChargeHeaders() throws {
        let request = try YCardReadOnlyClient.makeRequest(
            .feeItemData,
            formItems: [
                URLQueryItem(name: "feeitemid", value: "488"),
                URLQueryItem(name: "type", value: "select"),
                URLQueryItem(name: "level", value: "0")
            ],
            accessToken: "temporary-token",
            cookies: []
        )
        let bodyData = try XCTUnwrap(request.httpBody)
        let body = String(decoding: bodyData, as: UTF8.self)
        let values = try StrictServerFormTestDecoder.values(bodyData)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            request.url?.path,
            "/charge/feeitem/getThirdData"
        )
        XCTAssertEqual(values["feeitemid"], "488")
        XCTAssertEqual(values["type"], "select")
        XCTAssertEqual(values["level"], "0")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Referer"),
            "https://ycard.ahu.edu.cn/charge-app/"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Origin"),
            "https://ycard.ahu.edu.cn"
        )
        XCTAssertFalse(body.contains("SIGN"))
        XCTAssertFalse(body.contains("SECRET_KEY"))
        XCTAssertFalse(body.contains("password"))
        XCTAssertFalse(body.contains("uuid"))
    }

    func testFeeItemPostUsesOkHttpCompatibleFormBytes() throws {
        let campus = "A+B C%D&E=F~中文"
        let request = try YCardReadOnlyClient.makeRequest(
            .feeItemData,
            formItems: [
                URLQueryItem(name: "feeitemid", value: "488"),
                URLQueryItem(name: "type", value: "IEC"),
                URLQueryItem(name: "level", value: "4"),
                URLQueryItem(name: "campus", value: campus),
                URLQueryItem(name: "building", value: "B"),
                URLQueryItem(name: "floor", value: "F"),
                URLQueryItem(name: "room", value: "R")
            ],
            accessToken: "temporary-token",
            cookies: []
        )
        let body = try XCTUnwrap(request.httpBody)
        let transport = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(transport.contains(
            "campus=A%2BB+C%25D%26E%3DF%7E%E4%B8%AD%E6%96%87"
        ))
        let decoded = try StrictServerFormTestDecoder.values(body)
        XCTAssertEqual(decoded["campus"], campus)
    }

    func testReadEndpointsRejectPaymentFieldsAndUnexpectedQueries() throws {
        XCTAssertThrowsError(try YCardReadOnlyClient.makeRequest(
            .feeItemData,
            formItems: [
                URLQueryItem(name: "feeitemid", value: "488"),
                URLQueryItem(name: "type", value: "select"),
                URLQueryItem(name: "level", value: "0"),
                URLQueryItem(name: "tranamt", value: "1.00")
            ],
            accessToken: "temporary-token",
            cookies: []
        ))

        let validFeeRequest = try YCardReadOnlyClient.makeRequest(
            .feeItemData,
            formItems: YCardReadOnlyContract.electricitySelectionForm(
                level: "0"
            ),
            accessToken: "temporary-token",
            cookies: []
        )
        for suffix in ["&extra=%", "&extra=%FF", "&%66eeitemid=488"] {
            var request = validFeeRequest
            var body = try XCTUnwrap(validFeeRequest.httpBody)
            body.append(contentsOf: suffix.utf8)
            request.httpBody = body
            XCTAssertThrowsError(
                try YCardReadOnlyRequestPolicy.authorize(request)
            )
        }
        for rawURL in [
            "https://ycard.ahu.edu.cn/charge/feeitem/getThirdData?tranamt=1",
            "https://ycard.ahu.edu.cn:444/charge/feeitem/getThirdData",
            "https://user@ycard.ahu.edu.cn/charge/feeitem/getThirdData"
        ] {
            var request = validFeeRequest
            request.url = try XCTUnwrap(URL(string: rawURL))
            XCTAssertThrowsError(
                try YCardReadOnlyRequestPolicy.authorize(request)
            )
        }
        XCTAssertThrowsError(try YCardReadOnlyClient.makeRequest(
            .cardAccount,
            queryItems: [
                URLQueryItem(name: "scene", value: "cardRecharge"),
                URLQueryItem(name: "synAccessSource", value: "h5"),
                URLQueryItem(name: "synjones-auth", value: "must-not-leak")
            ],
            accessToken: "temporary-token",
            cookies: []
        ))
    }

    func testAndroidBathroomAndElectricityReadContractsKeepExactLevels() {
        let bathroom = values(YCardReadOnlyContract.bathroomForm(
            feeItemID: "409",
            phone: "13800000000"
        ))
        XCTAssertEqual(bathroom["feeitemid"], "409")
        XCTAssertEqual(bathroom["type"], "IEC")
        XCTAssertEqual(bathroom["level"], "1")
        XCTAssertEqual(bathroom["telPhone"], "13800000000")

        let campus = YCardSelectionOption(name: "校区", value: "campus-id")
        let building = YCardSelectionOption(
            name: "楼栋",
            value: "building-id"
        )
        let floor = YCardSelectionOption(name: "楼层", value: "floor-id")
        let room = YCardSelectionOption(name: "房间", value: "room-id")
        let levels = [
            values(YCardReadOnlyContract.electricitySelectionForm(level: "0")),
            values(YCardReadOnlyContract.electricitySelectionForm(
                level: "1",
                values: [
                    URLQueryItem(name: "campus", value: campus.value)
                ]
            )),
            values(YCardReadOnlyContract.electricitySelectionForm(
                level: "2",
                values: [
                    URLQueryItem(name: "campus", value: campus.value),
                    URLQueryItem(name: "building", value: building.value)
                ]
            )),
            values(YCardReadOnlyContract.electricitySelectionForm(
                level: "3",
                values: [
                    URLQueryItem(name: "campus", value: campus.value),
                    URLQueryItem(name: "building", value: building.value),
                    URLQueryItem(name: "floor", value: floor.value)
                ]
            ))
        ]
        XCTAssertEqual(levels.map { $0["level"]! }, ["0", "1", "2", "3"])
        XCTAssertTrue(levels.allSatisfy { $0["feeitemid"] == "488" })
        XCTAssertTrue(levels.allSatisfy { $0["type"] == "select" })

        let detail = values(YCardReadOnlyContract.electricityRoomForm(
            campus: campus,
            building: building,
            floor: floor,
            room: room
        ))
        XCTAssertEqual(detail["feeitemid"], "488")
        XCTAssertEqual(detail["type"], "IEC")
        XCTAssertEqual(detail["level"], "4")
        XCTAssertEqual(detail["campus"], "campus-id")
        XCTAssertEqual(detail["building"], "building-id")
        XCTAssertEqual(detail["floor"], "floor-id")
        XCTAssertEqual(detail["room"], "room-id")
    }

    func testPhoneContractAcceptsOnlyElevenASCIIDigits() {
        XCTAssertTrue(YCardReadOnlyContract.isValidPhone("13800000000"))
        XCTAssertFalse(YCardReadOnlyContract.isValidPhone("１３８００００００００"))
        XCTAssertFalse(YCardReadOnlyContract.isValidPhone("١٣٨٠٠٠٠٠٠٠٠"))
        XCTAssertEqual(
            YCardReadOnlyContract.normalizedPhone("１３8a000-00000"),
            "800000000"
        )
    }

    func testRedirectAndAuthorizationFailuresRefreshTokenAndRetryOnce() async throws {
        for statusCode in [302, 401, 403] {
            let api = YCardReadOnlyAPIStub(cookies: """
                [{"name":"SESSION","value":"old-cookie","domain":"ycard.ahu.edu.cn","path":"/","secure":true}]
                """)
            let configuration = YCardReadOnlyClient.makeConfiguration()
            configuration.protocolClasses = [YCardReadOnlyTestURLProtocol.self]
            let client = YCardReadOnlyClient(
                campusAPI: api,
                configuration: configuration
            )
            let requestCount = YCardReadOnlyLockedBox(0)
            let sentCookies = YCardReadOnlyLockedBox<[String?]>([])
            YCardReadOnlyTestURLProtocol.handler = { request in
                sentCookies.withValue {
                    $0.append(request.value(forHTTPHeaderField: "Cookie"))
                }
                let count = requestCount.withValue {
                    $0 += 1
                    return $0
                }
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: count == 1 ? statusCode : 200,
                        httpVersion: "HTTP/1.1",
                        headerFields: statusCode == 302 && count == 1
                            ? ["Location": "/login"]
                            : nil
                    )!,
                    Data("ok".utf8)
                )
            }

            let result = try await client.request(
                .cardAccount,
                queryItems: YCardReadOnlyContract.cardAccountQuery
            )

            let tokenRequestCount = await api.tokenRequestCount()
            let refreshCount = await api.refreshCount()
            XCTAssertEqual(String(decoding: result, as: UTF8.self), "ok")
            XCTAssertEqual(tokenRequestCount, 2)
            XCTAssertEqual(refreshCount, 1)
            XCTAssertEqual(sentCookies.value.count, 2)
            XCTAssertEqual(sentCookies.value[0], "SESSION=old-cookie")
            XCTAssertNil(sentCookies.value[1])
        }
    }

    func testResponseURLMismatchFailsClosedAndClearsCredentials() async throws {
        let api = YCardReadOnlyAPIStub(cookies: "[]")
        let configuration = YCardReadOnlyClient.makeConfiguration()
        configuration.protocolClasses = [YCardReadOnlyTestURLProtocol.self]
        let client = YCardReadOnlyClient(
            campusAPI: api,
            configuration: configuration
        )
        let requestCount = YCardReadOnlyLockedBox(0)
        YCardReadOnlyTestURLProtocol.handler = { request in
            let count = requestCount.withValue {
                $0 += 1
                return $0
            }
            let responseURL = count == 1
                ? URL(string: "https://epay92.ahu.edu.cn/charge-app")!
                : request.url!
            return (
                HTTPURLResponse(
                    url: responseURL,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!,
                Data("ok".utf8)
            )
        }

        do {
            _ = try await client.request(
                .cardAccount,
                queryItems: YCardReadOnlyContract.cardAccountQuery
            )
            XCTFail("Expected invalidResponse")
        } catch {
            XCTAssertEqual(error as? YCardReadOnlyError, .invalidResponse)
        }
        _ = try await client.request(
            .cardAccount,
            queryItems: YCardReadOnlyContract.cardAccountQuery
        )
        let tokenRequestCount = await api.tokenRequestCount()
        XCTAssertEqual(tokenRequestCount, 2)
    }

    func testExpiredResponseCookieIsDeletedBeforeNextRequest() async throws {
        let api = YCardReadOnlyAPIStub(cookies: """
            [{"name":"SESSION","value":"old-cookie","domain":"ycard.ahu.edu.cn","path":"/","secure":true}]
            """)
        let configuration = YCardReadOnlyClient.makeConfiguration()
        configuration.protocolClasses = [YCardReadOnlyTestURLProtocol.self]
        let client = YCardReadOnlyClient(
            campusAPI: api,
            configuration: configuration
        )
        let requestCount = YCardReadOnlyLockedBox(0)
        let sentCookies = YCardReadOnlyLockedBox<[String?]>([])
        YCardReadOnlyTestURLProtocol.handler = { request in
            sentCookies.withValue {
                $0.append(request.value(forHTTPHeaderField: "Cookie"))
            }
            let count = requestCount.withValue {
                $0 += 1
                return $0
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: count == 1
                        ? [
                            "Set-Cookie": "SESSION=; Path=/; "
                                + "Max-Age=0; Secure"
                        ]
                        : nil
                )!,
                Data("ok".utf8)
            )
        }

        _ = try await client.request(
            .cardAccount,
            queryItems: YCardReadOnlyContract.cardAccountQuery
        )
        _ = try await client.request(
            .cardAccount,
            queryItems: YCardReadOnlyContract.cardAccountQuery
        )

        XCTAssertEqual(sentCookies.value.count, 2)
        XCTAssertEqual(sentCookies.value[0], "SESSION=old-cookie")
        XCTAssertNil(sentCookies.value[1])
    }

    private func values(
        _ items: [URLQueryItem]
    ) -> [String: String] {
        Dictionary(uniqueKeysWithValues:
            items.map { ($0.name, $0.value ?? "") }
        )
    }
}

final class PaymentReadOnlyDecoderTests: XCTestCase {
    func testMalformedCardAndSelectionJSONUseFiniteErrors() {
        let malformed = Data(#"{"student":"must-not-leak""#.utf8)

        XCTAssertThrowsError(
            try YCardPaymentDecoder.decodeCardAccount(malformed)
        ) { error in
            XCTAssertEqual(error as? YCardReadOnlyError, .invalidResponse)
            XCTAssertFalse(error.localizedDescription.contains("student"))
        }
        XCTAssertThrowsError(
            try YCardPaymentDecoder.decodeSelectionOptions(malformed)
        ) { error in
            XCTAssertEqual(error as? YCardReadOnlyError, .invalidResponse)
            XCTAssertFalse(error.localizedDescription.contains("student"))
        }
    }

    func testDecodesAndroidCardAccountNameTypeAndCentBalance() throws {
        let data = Data(#"""
        {
          "code": 200,
          "success": true,
          "msg": "success",
          "data": {
            "card": [{
              "accinfo": [{
                "name": "主钱包",
                "type": "01",
                "balance": 12635
              }]
            }]
          }
        }
        """#.utf8)

        let account = try XCTUnwrap(
            YCardPaymentDecoder.decodeCardAccount(data)
        )

        XCTAssertEqual(account.id, "01")
        XCTAssertEqual(account.displayName, "主钱包 01")
        XCTAssertEqual(
            account.balance,
            try XCTUnwrap(Decimal(string: "126.35"))
        )
    }

    func testDecodesBathroomBalancesAndNormalizesAndroidPaymentContext() throws {
        let data = Data(#"""
        {
          "code": 0,
          "msg": "success",
          "map": {
            "showData": {
              "手机号": "13800000000",
              "现金金额（单位：元）": "18.60",
              "赠送金额（单位：元）": "2.00"
            },
            "data": {
              "projectId": 12,
              "projectName": "浴室项目",
              "accountId": 456,
              "telPhone": "13800000000",
              "identifier": "read-only-account",
              "statusId": 1,
              "nested": { "preserved": true }
            }
          }
        }
        """#.utf8)

        let result = try YCardPaymentDecoder.decodeBathroomAccount(
            data,
            bathroomName: "竹园/龙河",
            requestedPhone: "13800000000"
        )
        let account = try XCTUnwrap(result.account)

        XCTAssertEqual(account.id, "456")
        XCTAssertEqual(account.name, "竹园/龙河")
        XCTAssertEqual(account.phone, "13800000000")
        XCTAssertEqual(
            account.cashBalance,
            try XCTUnwrap(Decimal(string: "18.60"))
        )
        XCTAssertEqual(
            account.giftBalance,
            try XCTUnwrap(Decimal(string: "2.00"))
        )
        XCTAssertNil(result.message)
        let contextData = try XCTUnwrap(result.thirdPartyJSON)
        let context = try XCTUnwrap(
            JSONSerialization.jsonObject(with: contextData) as? [String: Any]
        )
        XCTAssertEqual(context["projectId"] as? Int, 12)
        XCTAssertEqual(context["accountId"] as? Int, 456)
        XCTAssertEqual(context["myCustomInfo"] as? String, "手机号：13800000000")
        XCTAssertNil(context["nested"])
    }

    func testBathroomMissingAccountUsesFiniteSafeEmptyState() throws {
        let data = Data(#"""
        {
          "code": 0,
          "msg": "success",
          "message": "手机号 13800000000 token=temporary-secret",
          "map": null
        }
        """#.utf8)

        let result = try YCardPaymentDecoder.decodeBathroomAccount(
            data,
            bathroomName: "桔园/蕙园",
            requestedPhone: "13800000000"
        )

        XCTAssertNil(result.account)
        XCTAssertEqual(result.message, "未查询到浴室账户")
        XCTAssertNil(result.thirdPartyJSON)
        XCTAssertFalse(try XCTUnwrap(result.message).contains("13800000000"))
        XCTAssertFalse(try XCTUnwrap(result.message).contains("temporary-secret"))
    }

    func testBathroomDecoderRejectsNonObjectPaymentData() {
        let payload = Data(#"""
        {
          "code": 200,
          "map": {
            "showData": {
              "手机号": "fixture",
              "现金金额（单位：元）": "1",
              "赠送金额（单位：元）": "0"
            },
            "data": ["unexpected"]
          }
        }
        """#.utf8)

        XCTAssertThrowsError(
            try YCardPaymentDecoder.decodeBathroomAccount(
                payload,
                bathroomName: "fixture",
                requestedPhone: "fixture"
            )
        ) { error in
            XCTAssertEqual(error as? YCardReadOnlyError, .invalidResponse)
        }
    }

    func testServerFailureNeverExposesPhoneOrTokenMessage() throws {
        let data = Data(#"""
        {
          "code": 500,
          "msg": "phone=13800000000 token=temporary-secret",
          "map": null
        }
        """#.utf8)

        XCTAssertThrowsError(
            try YCardPaymentDecoder.decodeSelectionOptions(data)
        ) { error in
            let message = error.localizedDescription
            XCTAssertFalse(message.contains("13800000000"))
            XCTAssertFalse(message.contains("temporary-secret"))
            XCTAssertEqual(
                message,
                "学校校园卡服务暂时无法完成查询，请稍后重试"
            )
        }
    }

    func testMalformedBathroomBalanceFailsInsteadOfBecomingZero() {
        let data = Data(#"""
        {
          "code": 0,
          "msg": "success",
          "map": {
            "showData": {
              "手机号": "13800000000",
              "现金金额（单位：元）": "not-a-balance",
              "赠送金额（单位：元）": "2.00"
            },
            "data": { "accountId": 456, "telPhone": "13800000000" }
          }
        }
        """#.utf8)

        XCTAssertThrowsError(try YCardPaymentDecoder.decodeBathroomAccount(
            data,
            bathroomName: "竹园/龙河",
            requestedPhone: "13800000000"
        )) { error in
            XCTAssertEqual(error as? YCardReadOnlyError, .invalidResponse)
        }
    }

    func testMissingElectricityBalanceRemainsUnavailableInsteadOfBecomingZero() throws {
        let data = Data(#"""
        {
          "code": 0,
          "msg": "success",
          "map": {
            "showData": { "信息": "房间：磬苑校区 竹园 3层 305" },
            "data": {
              "areaName": "磬苑校区",
              "buildingName": "竹园",
              "floorName": "3层",
              "account": "electric-account-305",
              "roomName": "305",
              "nested": { "preserved": false }
            }
          }
        }
        """#.utf8)

        let room = try YCardPaymentDecoder.decodeElectricityRoom(
            data,
            campus: YCardSelectionOption(name: "磬苑校区", value: "campus"),
            building: YCardSelectionOption(name: "竹园", value: "building"),
            floor: YCardSelectionOption(name: "3层", value: "floor"),
            room: YCardSelectionOption(name: "305", value: "room")
        )
        XCTAssertNil(room.balance)
        XCTAssertEqual(room.information, "房间：磬苑校区 竹园 3层 305")
    }

    func testDecodesElectricitySelectionAndRoomBalance() throws {
        let selection = Data(#"""
        {
          "code": 200,
          "msg": "success",
          "map": {
            "data": [
              { "name": "磬苑校区", "value": "campus-qy" },
              { "name": "龙河校区", "value": "campus-lh" }
            ]
          }
        }
        """#.utf8)
        let options = try YCardPaymentDecoder.decodeSelectionOptions(
            selection
        )
        XCTAssertEqual(options.map(\.name), ["磬苑校区", "龙河校区"])
        XCTAssertEqual(options.map(\.value), ["campus-qy", "campus-lh"])

        let roomData = Data(#"""
        {
          "code": 0,
          "msg": "success",
          "map": {
            "showData": {
              "信息": "房间当前剩余电量1.95，电量单价0.56",
              "扩展字段": { "ignored": true }
            },
            "data": {
              "areaName": "磬苑校区",
              "buildingName": "竹园",
              "floorName": "3层",
              "account": "electric-account-305",
              "roomName": "305"
            }
          }
        }
        """#.utf8)
        let room = try YCardPaymentDecoder.decodeElectricityRoom(
            roomData,
            campus: options[0],
            building: YCardSelectionOption(
                name: "竹园",
                value: "building-zhu"
            ),
            floor: YCardSelectionOption(name: "3层", value: "floor-3"),
            room: YCardSelectionOption(name: "305", value: "room-305")
        )

        XCTAssertEqual(room.id, "electric-account-305")
        XCTAssertEqual(room.label, "磬苑校区 · 竹园 · 3层 · 305")
        XCTAssertEqual(
            room.balance,
            try XCTUnwrap(Decimal(string: "1.95"))
        )
        XCTAssertEqual(
            room.information,
            "房间当前剩余电量1.95，电量单价0.56"
        )

        let paymentResult = try YCardPaymentDecoder.decodeElectricityRoomLookup(
            roomData,
            campus: options[0],
            building: YCardSelectionOption(
                name: "竹园",
                value: "building-zhu"
            ),
            floor: YCardSelectionOption(name: "3层", value: "floor-3"),
            room: YCardSelectionOption(name: "305", value: "room-305")
        )
        let contextData = try XCTUnwrap(paymentResult.thirdPartyJSON)
        let context = try XCTUnwrap(
            JSONSerialization.jsonObject(with: contextData) as? [String: Any]
        )
        XCTAssertEqual(context["account"] as? String, "electric-account-305")
        XCTAssertEqual(context["roomName"] as? String, "305")
        XCTAssertEqual(context["extdata"] as? String, "")
        XCTAssertEqual(
            context["myCustomInfo"] as? String,
            "房间：磬苑校区 竹园 3层 305"
        )
        XCTAssertNil(context["nested"])
    }

    func testAlipayHandoffRejectsIdentityAndCredentialParameters() throws {
        XCTAssertTrue(
            AlipayCampusCardHandoff.isAllowed(
                AlipayCampusCardHandoff.appURL
            )
        )
        XCTAssertTrue(
            AlipayCampusCardHandoff.isAllowed(
                AlipayCampusCardHandoff.fallbackURL
            )
        )
        XCTAssertFalse(AlipayCampusCardHandoff.isAllowed(
            try XCTUnwrap(URL(
                string: "https://www.wmslz.com/s/M6KARh485j3?studentID=secret"
            ))
        ))
        XCTAssertFalse(AlipayCampusCardHandoff.isAllowed(
            try XCTUnwrap(URL(
                string: "alipays://platformapi/startapp?appId=2019090967125695&studentID=secret"
            ))
        ))
        XCTAssertFalse(AlipayCampusCardHandoff.isAllowed(
            try XCTUnwrap(URL(
                string: "alipays://platformapi/startapp?appId=2019090967125695&synjones-auth=secret"
            ))
        ))
        XCTAssertFalse(AlipayCampusCardHandoff.isAllowed(
            try XCTUnwrap(URL(
                string: "alipays://attacker/startapp?appId=2019090967125695"
            ))
        ))
    }
}

final class OfficialPaymentReadOnlyDataSourceTests: XCTestCase {
    override func tearDown() {
        YCardReadOnlyTestURLProtocol.handler = nil
        super.tearDown()
    }

    func testMalformedAndTransportFailuresStayFiniteThenRetrySucceeds() async throws {
        let api = YCardReadOnlyAPIStub(cookies: "[]")
        let configuration = YCardReadOnlyClient.makeConfiguration()
        configuration.protocolClasses = [YCardReadOnlyTestURLProtocol.self]
        let source = OfficialCardRechargeAccountDataSource(
            campusAPI: api,
            configuration: configuration
        )
        let requestCount = YCardReadOnlyLockedBox(0)
        YCardReadOnlyTestURLProtocol.handler = { request in
            let count = requestCount.withValue {
                $0 += 1
                return $0
            }
            if count == 2 {
                throw NSError(
                    domain: "must-not-reach-ui",
                    code: 7,
                    userInfo: [NSLocalizedDescriptionKey: "private upstream body"]
                )
            }
            let data = count == 1
                ? Data(#"{"private":"must-not-leak""#.utf8)
                : Data(#"{"code":200,"success":true,"data":{"card":[{"accinfo":[{"name":"主钱包","type":"01","balance":1234}]}]}}"#.utf8)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!,
                data
            )
        }

        do {
            _ = try await source.load()
            XCTFail("Expected malformed response")
        } catch {
            XCTAssertEqual(error as? YCardReadOnlyError, .invalidResponse)
            XCTAssertFalse(error.localizedDescription.contains("private"))
        }
        do {
            _ = try await source.load()
            XCTFail("Expected unavailable transport")
        } catch {
            XCTAssertEqual(error as? YCardReadOnlyError, .unavailable)
            XCTAssertFalse(error.localizedDescription.contains("upstream"))
        }

        let loadedAccount = try await source.load()
        let account = try XCTUnwrap(loadedAccount)
        XCTAssertEqual(account.name, "主钱包")
        XCTAssertEqual(account.balance, 12.34)
        let tokenRequestCount = await api.tokenRequestCount()
        XCTAssertEqual(tokenRequestCount, 3)
    }
}

@MainActor
final class PaymentReadOnlyViewModelStateTests: XCTestCase {
    func testStaleCardResponseCannotOverwriteNewerResult() async {
        let source = ControllableCardAccountDataSource()
        let model = CardRechargeAccountViewModel(dataSource: source)

        let first = Task { await model.load() }
        await source.waitUntilFirstRequestStarts()
        let second = Task { await model.load() }
        await second.value
        await source.finishFirstRequest()
        await first.value

        guard case let .ready(account) = model.state else {
            return XCTFail("Expected latest card response, got \(model.state)")
        }
        XCTAssertEqual(model.readyAccount, account)
        XCTAssertNoThrow(try model.requireReadyAccount())
        XCTAssertEqual(account.name, "新账户")
        XCTAssertEqual(account.balance, 20)
    }

    func testCardEmptyAndErrorStatesRemainDistinct() async {
        let empty = CardRechargeAccountViewModel(
            dataSource: EmptyCardAccountDataSource()
        )
        await empty.load()
        XCTAssertEqual(empty.state, .empty)
        XCTAssertNil(empty.readyAccount)
        XCTAssertThrowsError(try empty.requireReadyAccount()) { error in
            XCTAssertEqual(error as? PaymentValidationError, .missingAccount)
        }

        let failed = CardRechargeAccountViewModel(
            dataSource: FailingCardAccountDataSource()
        )
        await failed.load()
        XCTAssertEqual(
            failed.state,
            .failed(YCardReadOnlyError.unavailable.localizedDescription)
        )
        XCTAssertNil(failed.readyAccount)
    }

    func testUnknownFailureNeverReachesUIAndRetryCanRecover() async {
        let source = RetryingUnknownCardAccountDataSource()
        let model = CardRechargeAccountViewModel(dataSource: source)

        await model.load()
        XCTAssertEqual(
            model.state,
            .failed(YCardReadOnlyError.unavailable.localizedDescription)
        )
        if case let .failed(message) = model.state {
            XCTAssertFalse(message.contains("private upstream body"))
        }

        await model.load()
        guard case let .ready(account) = model.state else {
            return XCTFail("Expected retry to recover, got \(model.state)")
        }
        XCTAssertEqual(account.name, "重试成功")
    }

    func testStaleBathroomResponseCannotOverwriteNewerResult() async {
        let source = ControllableBathroomAccountDataSource()
        let model = BathroomAccountViewModel(dataSource: source)

        let first = Task {
            await model.lookup(
                bathroomName: "竹园/龙河",
                phone: "13800000000"
            )
        }
        await source.waitUntilFirstRequestStarts()
        let second = Task {
            await model.lookup(
                bathroomName: "竹园/龙河",
                phone: "13900000000"
            )
        }
        await second.value
        await source.finishFirstRequest()
        await first.value

        guard case let .ready(account) = model.state else {
            return XCTFail("Expected latest bathroom response, got \(model.state)")
        }
        XCTAssertEqual(account.phone, "13900000000")
        XCTAssertEqual(account.cashBalance, 20)
        XCTAssertEqual(
            model.thirdPartyJSON,
            Data(#"{"revision":"new"}"#.utf8)
        )
    }

    func testBathroomEmptyAndErrorStatesRemainDistinct() async {
        let empty = BathroomAccountViewModel(
            dataSource: EmptyBathroomAccountDataSource()
        )
        await empty.lookup(
            bathroomName: "竹园/龙河",
            phone: "13800000000"
        )
        XCTAssertEqual(empty.state, .empty("未查询到浴室账户"))
        XCTAssertNil(empty.thirdPartyJSON)

        let failed = BathroomAccountViewModel(
            dataSource: FailingBathroomAccountDataSource()
        )
        await failed.lookup(
            bathroomName: "竹园/龙河",
            phone: "13800000000"
        )
        XCTAssertEqual(
            failed.state,
            .failed(YCardReadOnlyError.unavailable.localizedDescription)
        )
        XCTAssertNil(failed.thirdPartyJSON)
    }

    func testBathroomResetImmediatelyDropsPaymentContext() async {
        let model = BathroomAccountViewModel(
            dataSource: ContextBathroomAccountDataSource()
        )

        await model.lookup(
            bathroomName: "竹园/龙河",
            phone: "13800000000"
        )
        XCTAssertNotNil(model.thirdPartyJSON)

        model.reset()

        XCTAssertEqual(model.state, .idle)
        XCTAssertNil(model.thirdPartyJSON)
    }
}

@MainActor
final class ElectricityAccountViewModelTests: XCTestCase {
    func testStaleBuildingResponseCannotOverwriteNewCampusSelection() async throws {
        let source = ControllableElectricityAccountDataSource()
        let model = ElectricityAccountViewModel(dataSource: source)
        await model.load()

        let firstRequest = try XCTUnwrap(
            model.selectCampus(named: "校区 A")
        )
        await source.waitUntilFirstBuildingRequestStarts()
        let latestRequest = try XCTUnwrap(
            model.selectCampus(named: "校区 B")
        )
        await latestRequest.value
        XCTAssertEqual(model.selectedCampus?.name, "校区 B")
        XCTAssertEqual(model.buildings.map(\.name), ["B 楼"])
        XCTAssertFalse(model.isLoading)

        await source.finishFirstBuildingRequest()
        await firstRequest.value
        XCTAssertEqual(model.selectedCampus?.name, "校区 B")
        XCTAssertEqual(model.buildings.map(\.name), ["B 楼"])
        XCTAssertFalse(model.isLoading)
    }

    func testRoomPaymentContextFollowsSelectionAndClearsOnAncestorChange() async throws {
        let model = ElectricityAccountViewModel(
            dataSource: ContextElectricityAccountDataSource()
        )
        await model.load()

        await model.selectCampus(named: "校区 A")?.value
        model.selectBuilding(named: "A 楼")
        try await waitUntil { !model.floors.isEmpty }
        model.selectFloor(named: "3 层")
        try await waitUntil { !model.rooms.isEmpty }
        model.selectRoom(named: "305")
        try await waitUntil { model.selectedRoom != nil }

        XCTAssertEqual(
            model.selectedRoomThirdPartyJSON,
            Data(#"{"revision":"room-305"}"#.utf8)
        )

        await model.selectCampus(named: "校区 A")?.value
        XCTAssertNil(model.selectedRoom)
        XCTAssertNil(model.selectedRoomThirdPartyJSON)
    }

    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for electricity selection state")
    }
}

private actor ControllableCardAccountDataSource:
    CardRechargeAccountDataSource
{
    private var requestCount = 0
    private var firstRequestContinuation:
        CheckedContinuation<CardRechargeAccountSnapshot?, Never>?
    private var firstRequestStarted = false
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []

    func load() async throws -> CardRechargeAccountSnapshot? {
        requestCount += 1
        guard requestCount == 1 else {
            return CardRechargeAccountSnapshot(
                id: "new",
                name: "新账户",
                type: "02",
                balance: 20
            )
        }
        firstRequestStarted = true
        let waiters = firstRequestWaiters
        firstRequestWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstRequestContinuation = continuation
        }
    }

    func waitUntilFirstRequestStarts() async {
        guard !firstRequestStarted else { return }
        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func finishFirstRequest() {
        firstRequestContinuation?.resume(returning: CardRechargeAccountSnapshot(
            id: "old",
            name: "旧账户",
            type: "01",
            balance: 10
        ))
        firstRequestContinuation = nil
    }
}

private struct EmptyCardAccountDataSource: CardRechargeAccountDataSource {
    func load() async throws -> CardRechargeAccountSnapshot? {
        nil
    }
}

private struct FailingCardAccountDataSource: CardRechargeAccountDataSource {
    func load() async throws -> CardRechargeAccountSnapshot? {
        throw YCardReadOnlyError.unavailable
    }
}

private actor RetryingUnknownCardAccountDataSource:
    CardRechargeAccountDataSource
{
    private var requestCount = 0

    func load() async throws -> CardRechargeAccountSnapshot? {
        requestCount += 1
        guard requestCount > 1 else {
            throw NSError(
                domain: "must-not-reach-ui",
                code: 8,
                userInfo: [
                    NSLocalizedDescriptionKey: "private upstream body"
                ]
            )
        }
        return CardRechargeAccountSnapshot(
            id: "retry",
            name: "重试成功",
            type: "01",
            balance: 20
        )
    }
}

private actor ControllableBathroomAccountDataSource:
    BathroomAccountDataSource
{
    private var requestCount = 0
    private var firstRequestContinuation:
        CheckedContinuation<BathroomLookupResult, Never>?
    private var firstRequestStarted = false
    private var firstRequestWaiters: [CheckedContinuation<Void, Never>] = []

    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult {
        requestCount += 1
        guard requestCount == 1 else {
            return BathroomLookupResult(
                account: BathroomPaymentAccount(
                    id: "new",
                    name: bathroomName,
                    phone: phone,
                    cashBalance: 20,
                    giftBalance: 2
                ),
                message: nil,
                thirdPartyJSON: Data(#"{"revision":"new"}"#.utf8)
            )
        }
        firstRequestStarted = true
        let waiters = firstRequestWaiters
        firstRequestWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstRequestContinuation = continuation
        }
    }

    func waitUntilFirstRequestStarts() async {
        guard !firstRequestStarted else { return }
        await withCheckedContinuation { continuation in
            firstRequestWaiters.append(continuation)
        }
    }

    func finishFirstRequest() {
        firstRequestContinuation?.resume(returning: BathroomLookupResult(
            account: BathroomPaymentAccount(
                id: "old",
                name: "竹园/龙河",
                phone: "13800000000",
                cashBalance: 10,
                giftBalance: 1
            ),
            message: nil,
            thirdPartyJSON: Data(#"{"revision":"old"}"#.utf8)
        ))
        firstRequestContinuation = nil
    }
}

private struct EmptyBathroomAccountDataSource: BathroomAccountDataSource {
    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult {
        BathroomLookupResult(account: nil, message: nil)
    }
}

private struct FailingBathroomAccountDataSource: BathroomAccountDataSource {
    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult {
        throw YCardReadOnlyError.unavailable
    }
}

private struct ContextBathroomAccountDataSource: BathroomAccountDataSource {
    func lookup(
        bathroomName: String,
        phone: String
    ) async throws -> BathroomLookupResult {
        BathroomLookupResult(
            account: BathroomPaymentAccount(
                id: "bathroom-account",
                name: bathroomName,
                phone: phone,
                cashBalance: 20,
                giftBalance: 2
            ),
            message: nil,
            thirdPartyJSON: Data(#"{"revision":"current"}"#.utf8)
        )
    }
}

private struct ContextElectricityAccountDataSource: ElectricityAccountDataSource {
    func campuses() async throws -> [YCardSelectionOption] {
        [YCardSelectionOption(name: "校区 A", value: "campus-a")]
    }

    func buildings(
        campus: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        [YCardSelectionOption(name: "A 楼", value: "building-a")]
    }

    func floors(
        campus: YCardSelectionOption,
        building: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        [YCardSelectionOption(name: "3 层", value: "floor-3")]
    }

    func rooms(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        [YCardSelectionOption(name: "305", value: "room-305")]
    }

    func room(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) async throws -> ElectricityRoomLookupResult {
        ElectricityRoomLookupResult(
            room: ElectricityRoom(
                id: "electricity-account",
                campus: campus.name,
                building: building.name,
                floor: floor.name,
                room: room.name,
                balance: 12.34,
                information: "房间状态正常"
            ),
            thirdPartyJSON: Data(#"{"revision":"room-305"}"#.utf8)
        )
    }

    func clearCredentials() async { }
}

private actor ControllableElectricityAccountDataSource:
    ElectricityAccountDataSource
{
    private var firstBuildingContinuation:
        CheckedContinuation<[YCardSelectionOption], Never>?
    private var firstBuildingRequestStarted = false
    private var firstBuildingStartWaiters:
        [CheckedContinuation<Void, Never>] = []

    func campuses() async throws -> [YCardSelectionOption] {
        [
            YCardSelectionOption(name: "校区 A", value: "campus-a"),
            YCardSelectionOption(name: "校区 B", value: "campus-b")
        ]
    }

    func buildings(
        campus: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        guard campus.value == "campus-a" else {
            return [YCardSelectionOption(name: "B 楼", value: "building-b")]
        }
        firstBuildingRequestStarted = true
        let waiters = firstBuildingStartWaiters
        firstBuildingStartWaiters.removeAll(keepingCapacity: false)
        waiters.forEach { $0.resume() }
        return await withCheckedContinuation { continuation in
            firstBuildingContinuation = continuation
        }
    }

    func floors(
        campus: YCardSelectionOption,
        building: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        []
    }

    func rooms(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption
    ) async throws -> [YCardSelectionOption] {
        []
    }

    func room(
        campus: YCardSelectionOption,
        building: YCardSelectionOption,
        floor: YCardSelectionOption,
        room: YCardSelectionOption
    ) async throws -> ElectricityRoomLookupResult {
        throw YCardReadOnlyError.unavailable
    }

    func clearCredentials() async { }

    func waitUntilFirstBuildingRequestStarts() async {
        guard !firstBuildingRequestStarted else { return }
        await withCheckedContinuation { continuation in
            firstBuildingStartWaiters.append(continuation)
        }
    }

    func finishFirstBuildingRequest() {
        firstBuildingContinuation?.resume(
            returning: [
                YCardSelectionOption(name: "A 楼（旧响应）", value: "building-a")
            ]
        )
        firstBuildingContinuation = nil
    }
}

private final class YCardReadOnlyTestURLProtocol:
    URLProtocol,
    @unchecked Sendable
{
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let handlerBox = YCardReadOnlyLockedBox<Handler?>(nil)

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

private final class YCardReadOnlyLockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValue: Value

    init(_ value: Value) {
        storedValue = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storedValue
    }

    func set(_ value: Value) {
        lock.lock()
        storedValue = value
        lock.unlock()
    }

    @discardableResult
    func withValue<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&storedValue)
    }
}

private actor YCardReadOnlyAPIStub: CampusCoreAPI {
    private var cookies: String
    private var tokenRequests = 0
    private var refreshes = 0

    init(cookies: String) {
        self.cookies = cookies
    }

    func initialize(cookiesJSON: String) {
        cookies = cookiesJSON
    }

    func login(studentID: String, password: String) throws -> User {
        throw CampusCoreError.invalidResponse
    }

    func dumpCookies() -> String { cookies }
    func cookiesFlat() -> String { cookies }
    func schedule() throws -> [Course] { throw CampusCoreError.invalidResponse }
    func currentWeek() throws -> Int { throw CampusCoreError.invalidResponse }
    func exams() throws -> [CampusExam] { throw CampusCoreError.invalidResponse }
    func grades() throws -> CampusGradeReport {
        throw CampusCoreError.invalidResponse
    }
    func cardBalance() throws -> Double { throw CampusCoreError.invalidResponse }
    func cardQRCode() throws -> String { throw CampusCoreError.invalidResponse }

    func cardAccessToken() -> String {
        tokenRequests += 1
        return "temporary-token-\(tokenRequests)"
    }

    func testYCardLoginHTMLRefreshesOnceAndSecondRejectionStops() async throws {
        for secondStatus in [200, 401] {
            let api = YCardReadOnlyAPIStub(cookies: "[]")
            let configuration = YCardReadOnlyClient.makeConfiguration()
            configuration.protocolClasses = [YCardReadOnlyTestURLProtocol.self]
            let client = YCardReadOnlyClient(
                campusAPI: api,
                configuration: configuration,
                refreshCoordinator: SessionRefreshCoordinator()
            )
            let requestCount = YCardReadOnlyLockedBox(0)
            YCardReadOnlyTestURLProtocol.handler = { request in
                let count = requestCount.withValue {
                    $0 += 1
                    return $0
                }
                if count == 1 {
                    return (
                        HTTPURLResponse(
                            url: request.url!,
                            statusCode: 200,
                            httpVersion: "HTTP/1.1",
                            headerFields: ["Content-Type": "text/html"]
                        )!,
                        Data(#"<html><form id="loginForm"><input name="username"><input name="password"></form></html>"#.utf8)
                    )
                }
                return (
                    HTTPURLResponse(
                        url: request.url!,
                        statusCode: secondStatus,
                        httpVersion: "HTTP/1.1",
                        headerFields: nil
                    )!,
                    Data("ok".utf8)
                )
            }

            if secondStatus == 200 {
                let data = try await client.request(
                    .cardAccount,
                    queryItems: YCardReadOnlyContract.cardAccountQuery
                )
                XCTAssertEqual(String(decoding: data, as: UTF8.self), "ok")
            } else {
                do {
                    _ = try await client.request(
                        .cardAccount,
                        queryItems: YCardReadOnlyContract.cardAccountQuery
                    )
                    XCTFail("Expected second token rejection to stop")
                } catch {
                    XCTAssertEqual(error as? YCardReadOnlyError, .credentialsUnavailable)
                }
            }
            XCTAssertEqual(requestCount.value, 2)
            let refreshCount = await api.refreshCount()
            XCTAssertEqual(refreshCount, 1)
        }
    }

    func refreshSession() {
        refreshes += 1
        cookies = "[]"
    }

    func setCookies(_ value: String) {
        cookies = value
    }

    func tokenRequestCount() -> Int { tokenRequests }
    func refreshCount() -> Int { refreshes }
}
