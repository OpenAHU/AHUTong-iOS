import Foundation

struct WeatherResponse: Codable, Equatable, Sendable {
    let province: String?
    let city: String?
    let district: String?
    let adcode: String?
    let weather: String?
    let weatherIcon: String?
    let weatherCode: String?
    let temperature: Double?
    let windDirection: String?
    let windPower: String?
    let humidity: Int?
    let reportTime: String?
    let feelsLike: Double?
    let visibility: Double?
    let pressure: Double?
    let ultraviolet: Double?
    let precipitation: Double?
    let cloud: Int?
    let aqi: Int?
    let aqiLevel: Int?
    let aqiCategory: String?
    let aqiPrimary: String?
    let airPollutants: WeatherAirPollutants?
    let alerts: [WeatherAlert]?
    let tempMax: Double?
    let tempMin: Double?
    let forecast: [WeatherForecastDay]?
    let hourlyForecast: [WeatherHourlyForecast]?
    let lifeIndices: WeatherLifeIndices?

    enum CodingKeys: String, CodingKey {
        case province, city, district, adcode, weather, temperature, humidity
        case visibility, pressure, precipitation, cloud, aqi, alerts, forecast
        case weatherIcon = "weather_icon"
        case weatherCode = "weather_code"
        case windDirection = "wind_direction"
        case windPower = "wind_power"
        case reportTime = "report_time"
        case feelsLike = "feels_like"
        case ultraviolet = "uv"
        case aqiLevel = "aqi_level"
        case aqiCategory = "aqi_category"
        case aqiPrimary = "aqi_primary"
        case airPollutants = "air_pollutants"
        case tempMax = "temp_max"
        case tempMin = "temp_min"
        case hourlyForecast = "hourly_forecast"
        case lifeIndices = "life_indices"
    }

    var locationName: String {
        [district, city, province]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty }) ?? "未知位置"
    }

    var isMeaningful: Bool {
        temperature != nil || weather != nil || city != nil || district != nil
    }
}

struct WeatherAirPollutants: Codable, Equatable, Sendable {
    let pm25: Double?
    let pm10: Double?
    let o3: Double?
    let no2: Double?
    let so2: Double?
    let co: Double?
}

struct WeatherAlert: Codable, Equatable, Identifiable, Sendable {
    let title: String?
    let type: String?
    let level: String?
    let text: String?
    let publishTime: String?
    let publisher: String?
    let guidance: [String]?

    var id: String { "\(title ?? type ?? "预警")-\(publishTime ?? "")" }

    enum CodingKeys: String, CodingKey {
        case title, type, level, text, publisher, guidance
        case publishTime = "publish_time"
    }
}

struct WeatherForecastDay: Codable, Equatable, Identifiable, Sendable {
    let date: String?
    let week: String?
    let tempMax: Double?
    let tempMin: Double?
    let weatherDay: String?
    let weatherNight: String?
    let windDirectionDay: String?
    let windScaleDay: String?
    let humidity: Int?
    let precipitation: Double?
    let probabilityOfPrecipitation: Int?
    let ultravioletIndex: Int?
    let sunrise: String?
    let sunset: String?

    var id: String { date ?? "\(week ?? "unknown")-\(weatherDay ?? "")" }

    enum CodingKeys: String, CodingKey {
        case date, week, humidity, sunrise, sunset
        case tempMax = "temp_max"
        case tempMin = "temp_min"
        case weatherDay = "weather_day"
        case weatherNight = "weather_night"
        case windDirectionDay = "wind_dir_day"
        case windScaleDay = "wind_scale_day"
        case precipitation = "precip"
        case probabilityOfPrecipitation = "pop"
        case ultravioletIndex = "uv_index"
    }
}

struct WeatherHourlyForecast: Codable, Equatable, Identifiable, Sendable {
    let time: String?
    let temperature: Double?
    let weather: String?
    let windDirection: String?
    let windSpeed: Double?
    let windScale: String?
    let humidity: Int?
    let precipitation: Double?
    let feelsLike: Double?
    let visibility: Double?
    let probabilityOfPrecipitation: Int?
    let ultravioletIndex: Int?

    var id: String { time ?? "\(weather ?? "unknown")-\(temperature ?? 0)" }

    enum CodingKeys: String, CodingKey {
        case time, temperature, weather, humidity, visibility
        case windDirection = "wind_direction"
        case windSpeed = "wind_speed"
        case windScale = "wind_scale"
        case precipitation = "precip"
        case feelsLike = "feels_like"
        case probabilityOfPrecipitation = "pop"
        case ultravioletIndex = "uv_index"
    }
}

struct WeatherLifeIndexItem: Codable, Equatable, Sendable {
    let level: String?
    let brief: String?
    let advice: String?
}

struct WeatherLifeIndices: Codable, Equatable, Sendable {
    let clothing: WeatherLifeIndexItem?
    let ultraviolet: WeatherLifeIndexItem?
    let carWash: WeatherLifeIndexItem?
    let drying: WeatherLifeIndexItem?
    let coldRisk: WeatherLifeIndexItem?
    let exercise: WeatherLifeIndexItem?
    let comfort: WeatherLifeIndexItem?
    let travel: WeatherLifeIndexItem?
    let allergy: WeatherLifeIndexItem?
    let sunscreen: WeatherLifeIndexItem?
    let umbrella: WeatherLifeIndexItem?
    let traffic: WeatherLifeIndexItem?

    enum CodingKeys: String, CodingKey {
        case clothing, drying, exercise, comfort, travel, allergy, sunscreen, umbrella, traffic
        case ultraviolet = "uv"
        case carWash = "car_wash"
        case coldRisk = "cold_risk"
    }

    var displayItems: [WeatherLifeIndexDisplayItem] {
        let values: [(String, WeatherLifeIndexItem?)] = [
            ("穿衣", clothing), ("紫外线", ultraviolet), ("洗车", carWash),
            ("晾晒", drying), ("感冒", coldRisk), ("运动", exercise),
            ("舒适度", comfort), ("出行", travel), ("过敏", allergy),
            ("防晒", sunscreen), ("雨伞", umbrella), ("交通", traffic)
        ]
        return values.compactMap { title, item in
            item.map { WeatherLifeIndexDisplayItem(title: title, item: $0) }
        }
    }
}

struct WeatherLifeIndexDisplayItem: Identifiable, Sendable {
    let title: String
    let item: WeatherLifeIndexItem
    var id: String { title }
}

enum WeatherQuery: Equatable, Sendable {
    case ip
    case city(String)
    case adcode(String)

    var cacheKey: String {
        switch self {
        case .ip: "ip"
        case let .city(city): "city.\(city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
        case let .adcode(adcode): "adcode.\(adcode)"
        }
    }
}

enum WeatherSnapshotSource: String, Equatable, Sendable {
    case remote
    case staleCache
}

struct WeatherSnapshot: Equatable, Sendable {
    let response: WeatherResponse
    let source: WeatherSnapshotSource
    let updatedAt: Date
}

struct WeatherDisplayPreferences: Codable, Equatable, Sendable {
    var showLocation = true
    var showTemperature = true
    var showCondition = true
    var showAirQuality = true
    var showHourlyForecast = true
    var showLifeIndices = true
}

enum WeatherHomeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case detailed
    case compact

    var id: String { rawValue }
    var title: String { self == .detailed ? "详细" : "精简" }

    static func resolve(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .detailed
    }
}

struct WeatherHomeConfiguration: Codable, Equatable, Sendable {
    var showOnHome = false
    var mode = WeatherHomeMode.detailed
    var showLocation = true
    var showTemperature = true
    var showCondition = true
    var showAirQuality = true
}

enum WeatherError: Error, Equatable, Sendable {
    case blankCity
    case invalidPayload
    case locationPermissionDenied
    case locationUnavailable
}
