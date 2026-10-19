import CoreFoundation
import Foundation

enum TeachingWeekParser {
    static func parse(_ data: Data) throws -> Int {
        let object = try JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)
        guard let week = find(in: object) else { throw CampusCoreError.invalidResponse }
        return week
    }

    private static func find(in value: Any) -> Int? {
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            return Int(exactly: number.doubleValue)
        }
        if let string = value as? String { return Int(string.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if let dictionary = value as? [String: Any] {
            for key in ["week", "currentWeek", "teachWeek", "data", "object", "result"] {
                if let nested = dictionary[key], let week = find(in: nested) { return week }
            }
        }
        // Numeric status codes or unrelated fields are not teaching weeks.
        return nil
    }
}
