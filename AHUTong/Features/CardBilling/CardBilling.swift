import Foundation

struct CardBill: Decodable, Equatable, Identifiable, Sendable {
    let orderId: String
    let tranamt: Int64
    let cardBalance: Int64?
    let feeAmt: Int64?
    let typeFrom: String?
    let turnoverType: String?
    let consumeTypeName: String?
    let resume: String?
    let toMerchant: String?
    let remark: String?
    let effectdateStr: String?
    let jndatetimeStr: String?
    var id: String { orderId }
    var isExpense: Bool { typeFrom != "1" }
    var merchant: String { [toMerchant, resume, turnoverType].compactMap { $0 }.first { !$0.isEmpty } ?? "校园卡交易" }
    var time: String { effectdateStr ?? jndatetimeStr ?? "时间未知" }
    static func money(_ cents: Int64) -> String { (Decimal(cents) / 100).formatted(.currency(code: "CNY")) }
}

struct CardBillPage: Decodable, Sendable {
    let records: [CardBill]?
    let total: Int?
    let pages: Int?
}

struct CardBillSummary: Decodable, Sendable {
    let expenses: Int64?
    let income: Int64?
}

struct CardBillRange: Equatable, Sendable {
    let from: String
    let to: String
    static func month(containing date: Date) -> Self {
        let calendar = ScheduleCalendar.campus
        let start = calendar.dateInterval(of: .month, for: date)!.start
        let end = calendar.date(byAdding: .day, value: -1, to: calendar.dateInterval(of: .month, for: date)!.end)!
        func day(_ value: Date) -> String {
            let parts = calendar.dateComponents([.year, .month, .day], from: value)
            return String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        }
        return Self(from: day(start), to: day(end))
    }
}

enum CardBillingContract {
    static func query(page: Int, size: Int, range: CardBillRange?, type: String?) -> [URLQueryItem] {
        var items = [URLQueryItem(name: "size", value: String(size)), .init(name: "current", value: String(page)), .init(name: "synAccessSource", value: "h5")]
        if let range { items += [.init(name: "timeFrom", value: range.from), .init(name: "timeTo", value: range.to)] }
        if let type { items.append(.init(name: "type", value: type)) }
        return items
    }
    static func authorize(_ request: URLRequest, summary: Bool) throws {
        guard request.httpBody == nil, request.httpMethod == "GET", let url = request.url,
              url.fragment == nil,
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              Set(items.map(\.name)).count == items.count else { throw YCardReadOnlyError.disallowedEndpoint }
        let values = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        let allowed: Set<String> = summary ? ["timeFrom", "timeTo", "synAccessSource"] : ["timeFrom", "timeTo", "type", "size", "current", "synAccessSource"]
        guard Set(values.keys).isSubset(of: allowed), values["synAccessSource"] == "h5" else { throw YCardReadOnlyError.disallowedEndpoint }
        if !summary {
            guard let page = Int(values["current"] ?? ""), page > 0, page <= 10000,
                  let size = Int(values["size"] ?? ""), (1...100).contains(size),
                  values["type"] == nil || ["1", "2"].contains(values["type"]!) else { throw YCardReadOnlyError.disallowedEndpoint }
        }
        if summary || values["timeFrom"] != nil || values["timeTo"] != nil {
            guard let from = values["timeFrom"], let to = values["timeTo"], from <= to,
                  validDay(from), validDay(to) else { throw YCardReadOnlyError.disallowedEndpoint }
        }
    }
    private static func validDay(_ text: String) -> Bool {
        let formatter = DateFormatter()
        formatter.calendar = ScheduleCalendar.campus; formatter.timeZone = ScheduleCalendar.campus.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"; formatter.isLenient = false
        return text.count == 10 && formatter.date(from: text).map { formatter.string(from: $0) == text } == true
    }
    static func decode<T: Decodable & Sendable>(_ type: T.Type, data: Data) throws -> T {
        let envelope = try JSONDecoder().decode(Envelope<T>.self, from: data)
        guard envelope.code == 200, let value = envelope.data else {
            if envelope.code == 401 || envelope.code == 403 { throw YCardReadOnlyError.credentialsUnavailable }
            throw YCardReadOnlyError.server
        }
        return value
    }
    private struct Envelope<T: Decodable & Sendable>: Decodable { let code: Int; let data: T? }
}

protocol CardBillingRemote: Sendable {
    func page(_ page: Int, size: Int, range: CardBillRange?, type: String?) async throws -> CardBillPage
    func summary(range: CardBillRange) async throws -> CardBillSummary
}

struct OfficialCardBillingRemote: CardBillingRemote {
    private let client: YCardReadOnlyClient
    init(api: any CampusCoreAPI) { client = YCardReadOnlyClient(campusAPI: api) }
    func page(_ page: Int, size: Int, range: CardBillRange?, type: String?) async throws -> CardBillPage {
        try CardBillingContract.decode(CardBillPage.self, data: await client.request(.billPage, queryItems: CardBillingContract.query(page: page, size: size, range: range, type: type)))
    }
    func summary(range: CardBillRange) async throws -> CardBillSummary {
        try CardBillingContract.decode(CardBillSummary.self, data: await client.request(.billSummary, queryItems: [
            .init(name: "timeFrom", value: range.from), .init(name: "timeTo", value: range.to), .init(name: "synAccessSource", value: "h5")
        ]))
    }
}

struct CardBillAnalytics: Sendable {
    struct Amount: Identifiable, Sendable { let id: String; let cents: Int64; let count: Int }
    let expense: Int64
    let income: Int64
    let expenseCount: Int
    let merchants: [Amount]
    let days: [Amount]
    init(records: [CardBill]) {
        var seen = Set<String>()
        let records = records.filter { seen.insert($0.id).inserted }
        let expenses = records.filter(\.isExpense)
        expense = expenses.reduce(0) { $0 + $1.tranamt }
        income = records.filter { !$0.isExpense }.reduce(0) { $0 + $1.tranamt }
        expenseCount = expenses.count
        merchants = Dictionary(grouping: expenses, by: \.merchant).map { key, values in
            Amount(id: key, cents: values.reduce(0) { $0 + $1.tranamt }, count: values.count)
        }.sorted { $0.cents == $1.cents ? $0.id < $1.id : $0.cents > $1.cents }
        days = Dictionary(grouping: expenses, by: { String($0.time.prefix(10)) }).map { key, values in
            Amount(id: key, cents: values.reduce(0) { $0 + $1.tranamt }, count: values.count)
        }.sorted { $0.id < $1.id }
    }
}

@MainActor
final class CardBillingViewModel: ObservableObject {
    @Published private(set) var records: [CardBill] = []
    @Published private(set) var summary: CardBillSummary?
    @Published private(set) var analytics: CardBillAnalytics?
    @Published private(set) var isLoading = false
    @Published private(set) var hasMore = true
    @Published private(set) var error: String?
    @Published private(set) var summaryError: String?
    private let remote: any CardBillingRemote
    private var nextPage = 1
    private var revision = 0
    init(remote: any CardBillingRemote) { self.remote = remote }

    func refresh(range: CardBillRange?, type: String?, demo: Bool = false) async {
        revision += 1
        let current = revision
        nextPage = 1; records = []; hasMore = true; error = nil; analytics = nil; summary = nil; summaryError = nil
        isLoading = true
        defer { if current == revision { isLoading = false } }
        do {
            if demo { records = try Self.demoRecords(); hasMore = false; return }
            let page = try await remote.page(1, size: 20, range: range, type: type)
            try Task.checkCancellation()
            guard current == revision else { return }
            append(page, requestedPage: 1, size: 20)
            if let range {
                do { let value = try await remote.summary(range: range); if current == revision { summary = value } }
                catch { if current == revision { summaryError = "收支汇总暂不可用" } }
            }
        } catch is CancellationError {} catch { if current == revision { self.error = error.localizedDescription } }
    }

    func loadMore(range: CardBillRange?, type: String?) async {
        guard !isLoading, hasMore else { return }
        let current = revision
        isLoading = true; error = nil
        defer { if current == revision { isLoading = false } }
        do {
            let pageNumber = nextPage
            let page = try await remote.page(pageNumber, size: 20, range: range, type: type)
            try Task.checkCancellation()
            guard current == revision else { return }
            append(page, requestedPage: pageNumber, size: 20)
        } catch is CancellationError {} catch { if current == revision { self.error = error.localizedDescription } }
    }

    private func append(_ page: CardBillPage, requestedPage: Int, size: Int) {
        let rows = page.records ?? []
        var seen = Set(records.map(\.id))
        records += rows.filter { seen.insert($0.id).inserted }
        let pages = page.pages ?? page.total.map { ($0 + size - 1) / size } ?? 1
        hasMore = !rows.isEmpty && requestedPage < pages
        nextPage = requestedPage + 1
    }

    func loadAnalytics(range: CardBillRange?, demo: Bool = false) async {
        guard !isLoading else { return }
        isLoading = true; error = nil
        defer { isLoading = false }
        do {
            var rows: [CardBill] = []
            if demo { rows = try Self.demoRecords() }
            else {
                for pageNumber in 1...200 {
                    try Task.checkCancellation()
                    let page = try await remote.page(pageNumber, size: 100, range: range, type: nil)
                    let pageRows = page.records ?? []
                    rows += pageRows
                    let pages = page.pages ?? page.total.map { ($0 + 99) / 100 } ?? 1
                    if pageRows.isEmpty || pageNumber >= pages { break }
                    if pageNumber == 200 { throw CampusWebError.server("账单过多，请缩小时间范围后统计") }
                }
            }
            let completeRecords = rows
            let report = await Task.detached { CardBillAnalytics(records: completeRecords) }.value
            try Task.checkCancellation()
            analytics = report
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }

    nonisolated static func demoRecords() throws -> [CardBill] {
        try JSONDecoder().decode([CardBill].self, from: Data(#"[{"orderId":"demo-1","tranamt":1250,"cardBalance":12635,"typeFrom":"2","toMerchant":"榴园食堂","effectdateStr":"2026-10-19 12:08:00"},{"orderId":"demo-2","tranamt":10000,"typeFrom":"1","toMerchant":"校园卡充值","effectdateStr":"2026-10-18 10:00:00"},{"orderId":"demo-3","tranamt":650,"typeFrom":"2","toMerchant":"校园超市","effectdateStr":"2026-10-18 18:01:00"}]"#.utf8))
    }
}
