import Foundation

struct Course: Codable, Equatable, Hashable, Identifiable, Sendable {
    let weekday: Int
    let startWeek: Int
    let endWeek: Int
    let extra: String
    let location: String
    let name: String
    let teacher: String
    let duration: Int
    let startPeriod: Int
    let courseID: String
    let weekIndexes: [Int]

    var id: String {
        [courseID, name, String(weekday), String(startPeriod), location]
            .joined(separator: "|")
    }

    var endPeriod: Int {
        startPeriod + max(duration, 1) - 1
    }

    var isStructurallyValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (1...7).contains(weekday)
            && startPeriod > 0
            && duration > 0
            && !activeWeeks.isEmpty
    }

    var activeWeeks: [Int] {
        if !weekIndexes.isEmpty {
            return weekIndexes
        }
        guard startWeek > 0, endWeek >= startWeek else {
            return []
        }
        return Array(startWeek...endWeek)
    }

    init(
        weekday: Int,
        startWeek: Int,
        endWeek: Int,
        extra: String = "",
        location: String,
        name: String,
        teacher: String,
        duration: Int,
        startPeriod: Int,
        courseID: String,
        weekIndexes: [Int]
    ) {
        let normalizedWeeks = Array(Set(weekIndexes.filter { $0 > 0 })).sorted()
        self.weekday = weekday
        self.startWeek = normalizedWeeks.first ?? startWeek
        self.endWeek = normalizedWeeks.last ?? endWeek
        self.extra = extra
        self.location = location
        self.name = name
        self.teacher = teacher
        self.duration = duration
        self.startPeriod = startPeriod
        self.courseID = courseID
        self.weekIndexes = normalizedWeeks
    }

    func occurs(inWeek week: Int) -> Bool {
        activeWeeks.contains(week)
    }

    enum CodingKeys: String, CodingKey {
        case weekday
        case startWeek
        case endWeek
        case extra
        case location
        case name
        case teacher
        case duration = "length"
        case startPeriod = "startTime"
        case courseID = "courseId"
        case weekIndexes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            weekday: container.lossyInt(forKey: .weekday),
            startWeek: container.lossyInt(forKey: .startWeek),
            endWeek: container.lossyInt(forKey: .endWeek),
            extra: container.string(forKey: .extra),
            location: container.string(forKey: .location),
            name: container.string(forKey: .name),
            teacher: container.string(forKey: .teacher),
            duration: container.lossyInt(forKey: .duration),
            startPeriod: container.lossyInt(forKey: .startPeriod),
            courseID: container.string(forKey: .courseID),
            weekIndexes: (try? container.decode([Int].self, forKey: .weekIndexes)) ?? []
        )
    }
}

private extension KeyedDecodingContainer {
    func lossyInt(forKey key: Key) -> Int {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
        return 0
    }

    func string(forKey key: Key) -> String {
        (try? decode(String.self, forKey: key)) ?? ""
    }
}
