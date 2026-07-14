import Foundation

protocol WeatherRemoteDataSource: Sendable {
    func fetchWeather(query: WeatherQuery) async throws -> WeatherResponse
}

struct UAPIsWeatherRemote: WeatherRemoteDataSource {
    static let endpoint = URL(string: "https://uapis.cn/api/v1/misc/weather")!

    private let transport: any NetworkTransport

    init(transport: any NetworkTransport = URLSessionTransport()) {
        self.transport = transport
    }

    func fetchWeather(query: WeatherQuery) async throws -> WeatherResponse {
        guard var components = URLComponents(
            url: Self.endpoint,
            resolvingAgainstBaseURL: false
        ) else {
            throw NetworkError.invalidURL
        }

        var queryItems = [
            URLQueryItem(name: "extended", value: "true"),
            URLQueryItem(name: "indices", value: "true"),
            URLQueryItem(name: "forecast", value: "true"),
            URLQueryItem(name: "hourly", value: "true"),
            URLQueryItem(name: "lang", value: "zh")
        ]
        switch query {
        case .ip:
            break
        case let .city(city):
            let normalized = city.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { throw WeatherError.blankCity }
            queryItems.append(URLQueryItem(name: "city", value: normalized))
        case let .adcode(adcode):
            queryItems.append(URLQueryItem(name: "adcode", value: adcode))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw NetworkError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("AHUTong-iOS/0.1", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await transport.data(for: request)
        guard (200..<300).contains(response.statusCode) else {
            throw NetworkError.unacceptableStatusCode(response.statusCode)
        }
        do {
            let weather = try JSONDecoder().decode(WeatherResponse.self, from: data)
            guard weather.isMeaningful else { throw WeatherError.invalidPayload }
            return weather
        } catch let error as WeatherError {
            throw error
        } catch {
            throw NetworkError.decodingFailed
        }
    }
}

private struct WeatherCacheEntry: Codable, Sendable {
    let response: WeatherResponse
    let updatedAt: Date
}

struct WeatherRepository: Sendable {
    private let remote: any WeatherRemoteDataSource
    private let cache: any DataStore

    init(remote: any WeatherRemoteDataSource, cache: any DataStore) {
        self.remote = remote
        self.cache = cache
    }

    static func live() -> WeatherRepository {
        WeatherRepository(remote: UAPIsWeatherRemote(), cache: AppPersistence.migratingFileCache())
    }

    func load(query: WeatherQuery) async throws -> WeatherSnapshot {
        let key = "weather.response.\(query.cacheKey)"
        let cached = await loadCacheRecoveringCorruption(key: key)
        do {
            let response = try await remote.fetchWeather(query: query)
            let entry = WeatherCacheEntry(response: response, updatedAt: Date())
            try await cache.set(JSONEncoder().encode(entry), forKey: key)
            return WeatherSnapshot(
                response: response,
                source: .remote,
                updatedAt: entry.updatedAt
            )
        } catch {
            if let cached {
                return WeatherSnapshot(
                    response: cached.response,
                    source: .staleCache,
                    updatedAt: cached.updatedAt
                )
            }
            throw error
        }
    }

    private func loadCacheRecoveringCorruption(key: String) async -> WeatherCacheEntry? {
        do {
            guard let data = try await cache.data(forKey: key) else { return nil }
            return try JSONDecoder().decode(WeatherCacheEntry.self, from: data)
        } catch {
            try? await cache.removeValue(forKey: key)
            return nil
        }
    }
}

struct WeatherPreferencesStore: Sendable {
    private let store: any DataStore
    private let key = "weather.display-preferences.v1"

    init(store: any DataStore = AppPersistence.migratingDefaults()) {
        self.store = store
    }

    func load() async -> WeatherDisplayPreferences {
        do {
            guard let data = try await store.data(forKey: key) else {
                return WeatherDisplayPreferences()
            }
            return try JSONDecoder().decode(WeatherDisplayPreferences.self, from: data)
        } catch {
            try? await store.removeValue(forKey: key)
            return WeatherDisplayPreferences()
        }
    }

    func save(_ preferences: WeatherDisplayPreferences) async throws {
        try await store.set(JSONEncoder().encode(preferences), forKey: key)
    }
}
