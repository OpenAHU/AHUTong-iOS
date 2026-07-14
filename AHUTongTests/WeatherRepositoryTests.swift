import Foundation
import XCTest
@testable import AHUTong

final class WeatherRepositoryTests: XCTestCase {
    @MainActor
    func testRemoteDecodesCurrentForecastHourlyAQIAndIndices() async throws {
        let transport = WeatherRecordingTransport(data: Self.fixtureData)
        let remote = UAPIsWeatherRemote(transport: transport)

        let weather = try await remote.fetchWeather(query: .city(" 合肥 "))
        let request = await transport.lastRequest
        let queryItems = URLComponents(
            url: try XCTUnwrap(request?.url),
            resolvingAgainstBaseURL: false
        )?.queryItems ?? []

        XCTAssertEqual(weather.locationName, "蜀山区")
        XCTAssertEqual(weather.temperature, 29)
        XCTAssertEqual(weather.forecast?.first?.weatherDay, "小雨")
        XCTAssertEqual(weather.hourlyForecast?.first?.feelsLike, 35)
        XCTAssertEqual(weather.aqiCategory, "优")
        XCTAssertEqual(weather.lifeIndices?.umbrella?.level, "建议备伞")
        XCTAssertEqual(queryItems.first(where: { $0.name == "city" })?.value, "合肥")
        XCTAssertEqual(queryItems.first(where: { $0.name == "hourly" })?.value, "true")
    }

    @MainActor
    func testIPQueryDoesNotSendCityOrAdcode() async throws {
        let transport = WeatherRecordingTransport(data: Self.fixtureData)
        let remote = UAPIsWeatherRemote(transport: transport)

        _ = try await remote.fetchWeather(query: .ip)
        let request = await transport.lastRequest
        let names = Set(
            URLComponents(url: try XCTUnwrap(request?.url), resolvingAgainstBaseURL: false)?
                .queryItems?.map(\.name) ?? []
        )

        XCTAssertFalse(names.contains("city"))
        XCTAssertFalse(names.contains("adcode"))
        XCTAssertTrue(names.contains("forecast"))
    }

    @MainActor
    func testRemoteRejectsBlankCityAndMeaninglessPayload() async {
        let blankRemote = UAPIsWeatherRemote(
            transport: WeatherRecordingTransport(data: Self.fixtureData)
        )
        do {
            _ = try await blankRemote.fetchWeather(query: .city(" \n"))
            XCTFail("Expected blank city rejection")
        } catch {
            XCTAssertEqual(error as? WeatherError, .blankCity)
        }

        let emptyRemote = UAPIsWeatherRemote(
            transport: WeatherRecordingTransport(data: Data("{}".utf8))
        )
        do {
            _ = try await emptyRemote.fetchWeather(query: .ip)
            XCTFail("Expected invalid weather payload")
        } catch {
            XCTAssertEqual(error as? WeatherError, .invalidPayload)
        }
    }

    @MainActor
    func testRepositoryFallsBackOnlyToMatchingQueryCache() async throws {
        let remote = WeatherRemoteStub(response: Self.fixture)
        let repository = WeatherRepository(remote: remote, cache: InMemoryDataStore())
        _ = try await repository.load(query: .city("合肥"))
        await remote.setShouldFail(true)

        let cached = try await repository.load(query: .city("合肥"))
        XCTAssertEqual(cached.source, .staleCache)
        XCTAssertEqual(cached.response.city, "合肥市")

        do {
            _ = try await repository.load(query: .city("北京"))
            XCTFail("Another city's cache must not be reused")
        } catch is WeatherRemoteStub.Failure {
            XCTAssertTrue(true)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    @MainActor
    func testDisplayPreferencesRoundTripAndRecoverCorruption() async throws {
        let dataStore = InMemoryDataStore()
        let store = WeatherPreferencesStore(store: dataStore)
        var expected = WeatherDisplayPreferences()
        expected.showAirQuality = false
        expected.showHourlyForecast = false
        try await store.save(expected)
        let saved = await store.load()

        XCTAssertEqual(saved, expected)

        try await dataStore.set(Data("broken".utf8), forKey: "weather.display-preferences.v1")
        let recovered = await store.load()
        XCTAssertEqual(recovered, WeatherDisplayPreferences())
    }

    @MainActor
    func testDeniedGPSFallsBackToIPAndSettingsAffectModel() async {
        let remote = WeatherRemoteStub(response: Self.fixture)
        let model = WeatherViewModel(
            repository: WeatherRepository(remote: remote, cache: InMemoryDataStore()),
            preferencesStore: WeatherPreferencesStore(store: InMemoryDataStore()),
            locationProvider: WeatherLocationStub(error: .locationPermissionDenied)
        )

        await model.useCurrentLocation()
        model.setPreference(.airQuality, enabled: false)
        let queries = await remote.queries

        XCTAssertEqual(queries, [.ip])
        XCTAssertEqual(model.state.value?.response.city, "合肥市")
        XCTAssertTrue(model.notice?.contains("IP 定位") == true)
        XCTAssertFalse(model.preferences.showAirQuality)
    }

    private static let fixtureData = Data(
        #"""
        {
          "province":"安徽省","city":"合肥市","district":"蜀山区","adcode":"340104",
          "weather":"雾","weather_icon":"500","temperature":29,"wind_direction":"东南风",
          "wind_power":"1级","humidity":99,"report_time":"8 分钟前发布","feels_like":35,
          "visibility":5,"pressure":1002,"uv":6,"precipitation":0.2,"cloud":94,
          "aqi":26,"aqi_level":1,"aqi_category":"优","aqi_primary":"无",
          "air_pollutants":{"pm25":18,"pm10":26,"o3":48,"no2":12,"so2":4,"co":0.5},
          "temp_max":33,"temp_min":26,
          "forecast":[{"date":"2026-07-14","week":"星期二","temp_max":33,"temp_min":26,"weather_day":"小雨","weather_night":"晴","wind_dir_day":"东南风","wind_scale_day":"2级","humidity":82,"precip":0.2,"pop":60,"uv_index":6,"sunrise":"05:15","sunset":"19:18"}],
          "hourly_forecast":[{"time":"2026-07-14 08:10:08","temperature":29,"weather":"雾","wind_direction":"东南风","wind_speed":4,"wind_scale":"1级","humidity":99,"feels_like":35,"visibility":5}],
          "life_indices":{"clothing":{"level":"炎热","brief":"极热","advice":"穿清凉夏装"},"uv":{"level":"高","brief":"较强","advice":"注意防晒"},"umbrella":{"level":"建议备伞","brief":"小雨","advice":"随身备伞"}}
        }
        """#.utf8
    )

    private static var fixture: WeatherResponse {
        try! JSONDecoder().decode(WeatherResponse.self, from: fixtureData)
    }
}

private actor WeatherRecordingTransport: NetworkTransport {
    let data: Data
    private(set) var lastRequest: URLRequest?

    init(data: Data) { self.data = data }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        lastRequest = request
        return (
            data,
            HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
        )
    }
}

private actor WeatherRemoteStub: WeatherRemoteDataSource {
    enum Failure: Error { case unavailable }

    let response: WeatherResponse
    private(set) var queries: [WeatherQuery] = []
    private var shouldFail = false

    init(response: WeatherResponse) { self.response = response }

    func fetchWeather(query: WeatherQuery) async throws -> WeatherResponse {
        queries.append(query)
        if shouldFail { throw Failure.unavailable }
        return response
    }

    func setShouldFail(_ value: Bool) { shouldFail = value }
}

@MainActor
private final class WeatherLocationStub: WeatherLocationProviding {
    let error: WeatherError
    init(error: WeatherError) { self.error = error }
    func requestCity() async throws -> String { throw error }
}
