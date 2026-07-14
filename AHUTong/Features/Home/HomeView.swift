import SwiftUI

struct HomeView: View {
    @StateObject private var weatherModel = WeatherViewModel()

    var body: some View {
        AndroidScreen {
            ScrollView {
                LazyVStack(spacing: 24) {
                    atAGlance

                    if case let .loaded(snapshot) = weatherModel.state {
                        NavigationLink {
                            WeatherView()
                                .androidDetailScreen()
                        } label: {
                            HomeWeatherCard(weather: snapshot.response)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("home.weather")
                    }
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .task { await weatherModel.start() }
        .accessibilityIdentifier("screen.home")
    }

    private var atAGlance: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text(Self.dateFormatter.string(from: Date()))
                .font(.body)
                .padding(.leading, 32)
                .padding(.trailing, 16)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text("今日课程")
                    .font(.body)
                    .fontWeight(.bold)
                Text("已全部上完")
                    .font(.system(size: 40, weight: .bold))
                    .lineLimit(2)
                Text("准备您自己的安排吧")
                    .font(.body)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 32)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd / EE"
        return formatter
    }()
}

private struct HomeWeatherCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let weather: WeatherResponse

    var body: some View {
        AndroidCard(
            radius: 20,
            background: AndroidParityPalette.primaryContainer(colorScheme)
        ) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weather.locationName)
                        .font(.caption)
                        .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                    HStack(alignment: .bottom, spacing: 8) {
                        Text(homeTemperature(weather.temperature))
                            .font(.system(size: 32, weight: .light))
                        Text(weather.weather ?? "")
                            .font(.body)
                    }
                    if weather.windDirection != nil || weather.windPower != nil {
                        Text("\(windArrow) \(weather.windDirection ?? "") \(weather.windPower ?? "")")
                            .font(.caption)
                            .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                    }
                    if let aqi = weather.aqi {
                        Text("\(airQualityDot) 空气\(aqi) \(weather.aqiCategory ?? "")")
                            .font(.caption2)
                            .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if rainPossible {
                    VStack(spacing: 2) {
                        Text("☔").font(.system(size: 24))
                        Text(maxPrecipitation > 0 ? "\(maxPrecipitation)%" : "--")
                            .font(.system(size: 16, weight: .bold))
                        Text(rainLabel)
                            .font(.system(size: 12))
                            .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                    }
                }
            }
            .padding(16)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 4)
    }

    private var rainPossible: Bool {
        let keywords = ["雨", "雪", "雹"]
        let values = [weather.weather]
            + [weather.forecast?.first?.weatherDay, weather.forecast?.first?.weatherNight]
            + Array((weather.hourlyForecast ?? []).prefix(6).map(\.weather))
        return values.compactMap { $0 }.contains { value in
            keywords.contains { value.contains($0) }
        }
    }

    private var maxPrecipitation: Int {
        weather.hourlyForecast?.prefix(6).compactMap(\.probabilityOfPrecipitation).max() ?? 0
    }

    private var rainLabel: String {
        switch maxPrecipitation {
        case 60...: "务必带伞"
        case 40...: "建议带伞"
        case 1...: "可能降雨"
        default: "带伞"
        }
    }

    private var airQualityDot: String {
        switch weather.aqiLevel {
        case 1: "🟢"
        case 2: "🟡"
        case 3: "🟠"
        case 4: "🔴"
        case 5: "🟣"
        default: "⚪"
        }
    }

    private var windArrow: String {
        switch weather.windDirection {
        case "北风": "↓"
        case "南风": "↑"
        case "东风": "←"
        case "西风": "→"
        case "东北风": "↙"
        case "西北风": "↘"
        case "东南风": "↖"
        case "西南风": "↗"
        default: "↘"
        }
    }
}

private func homeTemperature(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))°" } ?? "--"
}
