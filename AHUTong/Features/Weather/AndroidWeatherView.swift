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
        VStack(spacing: 0) { stateContent }
            .appBackground()
            .navigationTitle(locationTitle)
            .toolbar(.visible, for: .navigationBar)
            .searchable(text: $cityQuery, isPresented: $isSearchActive, prompt: "输入城市名，如 合肥")
            .onSubmit(of: .search, search)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("天气设置", systemImage: "gearshape") { showSettings = true }
                    Button("刷新天气", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                        .disabled(model.isRefreshing)
                }
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { WeatherSettingsView() }
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .task { await model.start(autoLocate: !AppRuntime.isDemoSession) }
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

                WeatherCurrentCard(weather: snapshot.response, preferences: model.preferences)

                if let forecast = snapshot.response.forecast, !forecast.isEmpty {
                    VStack(spacing: 0) {
                        AndroidSectionTitle(title: "未来预报")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(forecast) { WeatherForecastCard(day: $0) }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }

                if model.preferences.showAirQuality, snapshot.response.aqi != nil {
                    WeatherAirQualityCard(weather: snapshot.response)
                }

                WeatherUmbrellaCard(weather: snapshot.response)

                if model.preferences.showHourlyForecast,
                   let hourly = snapshot.response.hourlyForecast,
                   !hourly.isEmpty {
                    VStack(spacing: 0) {
                        AndroidSectionTitle(title: "逐小时预报")
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(Array(hourly.prefix(12))) { WeatherHourlyCard(hour: $0) }
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

private struct WeatherCurrentCard: View {
    let weather: WeatherResponse
    let preferences: WeatherDisplayPreferences

    var body: some View {
        VStack(spacing: 12) {
            if preferences.showLocation { Text(weather.locationName).font(.title2.weight(.medium)) }
            Image(systemName: weatherSymbol(weather.weather))
                .symbolRenderingMode(.multicolor)
                .font(.system(size: 56))
                .padding(.top, 4)
                .accessibilityHidden(true)
            if preferences.showTemperature {
                Text(androidTemperature(weather.temperature))
                    .font(.system(size: 88, weight: .thin, design: .rounded))
                    .nativeNumericTransition(value: weather.temperature)
                    .minimumScaleFactor(0.6).lineLimit(1)
            }
            if preferences.showCondition {
                Text(weather.weather ?? "").font(.title3.weight(.medium))
                Text("体感 \(androidTemperature(weather.feelsLike))")
                    .nativeNumericTransition(value: weather.feelsLike)
                    .foregroundStyle(.secondary)
            }
            if weather.tempMax != nil || weather.tempMin != nil {
                Text("最高 \(androidTemperature(weather.tempMax))   最低 \(androidTemperature(weather.tempMin))")
                    .font(.subheadline.weight(.medium))
            }
            Divider().padding(.vertical, 6)
            HStack(alignment: .top, spacing: 8) {
                WeatherMetric(label: "湿度", symbol: "humidity", value: weather.humidity.map { "\($0)%" } ?? "--")
                WeatherMetric(label: "风力", symbol: "wind", value: weather.windPower ?? "--")
                WeatherMetric(label: "能见度", symbol: "eye", value: weather.visibility.map { "\(Int($0)) km" } ?? "--")
            }
            if let report = weather.reportTime, !report.isEmpty {
                Text(report).font(.caption).foregroundStyle(.secondary).padding(.top, 4)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                .overlay {
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .fill(LinearGradient(colors: [.blue.opacity(0.2), .cyan.opacity(0.06), .clear],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                }
        }
        .accessibilityIdentifier("weather.current")
    }
}

private struct WeatherMetric: View {
    let label: String
    let symbol: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Label(label, systemImage: symbol).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WeatherForecastCard: View {
    let day: WeatherForecastDay

    var body: some View {
        VStack(spacing: 10) {
            Text(day.week ?? "").font(.subheadline.weight(.medium))
            Image(systemName: weatherSymbol(day.weatherDay)).symbolRenderingMode(.multicolor)
                .font(.title2).frame(height: 30).accessibilityHidden(true)
            Text(day.weatherDay ?? "").font(.caption).foregroundStyle(.secondary)
            VStack(spacing: 3) {
                Text(androidTemperature(day.tempMax)).font(.title3.weight(.medium))
                Text(androidTemperature(day.tempMin)).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 16).frame(width: 104)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private struct WeatherAirQualityCard: View {
    let weather: WeatherResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("空气质量", systemImage: "aqi.medium").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(weather.aqi.map(String.init) ?? "--").font(.title.weight(.medium))
                Text(weather.aqiCategory ?? "").font(.headline)
                Spacer()
            }
            Gauge(value: Double(min(500, max(0, weather.aqi ?? 0))), in: 0...500) { EmptyView() }
                .gaugeStyle(.linearCapacity)
                .tint(Gradient(colors: [.green, .yellow, .orange, .red, .purple]))
                .accessibilityLabel("空气质量指数")
                .accessibilityValue(weather.aqi.map(String.init) ?? "未知")
            if let primary = weather.aqiPrimary, !primary.isEmpty {
                Text("主要污染物：\(primary)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }
}

private struct WeatherUmbrellaCard: View {
    let weather: WeatherResponse

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: needsUmbrella ? "umbrella.fill" : "sun.max.fill")
                .symbolRenderingMode(.multicolor).font(.largeTitle).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 24))
    }

    private var nextSix: [WeatherHourlyForecast] { Array((weather.hourlyForecast ?? []).prefix(6)) }
    private var maxProbability: Int { nextSix.compactMap(\.probabilityOfPrecipitation).max() ?? 0 }
    private var needsUmbrella: Bool {
        let values = [weather.weather, weather.forecast?.first?.weatherDay, weather.forecast?.first?.weatherNight] + nextSix.map(\.weather)
        return values.compactMap { $0 }.contains { value in ["雨", "雪", "雹"].contains { value.contains($0) } }
    }
    private var title: String {
        if !needsUmbrella { return "无需雨伞" }
        if maxProbability >= 60 { return "务必带伞" }
        if maxProbability >= 40 { return "建议带伞" }
        if maxProbability > 0 { return "可能降雨" }
        return "建议带伞"
    }
    private var subtitle: String {
        if !needsUmbrella { return "当前及短期预报无降水" }
        if maxProbability > 0 { return "未来6小时降雨概率 \(maxProbability)%" }
        return "当前天气或预报有降雨"
    }
}

private struct WeatherHourlyCard: View {
    let hour: WeatherHourlyForecast

    var body: some View {
        VStack(spacing: 10) {
            Text(androidHourLabel(hour.time)).font(.caption).foregroundStyle(.secondary)
            Image(systemName: weatherSymbol(hour.weather)).symbolRenderingMode(.multicolor)
                .font(.title2).frame(height: 28).accessibilityHidden(true)
            Text(androidTemperature(hour.temperature)).font(.title3.weight(.medium))
                .nativeNumericTransition(value: hour.temperature)
            Text(hour.weather ?? "").font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 16).frame(width: 88)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 22))
        .accessibilityElement(children: .combine)
    }
}

private func weatherSymbol(_ condition: String?) -> String {
    let value = condition ?? ""
    if value.contains("雷") { return "cloud.bolt.rain.fill" }
    if value.contains("雪") { return "cloud.snow.fill" }
    if value.contains("雹") { return "cloud.hail.fill" }
    if value.contains("雨") { return "cloud.rain.fill" }
    if value.contains("雾") || value.contains("霾") { return "cloud.fog.fill" }
    if value.contains("多云") { return "cloud.sun.fill" }
    if value.contains("云") || value.contains("阴") { return "cloud.fill" }
    if value.contains("晴") { return "sun.max.fill" }
    return "thermometer.medium"
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

private struct WeatherSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("weather.show-on-home") private var showOnHome = false
    @AppStorage("weather.home.mode") private var homeMode = WeatherHomeMode.detailed.rawValue
    @AppStorage("weather.home.show-location") private var homeShowsLocation = true
    @AppStorage("weather.home.show-temperature") private var homeShowsTemperature = true
    @AppStorage("weather.home.show-condition") private var homeShowsCondition = true
    @AppStorage("weather.home.show-air-quality") private var homeShowsAirQuality = true

    var body: some View {
        Form {
            Section("首页天气") {
                Toggle("在首页显示天气", isOn: $showOnHome)
                Picker("首页样式", selection: $homeMode) {
                    ForEach(WeatherHomeMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
            }
            Section("详细卡片") {
                Toggle("显示城市名", isOn: $homeShowsLocation)
                Toggle("显示温度", isOn: $homeShowsTemperature)
                Toggle("显示天气状况", isOn: $homeShowsCondition)
                Toggle("显示空气质量", isOn: $homeShowsAirQuality)
            }
        }
        .navigationTitle("天气设置")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .accessibilityIdentifier("weather.settings")
    }
}

private func androidTemperature(_ value: Double?) -> String {
    value.map { "\(Int($0.rounded()))°" } ?? "--"
}

private func androidHourLabel(_ raw: String?) -> String {
    guard let raw else { return "--" }
    let separator = raw.contains("T") ? "T" : " "
    let hour = raw.components(separatedBy: separator).last.map { String($0.prefix(2)) } ?? ""
    return hour.count == 2 ? "\(hour)时" : raw
}
