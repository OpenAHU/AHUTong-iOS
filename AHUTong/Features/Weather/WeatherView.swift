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

    func start(autoLocate: Bool = false) async {
        preferences = await preferencesStore.load()
        guard case .idle = state else { return }
        if AppRuntime.isDemoSession, let response = DebugRuntimeSettings.decode("weather", as: WeatherResponse.self) {
            state = response.isMeaningful
                ? .loaded(WeatherSnapshot(response: response, source: .remote, updatedAt: DemoDataState.referenceDate))
                : .empty
            return
        }
        if autoLocate {
            await useCurrentLocation()
        } else {
            await load(query: .ip)
        }
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
