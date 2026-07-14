import SwiftUI

@MainActor
final class WeatherViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<WeatherSnapshot> = .idle
    @Published private(set) var preferences = WeatherDisplayPreferences()
    @Published var notice: String?

    private let repository: WeatherRepository
    private let preferencesStore: WeatherPreferencesStore
    private let locationProvider: any WeatherLocationProviding
    private var lastQuery: WeatherQuery = .ip

    init(
        repository: WeatherRepository = .live(),
        preferencesStore: WeatherPreferencesStore = WeatherPreferencesStore(),
        locationProvider: any WeatherLocationProviding = CoreLocationWeatherProvider()
    ) {
        self.repository = repository
        self.preferencesStore = preferencesStore
        self.locationProvider = locationProvider
    }

    func start() async {
        preferences = await preferencesStore.load()
        guard case .idle = state else { return }
        await load(query: .ip)
    }

    func search(city: String) async {
        let normalized = city.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else {
            notice = "请输入城市名，例如“合肥”。"
            return
        }
        notice = nil
        await load(query: .city(normalized))
    }

    func refresh() async {
        notice = nil
        await load(query: lastQuery)
    }

    func useCurrentLocation() async {
        do {
            let city = try await locationProvider.requestCity()
            notice = "已按当前位置查询：\(city)"
            await load(query: .city(city))
        } catch {
            notice = "无法使用精确位置，已自动切换为 IP 定位。"
            await load(query: .ip)
        }
    }

    func setPreference(_ key: WeatherPreferenceKey, enabled: Bool) {
        switch key {
        case .location: preferences.showLocation = enabled
        case .temperature: preferences.showTemperature = enabled
        case .condition: preferences.showCondition = enabled
        case .airQuality: preferences.showAirQuality = enabled
        case .hourly: preferences.showHourlyForecast = enabled
        case .lifeIndices: preferences.showLifeIndices = enabled
        }
        let updated = preferences
        Task {
            do {
                try await preferencesStore.save(updated)
            } catch {
                notice = "天气显示设置保存失败。"
            }
        }
    }

    private func load(query: WeatherQuery) async {
        guard !state.isLoading else { return }
        lastQuery = query
        state = .loading
        do {
            let snapshot = try await repository.load(query: query)
            state = snapshot.response.isMeaningful ? .loaded(snapshot) : .empty
        } catch {
            state = .failed(
                AppErrorState(
                    title: "天气获取失败",
                    message: "请检查网络或更换城市后重试。"
                )
            )
        }
    }
}

enum WeatherPreferenceKey: String, CaseIterable, Identifiable {
    case location
    case temperature
    case condition
    case airQuality
    case hourly
    case lifeIndices

    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: "显示位置"
        case .temperature: "显示温度"
        case .condition: "显示天气状况"
        case .airQuality: "显示空气质量"
        case .hourly: "显示逐小时预报"
        case .lifeIndices: "显示生活指数"
        }
    }
}

struct WeatherView: View {
    @StateObject private var model: WeatherViewModel
    @State private var cityQuery = ""
    @State private var showSettings = false

    init(model: @autoclosure @escaping () -> WeatherViewModel = WeatherViewModel()) {
        _model = StateObject(wrappedValue: model())
    }

    var body: some View {
        Group {
            switch model.state {
            case .idle, .loading:
                ProgressView("正在获取天气")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(snapshot):
                weatherList(snapshot)
            case .empty:
                ContentUnavailableView(
                    "暂无天气数据",
                    systemImage: "cloud",
                    description: Text("请尝试搜索其他城市。")
                )
            case let .failed(error):
                ContentUnavailableView {
                    Label(error.title, systemImage: "cloud.bolt")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("重试") { Task { await model.refresh() } }
                }
            }
        }
        .navigationTitle("天气")
        .searchable(text: $cityQuery, prompt: "搜索城市，例如合肥")
        .onSubmit(of: .search) {
            Task { await model.search(city: cityQuery) }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("使用当前位置", systemImage: "location") {
                    Task { await model.useCurrentLocation() }
                }
                .labelStyle(.iconOnly)
                Button("刷新", systemImage: "arrow.clockwise") {
                    Task { await model.refresh() }
                }
                .labelStyle(.iconOnly)
                Button("显示设置", systemImage: "slider.horizontal.3") {
                    showSettings = true
                }
                .labelStyle(.iconOnly)
            }
        }
        .sheet(isPresented: $showSettings) {
            WeatherPreferencesView(model: model)
        }
        .task { await model.start() }
    }

    private func weatherList(_ snapshot: WeatherSnapshot) -> some View {
        List {
            if let notice = model.notice {
                Section {
                    Label(notice, systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            if snapshot.source == .staleCache {
                Section {
                    Label("网络不可用，正在显示该位置最近一次缓存", systemImage: "wifi.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("实况") {
                WeatherCurrentCard(
                    weather: snapshot.response,
                    preferences: model.preferences
                )
            }

            if let alerts = snapshot.response.alerts, !alerts.isEmpty {
                Section("天气预警") {
                    ForEach(alerts) { alert in
                        VStack(alignment: .leading, spacing: 5) {
                            Label(alert.title ?? alert.type ?? "天气预警", systemImage: "exclamationmark.triangle.fill")
                                .font(.headline)
                                .foregroundStyle(.orange)
                            if let text = alert.text { Text(text).font(.footnote) }
                        }
                    }
                }
            }

            if let forecast = snapshot.response.forecast, !forecast.isEmpty {
                Section("未来预报") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(forecast) { day in
                                WeatherForecastCard(day: day)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if model.preferences.showHourlyForecast,
               let hourly = snapshot.response.hourlyForecast,
               !hourly.isEmpty {
                Section("逐小时预报") {
                    ScrollView(.horizontal) {
                        HStack(spacing: 10) {
                            ForEach(Array(hourly.prefix(24))) { hour in
                                WeatherHourlyCard(hour: hour)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }

            if model.preferences.showAirQuality, snapshot.response.aqi != nil {
                Section("空气质量") {
                    WeatherAirQualityView(weather: snapshot.response)
                }
            }

            if model.preferences.showLifeIndices,
               let indices = snapshot.response.lifeIndices,
               !indices.displayItems.isEmpty {
                Section("生活指数") {
                    ForEach(indices.displayItems) { display in
                        WeatherLifeIndexRow(display: display)
                    }
                }
            }
        }
        .refreshable { await model.refresh() }
    }
}

private struct WeatherCurrentCard: View {
    let weather: WeatherResponse
    let preferences: WeatherDisplayPreferences

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    if preferences.showLocation {
                        Text(weather.locationName).font(.headline)
                    }
                    if preferences.showCondition {
                        Label(weather.weather ?? "天气未知", systemImage: weatherSymbol(weather.weather))
                            .foregroundStyle(.secondary)
                    }
                    if let reportTime = weather.reportTime {
                        Text(reportTime).font(.caption).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if preferences.showTemperature {
                    Text(formatTemperature(weather.temperature))
                        .font(.system(size: 52, weight: .light, design: .rounded))
                }
            }

            if preferences.showTemperature || preferences.showCondition {
                HStack {
                    WeatherMetric(title: "体感", value: formatTemperature(weather.feelsLike))
                    WeatherMetric(title: "湿度", value: weather.humidity.map { "\($0)%" } ?? "--")
                    WeatherMetric(title: "风力", value: weather.windPower ?? "--")
                    WeatherMetric(title: "能见度", value: weather.visibility.map { "\(Int($0)) km" } ?? "--")
                }
            }
        }
        .padding(.vertical, 6)
        .accessibilityIdentifier("weather.current")
    }
}

private struct WeatherMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.caption.monospacedDigit()).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct WeatherForecastCard: View {
    let day: WeatherForecastDay

    var body: some View {
        VStack(spacing: 7) {
            Text(day.week ?? day.date ?? "--").font(.caption).lineLimit(1)
            Image(systemName: weatherSymbol(day.weatherDay)).font(.title2)
            Text("\(formatTemperature(day.tempMax)) / \(formatTemperature(day.tempMin))")
                .font(.subheadline.monospacedDigit())
            Text(day.weatherDay ?? "--").font(.caption).foregroundStyle(.secondary)
            if let probability = day.probabilityOfPrecipitation {
                Label("\(probability)%", systemImage: "drop.fill").font(.caption2).foregroundStyle(.blue)
            }
        }
        .frame(width: 112, height: 132)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct WeatherHourlyCard: View {
    let hour: WeatherHourlyForecast

    var body: some View {
        VStack(spacing: 7) {
            Text(hourLabel(hour.time)).font(.caption2)
            Image(systemName: weatherSymbol(hour.weather))
            Text(formatTemperature(hour.temperature)).font(.headline.monospacedDigit())
            Text(hour.weather ?? "--").font(.caption2).foregroundStyle(.secondary)
        }
        .frame(width: 78, height: 104)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct WeatherAirQualityView: View {
    let weather: WeatherResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(weather.aqi.map(String.init) ?? "--")
                    .font(.largeTitle.bold().monospacedDigit())
                    .foregroundStyle(aqiColor(weather.aqiLevel))
                VStack(alignment: .leading) {
                    Text("空气\(weather.aqiCategory ?? "质量未知")").font(.headline)
                    Text("主要污染物：\(weather.aqiPrimary ?? "无")")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let pollutants = weather.airPollutants {
                HStack {
                    WeatherMetric(title: "PM2.5", value: pollutant(pollutants.pm25))
                    WeatherMetric(title: "PM10", value: pollutant(pollutants.pm10))
                    WeatherMetric(title: "O₃", value: pollutant(pollutants.o3))
                    WeatherMetric(title: "NO₂", value: pollutant(pollutants.no2))
                }
            }
        }
    }
}

private struct WeatherLifeIndexRow: View {
    let display: WeatherLifeIndexDisplayItem

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(display.title).font(.headline)
                Spacer()
                Text(display.item.level ?? "--").foregroundStyle(.secondary)
            }
            if let brief = display.item.brief { Text(brief).font(.subheadline) }
            if let advice = display.item.advice {
                Text(advice).font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct WeatherPreferencesView: View {
    @ObservedObject var model: WeatherViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(WeatherPreferenceKey.allCases) { key in
                        Toggle(
                            key.title,
                            isOn: Binding(
                                get: { value(for: key) },
                                set: { model.setPreference(key, enabled: $0) }
                            )
                        )
                    }
                } footer: {
                    Text("所有开关都会立即影响天气页面，并保存在本机。")
                }
            }
            .navigationTitle("天气显示设置")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
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

private func formatTemperature(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))°" } ?? "--"
}

private func pollutant(_ value: Double?) -> String {
    value.map { String(Int($0.rounded())) } ?? "--"
}

private func hourLabel(_ raw: String?) -> String {
    guard let raw else { return "--" }
    let time = raw.split(separator: raw.contains("T") ? "T" : " ").last.map(String.init) ?? raw
    return String(time.prefix(5))
}

private func weatherSymbol(_ condition: String?) -> String {
    guard let condition else { return "cloud" }
    if condition.contains("雷") { return "cloud.bolt.rain.fill" }
    if condition.contains("雪") { return "cloud.snow.fill" }
    if condition.contains("雨") { return "cloud.rain.fill" }
    if condition.contains("雾") || condition.contains("霾") { return "cloud.fog.fill" }
    if condition.contains("阴") { return "cloud.fill" }
    if condition.contains("云") { return "cloud.sun.fill" }
    if condition.contains("晴") { return "sun.max.fill" }
    return "cloud"
}

private func aqiColor(_ level: Int?) -> Color {
    switch level {
    case 1: .green
    case 2: .yellow
    case 3: .orange
    case 4: .red
    case 5: .purple
    case 6: .brown
    default: .secondary
    }
}
