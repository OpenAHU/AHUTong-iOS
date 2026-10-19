import CoreFoundation
import Foundation

enum TeachingWeekParser {
    static func parse(_ data: Data) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let week = week(in: object) else { throw CampusCoreError.invalidResponse }
        return week
    }

    private static func week(in value: Any) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID(),
                  number.doubleValue == Double(number.intValue),
                  (1...20).contains(number.intValue) else { return nil }
            return number.intValue
        }
        if let string = value as? String,
           let number = Int(string.trimmingCharacters(in: .whitespacesAndNewlines)),
           (1...20).contains(number) { return number }
        guard let dictionary = value as? [String: Any] else { return nil }
        // Never mistake a semester ID, status code or unrelated numeric field for a week.
        for key in ["weekIndex", "week", "currentWeek", "teachWeek", "currentTeachWeek", "data", "object", "result"] {
            if let nested = dictionary[key], let result = week(in: nested) { return result }
        }
        return nil
    }
}
