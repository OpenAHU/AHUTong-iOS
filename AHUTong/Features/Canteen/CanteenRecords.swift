import Foundation

enum CanteenNames {
    static func canonical(_ name: String) -> String {
        switch name {
        case "蕙园食堂": "蕙园"
        case "梧桐园食堂": "梧桐园"
        default: name
        }
    }
    static func serverNames(_ name: String) -> [String] {
        ["蕙园", "梧桐园"].contains(name) ? [name, name + "食堂"] : [name]
    }
    static func location(_ text: String) -> (canteen: String, floor: String?)? {
        guard text.contains("食堂") || text.contains("餐厅") else { return nil }
        let zones = [("北一区", "桔园"), ("北二区", "榴园"), ("北三区", "蕙园"),
                     ("南一区", "梅园"), ("南二区", "桂园"), ("南三区", "梧桐园")]
        let known = zones.first { text.contains($0.0) }?.1
        let name = known ?? text.range(of: #"[\p{Han}]{1,10}(?:食堂|餐厅)"#, options: .regularExpression).map { String(text[$0]) }
        guard let name else { return nil }
        let normalized = zones.map(\.1).first { name == $0 + "食堂" || name == $0 + "餐厅" } ?? canonical(name)
        let floor = text.range(of: #"(?:负一|[一二三四五六七八])楼"#, options: .regularExpression).map { String(text[$0]) }
        return (normalized, floor)
    }
}

// This is the entire contribution payload. School order IDs and account fields stay local.
struct CanteenTransaction: Codable, Hashable, Sendable {
    let terminal: String
    let ts: String
    let amountCents: Int64
    let canteen: String
    let floor: String?
}

struct CanteenMeal: Identifiable, Sendable {
    let id: String
    let terminal: String?
    let canteen: String
    let floor: String?
    let slot: String
    let date: Date
    var cents: Int64
    let merchant: String
    var location: String { [canteen, floor].compactMap { $0 }.joined(separator: " · ") }
}

struct CanteenFootprint: Sendable {
    let meals: [CanteenMeal]
    let transactions: [CanteenTransaction]
    var total: Int64 { meals.reduce(0) { $0 + $1.cents } }
    var windowCount: Int { Set(meals.compactMap(\.terminal)).count }
    func filtered(canteens: Set<String>) -> [CanteenMeal] {
        meals.filter { canteens.isEmpty || canteens.contains($0.canteen) }
    }

    init(records: [CardBill]) {
        let formatter = Self.formatter()
        var seen = Set<String>()
        var transactions = Set<CanteenTransaction>()
        var grouped: [String: [CanteenMeal]] = [:]
        for record in records where seen.insert(record.id).inserted {
            let merchant = [record.resume, record.toMerchant].compactMap { $0 }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } ?? record.merchant
            let direction = [record.resume, record.toMerchant, record.turnoverType, record.consumeTypeName, record.remark].compactMap { $0 }.joined(separator: " ")
            let isExpense = record.typeFrom.map { $0 != "1" }
                ?? !["充值", "退款", "退费", "转入", "入账"].contains { direction.contains($0) }
            guard isExpense, (1...50_000).contains(record.tranamt),
                  let location = CanteenNames.location(merchant), let rawTime = record.effectdateStr else { continue }
            var time = rawTime.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "T", with: " ")
            if time.count == 16 { time += ":00" }
            guard time.count == 19, let date = formatter.date(from: time), formatter.string(from: date) == time else { continue }
            let calendar = ScheduleCalendar.campus
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            let slot: String
            if (630..<840).contains(minute) { slot = "午餐" }
            else if (990..<1350).contains(minute) { slot = "晚餐" }
            else { continue }
            let terminal = record.locationName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            let key = "\(String(time.prefix(10)))|\(slot)|\(terminal ?? location.canteen + (location.floor ?? ""))"
            grouped[key, default: []].append(.init(id: key + time, terminal: terminal, canteen: location.canteen,
                                                  floor: location.floor, slot: slot, date: date, cents: record.tranamt, merchant: merchant))
            if let terminal {
                transactions.insert(.init(terminal: terminal, ts: time, amountCents: record.tranamt, canteen: location.canteen, floor: location.floor))
            }
        }
        meals = grouped.values.flatMap { records -> [CanteenMeal] in
            var merged: [CanteenMeal] = []
            for meal in records.sorted(by: { $0.date < $1.date }) {
                if let last = merged.last, meal.date.timeIntervalSince(last.date) <= 300 {
                    merged[merged.count - 1].cents += meal.cents
                } else { merged.append(meal) }
            }
            return merged
        }.sorted { $0.date > $1.date }
        self.transactions = transactions.sorted { $0.ts == $1.ts ? $0.terminal < $1.terminal : $0.ts < $1.ts }
    }

    func contribution(now: Date) -> [CanteenTransaction] {
        let calendar = ScheduleCalendar.campus
        let firstDay = calendar.date(byAdding: .day, value: -29, to: calendar.startOfDay(for: now))!
        let formatter = Self.formatter()
        return transactions.filter { transaction in
            guard let date = formatter.date(from: transaction.ts) else { return false }
            return date >= firstDay && date <= now
        }
    }
    static func formatter() -> DateFormatter {
        let value = DateFormatter()
        value.locale = Locale(identifier: "en_US_POSIX")
        value.calendar = ScheduleCalendar.campus; value.timeZone = ScheduleCalendar.campus.timeZone
        value.dateFormat = "yyyy-MM-dd HH:mm:ss"; value.isLenient = false
        return value
    }
}

@MainActor
final class CanteenRecordsModel: ObservableObject {
    @Published private(set) var footprint: CanteenFootprint?
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var mappingError: String?
    private let bills: any CardBillingRemote
    private let community: any CanteenCommunityRemote
    init(bills: any CardBillingRemote, community: any CanteenCommunityRemote) {
        self.bills = bills; self.community = community
    }
    func load(demo: Bool = false, now: Date = Date()) async {
        guard !isLoading else { return }
        isLoading = true; error = nil; mappingError = nil
        defer { isLoading = false }
        do {
            if demo {
                switch DemoDataState.current {
                case .loading: return
                case .error: throw CampusWebError.server("记录查询失败")
                case .empty: footprint = .init(records: []); return
                case .normal:
                    footprint = .init(records: try Self.demoBills(now: now))
                    names = ["DEMO001": "风味小炒", "DEMO002": "面食窗口"]
                    return
                }
            }
            let calendar = ScheduleCalendar.campus
            let formatter = CanteenFootprint.formatter()
            let from = calendar.date(byAdding: .day, value: -179, to: calendar.startOfDay(for: now))!
            let range = CardBillRange(from: String(formatter.string(from: from).prefix(10)), to: String(formatter.string(from: now).prefix(10)))
            var records: [CardBill] = []
            for page in 1...60 {
                try Task.checkCancellation()
                let value = try await bills.page(page, size: 100, range: range, type: "2")
                guard let rows = value.records else { throw CampusWebError.invalidResponse }
                records += rows
                if rows.isEmpty || value.pages.map({ page >= $0 }) == true
                    || value.total.map({ records.count >= $0 }) == true
                    || value.pages == nil && value.total == nil && rows.count < 100 { break }
                if page == 60 { throw CampusWebError.server("记录较多，未能完整读取，请稍后重试") }
            }
            let result = await Task.detached(priority: .userInitiated) { CanteenFootprint(records: records) }.value
            try Task.checkCancellation()
            footprint = result
            do { names = try await community.windowNames() }
            catch is CancellationError { throw CancellationError() }
            catch { mappingError = "窗口名称暂不可用，消费记录仍可查看" }
        } catch is CancellationError {} catch { self.error = error.localizedDescription }
    }
    static func demoBills(now: Date) throws -> [CardBill] {
        let yesterday = ScheduleCalendar.campus.date(byAdding: .day, value: -1, to: now)!
        let day = String(CanteenFootprint.formatter().string(from: yesterday).prefix(10))
        let json = """
        [{"orderId":"demo-1","tranamt":1250,"typeFrom":"2","resume":"北二区食堂一楼","locationName":"DEMO001","effectdateStr":"\(day) 11:30:00"},
         {"orderId":"demo-2","tranamt":900,"typeFrom":"2","resume":"南一区食堂二楼","locationName":"DEMO002","effectdateStr":"\(day) 17:30:00"},
         {"orderId":"demo-3","tranamt":1100,"typeFrom":"2","resume":"北一区食堂一楼","locationName":"DEMO003","effectdateStr":"\(day) 12:00:00"}]
        """
        return try JSONDecoder().decode([CardBill].self, from: Data(json.utf8))
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
