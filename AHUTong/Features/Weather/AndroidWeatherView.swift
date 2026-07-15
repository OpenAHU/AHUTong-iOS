import SwiftUI

struct WeatherView: View {
    @StateObject private var model: WeatherViewModel
    @State private var cityQuery = ""
    @State private var isSearchActive = false
    @State private var showSettings = false

    init(model: @autoclosure @escaping () -> WeatherViewModel = WeatherViewModel()) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                weatherHeader
                stateContent
            }
        }
        .sheet(isPresented: $showSettings) {
            AndroidWeatherSettings(model: model)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .task { await model.start() }
    }

    @ViewBuilder
    private var weatherHeader: some View {
        if isSearchActive {
            HStack(spacing: 0) {
                AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "关闭搜索") {
                    isSearchActive = false
                    cityQuery = ""
                }
                AndroidSearchField(
                    text: $cityQuery,
                    prompt: "输入城市名，如 合肥",
                    onSubmit: search
                )
                AndroidIconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索") {
                    search()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        } else {
            AndroidHeader(title: locationTitle) {
                HStack(spacing: 0) {
                    AndroidIconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索城市") {
                        isSearchActive = true
                    }
                    AndroidIconButton(systemName: "gearshape", accessibilityLabel: "天气设置") {
                        showSettings = true
                    }
                    AndroidIconButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新") {
                        Task { await model.refresh() }
                    }
                }
            }
        }
    }

    private var locationTitle: String {
        model.state.value?.response.locationName ?? "天气"
    }

    @ViewBuilder
    private var stateContent: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        case let .loaded(snapshot):
            weatherContent(snapshot)
        case .empty:
            AndroidEmptyState(text: "暂无天气数据")
            Spacer()
        case let .failed(error):
            VStack(spacing: 16) {
                Text(error.message).foregroundStyle(AndroidParityPalette.error).multilineTextAlignment(.center)
                Button("重试") { Task { await model.refresh() } }.buttonStyle(.borderedProminent)
            }
            .padding(32)
            Spacer()
        }
    }

    private func weatherContent(_ snapshot: WeatherSnapshot) -> some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                if let notice = model.notice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if snapshot.source == .staleCache {
                    Text("网络不可用，正在显示该位置最近一次缓存")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                AndroidWeatherCurrentCard(weather: snapshot.response, preferences: model.preferences)

                if let forecast = snapshot.response.forecast, !forecast.isEmpty {
                    VStack(spacing: 0) {
                        AndroidSectionTitle(title: "未来预报")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(forecast) { AndroidForecastCard(day: $0) }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                if model.preferences.showAirQuality, snapshot.response.aqi != nil {
                    AndroidAirQualityCard(weather: snapshot.response)
                }

                AndroidUmbrellaCard(weather: snapshot.response)

                if model.preferences.showHourlyForecast,
                   let hourly = snapshot.response.hourlyForecast,
                   !hourly.isEmpty {
                    VStack(spacing: 0) {
                        AndroidSectionTitle(title: "逐小时预报")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(hourly.prefix(12))) { AndroidHourlyCard(hour: $0) }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                if model.preferences.showLifeIndices,
                   let indices = snapshot.response.lifeIndices,
                   !indices.displayItems.isEmpty {
                    VStack(spacing: 0) {
                        AndroidSectionTitle(title: "生活指数")
                        LazyVGrid(columns: [GridItem(.flexible(), spacing: 8), GridItem(.flexible())], spacing: 8) {
                            ForEach(indices.displayItems) { AndroidLifeIndexCard(display: $0) }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .scrollIndicators(.hidden)
        .refreshable { await model.refresh() }
    }

    private func search() {
        guard !cityQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isSearchActive = false
        Task { await model.search(city: cityQuery) }
    }
}

private struct AndroidWeatherCurrentCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let weather: WeatherResponse
    let preferences: WeatherDisplayPreferences

    var body: some View {
        AndroidCard(radius: 12, background: AndroidParityPalette.primaryContainer(colorScheme)) {
            VStack(spacing: 0) {
                if preferences.showLocation {
                    Text(weather.locationName).font(.headline)
                    Spacer().frame(height: 8)
                }
                if preferences.showTemperature {
                    Text(androidTemperature(weather.temperature))
                        .font(.system(size: 64, weight: .light))
                }
                if preferences.showCondition {
                    Text(weather.weather ?? "").font(.headline).padding(.top, 4)
                    Text("体感 \(androidTemperature(weather.feelsLike))")
                        .font(.body)
                        .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                        .padding(.top, 2)
                }
                Spacer().frame(height: 16)
                HStack {
                    AndroidWeatherMetric(label: "湿度", value: weather.humidity.map { "\($0)%" } ?? "--")
                    AndroidWeatherMetric(label: "风力", value: weather.windPower ?? "--")
                    AndroidWeatherMetric(label: "能见度", value: weather.visibility.map { "\(Int($0))km" } ?? "--km")
                }
            }
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .accessibilityIdentifier("weather.current")
    }
}

private struct AndroidWeatherMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.body).fontWeight(.medium).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct AndroidForecastCard: View {
    @Environment(\.colorScheme) private var colorScheme
    let day: WeatherForecastDay

    var body: some View {
        AndroidCard(radius: 12) {
            VStack(spacing: 2) {
                Text(day.week ?? "").font(.caption)
                Text(androidTemperature(day.tempMax)).font(.system(size: 18, weight: .bold))
                Text(androidTemperature(day.tempMin)).font(.system(size: 14)).foregroundStyle(.secondary)
                Spacer().frame(height: 4)
                Text(day.weatherDay ?? "").font(.system(size: 12)).lineLimit(1)
            }
            .frame(width: 76)
            .padding(12)
        }
        .frame(width: 100)
    }
}

private struct AndroidAirQualityCard: View {
    let weather: WeatherResponse

    var body: some View {
        AndroidCard {
            HStack(spacing: 12) {
                Text(weather.aqi.map(String.init) ?? "--")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(androidAQIColor(weather.aqiLevel), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text("空气\(weather.aqiCategory ?? "")").fontWeight(.bold)
                    Text("主要污染物：\(weather.aqiPrimary ?? "无")").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
        }
    }
}

private struct AndroidUmbrellaCard: View {
    let weather: WeatherResponse

    var body: some View {
        AndroidCard(background: (needsUmbrella ? Color.blue : AndroidParityPalette.success).opacity(0.15)) {
            HStack(spacing: 12) {
                Text(needsUmbrella ? "☔" : "☀️").font(.system(size: 28))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 16, weight: .bold))
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
        }
    }

    private var nextSix: [WeatherHourlyForecast] {
        Array((weather.hourlyForecast ?? []).prefix(6))
    }
    private var maxProbability: Int { nextSix.compactMap(\.probabilityOfPrecipitation).max() ?? 0 }
    private var needsUmbrella: Bool {
        let values = [weather.weather, weather.forecast?.first?.weatherDay, weather.forecast?.first?.weatherNight] + nextSix.map(\.weather)
        return values.compactMap { $0 }.contains { value in ["雨", "雪", "雹"].contains { value.contains($0) } }
    }
    private var title: String {
        if !needsUmbrella { return "无需雨伞" }
        if maxProbability >= 60 { return "务必带伞 ☔" }
        if maxProbability >= 40 { return "建议带伞 ☔" }
        if maxProbability > 0 { return "可能降雨 ☔" }
        return "建议带伞 ☔"
    }
    private var subtitle: String {
        if !needsUmbrella { return "当前及短期预报无降水" }
        if maxProbability > 0 { return "未来6小时降雨概率 \(maxProbability)%" }
        return "当前天气或预报有降雨"
    }
}

private struct AndroidHourlyCard: View {
    let hour: WeatherHourlyForecast

    var body: some View {
        AndroidCard {
            VStack(spacing: 2) {
                Text(androidHourLabel(hour.time)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                Spacer().frame(height: 4)
                Text(androidTemperature(hour.temperature)).font(.system(size: 15, weight: .bold))
                Spacer().frame(height: 2)
                Text(hour.weather ?? "").font(.system(size: 11)).lineLimit(1)
            }
            .frame(width: 72)
            .padding(8)
        }
        .frame(width: 88)
    }
}

private struct AndroidLifeIndexCard: View {
    let display: WeatherLifeIndexDisplayItem

    var body: some View {
        AndroidCard {
            VStack(alignment: .leading, spacing: 2) {
                Text(display.title).font(.system(size: 14, weight: .bold))
                Text(display.item.level ?? "").font(.system(size: 13)).foregroundStyle(AndroidParityPalette.brand)
                if let brief = display.item.brief, !brief.isEmpty {
                    Text(brief).font(.caption).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
        }
    }
}

private struct AndroidWeatherSettings: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject var model: WeatherViewModel
    @AppStorage("weather.show-on-home") private var showOnHome = true

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("天气设置").font(.title2).fontWeight(.bold)
                    Text("选择要显示的信息：").font(.body).foregroundStyle(.secondary)
                    Spacer().frame(height: 8)

                    Button {
                        dismiss()
                        Task { await model.useCurrentLocation() }
                    } label: {
                        Label("使用当前位置", systemImage: "location")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    Toggle("在首页显示天气", isOn: $showOnHome)
                        .padding(.vertical, 4)

                    ForEach(WeatherPreferenceKey.allCases) { key in
                        Toggle(
                            key.title,
                            isOn: Binding(
                                get: { value(for: key) },
                                set: { model.setPreference(key, enabled: $0) }
                            )
                        )
                        .padding(.vertical, 4)
                    }
                }
                .padding(24)
            }
        }
    }

    private func value(for key: WeatherPreferenceKey) -> Bool {
        switch key {
        case .location: model.preferences.showLocation
        case .temperature: model.preferences.showTemperature
        case .condition: model.preferences.showCondition
        case .airQuality: model.preferences.showAirQuality
        case .hourly: model.preferences.showHourlyForecast
        case .lifeIndices: model.preferences.showLifeIndices
        }
    }
}

private func androidTemperature(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))°" } ?? "--"
}

private func androidHourLabel(_ raw: String?) -> String {
    guard let raw else { return "--" }
    let separator = raw.contains("T") ? "T" : " "
    let date = raw.split(separator: "-").dropFirst().joined(separator: "-").prefix(5)
    let hour = raw.components(separatedBy: separator).last.map { String($0.prefix(2)) } ?? ""
    return date.count == 5 && hour.count == 2 ? "\(date)日\(hour)时" : raw
}

private func androidAQIColor(_ level: Int?) -> Color {
    switch level {
    case 1: AndroidParityPalette.success
    case 2: .yellow
    case 3: .orange
    case 4: Color(red: 1, green: 87 / 255, blue: 34 / 255)
    case 5: .purple
    case 6: .brown
    default: .gray
    }
}
