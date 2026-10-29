import Foundation

enum CanteenPeriod: String, CaseIterable, Identifiable, Sendable {
    case week, month, all
    var id: Self { self }
    var title: String { switch self { case .week: "近7天"; case .month: "近30天"; case .all: "全部" } }
}

enum CanteenCampus: String, CaseIterable, Identifiable, Sendable {
    case all, qingyuan, longhe, jinzhai
    var id: Self { self }
    var title: String { switch self { case .all: "全部校区"; case .qingyuan: "磬苑"; case .longhe: "龙河"; case .jinzhai: "金寨路" } }
    var canteens: String? {
        switch self {
        case .all: nil
        case .qingyuan: "榴园,桔园,梅园,桂园,蕙园,梧桐园,蕙园食堂,梧桐园食堂"
        case .longhe: "本部二食堂,本部三食堂,二食堂餐厅,三食堂,外招餐厅"
        case .jinzhai: "江淮学院食堂"
        }
    }
    var names: [String] { Array(Set((canteens ?? CanteenCampus.allCases.dropFirst().compactMap(\.canteens).joined(separator: ",")).split(separator: ",").map { CanteenNames.canonical(String($0)) })).sorted() }
}

struct CanteenQuery: Hashable, Sendable {
    var period: CanteenPeriod = .week
    var campus: CanteenCampus = .all
    var selectedCanteens: Set<String> = []
    var limit = 50
    var title: String { selectedCanteens.isEmpty ? campus.title : selectedCanteens.sorted().joined(separator: "、") }
    func includes(_ name: String) -> Bool {
        let scope = selectedCanteens.isEmpty ? Set(campus.names) : selectedCanteens
        return campus == .all && selectedCanteens.isEmpty || scope.contains(CanteenNames.canonical(name))
    }
    var url: URL {
        var items: [URLQueryItem] = [.init(name: "period", value: period.rawValue), .init(name: "limit", value: String(limit)), .init(name: "minTxns", value: "20")]
        if !selectedCanteens.isEmpty {
            let names = selectedCanteens.sorted().flatMap(CanteenNames.serverNames)
            items.append(.init(name: "canteens", value: names.joined(separator: ",")))
        } else if let canteens = campus.canteens { items.append(.init(name: "canteens", value: canteens)) }
        return URL(string: "https://inchangejiang.cn/api/canteen/insights")!.appendingQueryItems(items)
    }
}

struct CanteenInsights: Decodable, Sendable {
    let startDay: String?
    let endDay: String?
    let sample: Sample?
    let confidence: Confidence?
    var ranking: [Window]?
    var canteenRanking: [Canteen]?
    let segments: [Segment]?
    let hourly: [Hour]?
    let trend: [Day]?
    let superlatives: Superlatives?
    let notes: [String]?

    struct Sample: Decodable, Sendable { let terminals: Int?; let days: Int?; let txns: Int? }
    struct Confidence: Decodable, Sendable { let level: String?; let note: String? }
    struct Window: Decodable, Identifiable, Sendable {
        let rank: Int?
        let terminal: String
        let name: String?
        let canteen: String?
        let floor: String?
        let txns: Int
        let share: Double?
        let avgCentsPerTxn: Double?
        var id: String { terminal }
        var isNamed: Bool { name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }
        var title: String { if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { name } else { "未命名窗口" } }
        var location: String { [canteen, floor].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ") }
    }
    struct Canteen: Decodable, Sendable { let canteen: String; let txns: Int }
    struct Segment: Decodable, Sendable { let segment: String; let txns: Int }
    struct Hour: Decodable, Sendable { let hour: Int; let txns: Int }
    struct Day: Decodable, Sendable { let day: String; let txns: Int }
    struct PeakDay: Decodable, Sendable { let day: String; let name: String?; let txns: Int }
    struct Superlatives: Decodable, Sendable {
        let lunchTopWindow: Window?
        let dinnerTopWindow: Window?
        let mostConsistent: Window?
        let mostImproved: Window?
        let leastPopular: Window?
        let peakDay: PeakDay?
        let busiestHour: Hour?
        var hasContent: Bool {
            lunchTopWindow != nil || dinnerTopWindow != nil || mostConsistent != nil
                || mostImproved != nil || leastPopular != nil || peakDay != nil || busiestHour != nil
        }
    }
}

protocol CanteenRankingRemote: Sendable {
    func load(_ query: CanteenQuery) async throws -> CanteenInsights
}

struct OfficialCanteenRankingRemote: CanteenRankingRemote {
    private let session: URLSession
    init(session: URLSession? = nil) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil; configuration.httpShouldSetCookies = false
        configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        self.session = session ?? URLSession(configuration: configuration)
    }
    func load(_ query: CanteenQuery) async throws -> CanteenInsights {
        var request = URLRequest(url: query.url, cachePolicy: .reloadIgnoringLocalCacheData)
        request.timeoutInterval = 20; request.httpShouldHandleCookies = false
        let (data, response) = try await session.diagnosticData(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              response.url == query.url, data.count <= 2_000_000 else { throw CampusWebError.server("榜单加载失败，请稍后重试") }
        return try JSONDecoder().decode(CanteenInsights.self, from: data)
    }
}

@MainActor
final class CanteenRankingViewModel: ObservableObject {
    struct Saved { let query: CanteenQuery; let value: CanteenInsights; let date: Date }
    @Published private(set) var saved: Saved?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let remote: any CanteenRankingRemote
    private var cache: [CanteenQuery: Saved] = [:]
    private var generation = 0
    private var hasEntered = false
    init(remote: any CanteenRankingRemote = OfficialCanteenRankingRemote()) { self.remote = remote }

    func load(_ query: CanteenQuery, refresh: Bool = false, demo: Bool = false) async {
        generation += 1
        let revision = generation
        let force = refresh || !hasEntered
        hasEntered = true; error = nil
        if saved?.query != query { saved = nil }
        if !force, let cached = cache[query], cached.date.timeIntervalSinceNow > -300 {
            saved = cached; isLoading = false; return
        }
        isLoading = true
        defer { if revision == generation, !(demo && DemoDataState.current == .loading) { isLoading = false } }
        do {
            var value: CanteenInsights
            if demo {
                switch DemoDataState.current {
                case .loading: return
                case .error: throw CampusWebError.server("榜单加载失败，请检查网络后重试")
                case .empty: value = try JSONDecoder().decode(CanteenInsights.self, from: Data(#"{"ranking":[]}"#.utf8))
                case .normal:
                    value = try JSONDecoder().decode(CanteenInsights.self, from: Data(Self.demoJSON.utf8))
                    value.ranking = value.ranking?.filter { query.includes($0.canteen ?? "") }.enumerated().map { index, window in
                        .init(rank: index + 1, terminal: window.terminal, name: window.name, canteen: window.canteen, floor: window.floor,
                              txns: window.txns, share: window.share, avgCentsPerTxn: window.avgCentsPerTxn)
                    }
                    value.canteenRanking = value.canteenRanking?.filter { query.includes($0.canteen) }
                }
            } else { value = try await remote.load(query) }
            try Task.checkCancellation()
            guard revision == generation else { return }
            let result = Saved(query: query, value: value, date: Date())
            cache[query] = result; saved = result
        } catch is CancellationError {} catch {
            guard revision == generation else { return }
            self.error = "榜单加载失败，请检查网络后重试"
        }
    }

    static let demoJSON = #"""
    {"startDay":"2026-10-19","endDay":"2026-10-25","sample":{"terminals":28,"days":7,"txns":4800},"confidence":{"level":"medium","note":"示例数据，仅展示界面"},"ranking":[{"rank":1,"terminal":"DEMO001","name":"风味小炒","canteen":"榴园","floor":"一楼","txns":520,"share":0.108,"avgCentsPerTxn":1250},{"rank":2,"terminal":"DEMO002","name":"面食窗口","canteen":"梅园","floor":"二楼","txns":460,"share":0.096,"avgCentsPerTxn":900},{"rank":3,"terminal":"DEMO003","name":null,"canteen":"桔园","floor":"一楼","txns":400,"share":0.083,"avgCentsPerTxn":1100}],"canteenRanking":[{"canteen":"榴园","txns":1800},{"canteen":"梅园","txns":1600},{"canteen":"桔园","txns":1400}],"segments":[{"segment":"lunch","txns":2600},{"segment":"dinner","txns":2200}],"hourly":[{"hour":11,"txns":2200},{"hour":12,"txns":400},{"hour":17,"txns":1800},{"hour":18,"txns":400}],"trend":[{"day":"2026-10-19","txns":700},{"day":"2026-10-20","txns":650},{"day":"2026-10-21","txns":720}],"notes":["基于已贡献的正餐消费样本，热度不代表口味评价。"]}
    """#
}
