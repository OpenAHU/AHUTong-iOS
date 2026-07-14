import Foundation

struct CampusExam: Codable, Equatable, Identifiable, Sendable {
    let course: String
    let time: String
    let seatNumber: String
    let location: String
    let isFinished: Bool

    var id: String { "\(course)|\(time)|\(seatNumber)" }

    enum CodingKeys: String, CodingKey {
        case course
        case time
        case seatNumber = "seatNum"
        case location
        case isFinished = "finished"
    }
}

struct CampusGrade: Codable, Equatable, Identifiable, Sendable {
    let courseName: String
    let courseCode: String
    let credit: Double?
    let score: String
    let gradePoint: Double?
    let courseProperty: String
    let semesterID: Int?
    let semesterName: String

    var id: String { "\(courseCode)|\(courseName)|\(semesterID ?? 0)" }
}

struct CampusGradeReport: Equatable, Sendable {
    let grades: [CampusGrade]
    let gradePointAverage: Double?
    let rank: String?
    let studentProfiles: [String]
}

enum CampusCoreError: Error, Equatable, LocalizedError, Sendable {
    case serverStartup(String)
    case invalidResponse
    case unauthorized
    case campus(String)

    var errorDescription: String? {
        switch self {
        case let .serverStartup(message): "校园服务启动失败：\(message)"
        case .invalidResponse: "校园服务返回了无法识别的数据"
        case .unauthorized: "登录已过期，请重新登录"
        case let .campus(message): message
        }
    }
}

struct CampusGradeParser: Sendable {
    func parse(_ data: Data) throws -> CampusGradeReport {
        let object = try JSONSerialization.jsonObject(with: data)
        let root = object as? [String: Any] ?? [:]
        let gradeObjects = findGradeObjects(in: object)
        let grades = gradeObjects.compactMap(parseGrade)
        let profiles = findStrings(
            keys: ["studentName", "studentId", "studentNo", "majorName", "nameZh"],
            in: root
        )
        return CampusGradeReport(
            grades: unique(grades),
            gradePointAverage: findDouble(keys: ["gpa", "gradePointAverage", "avgGradePoint"], in: object),
            rank: findString(keys: ["rank", "majorRank", "ranking"], in: object),
            studentProfiles: Array(Set(profiles)).sorted()
        )
    }

    private func findGradeObjects(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            var result: [[String: Any]] = []
            if looksLikeGrade(dictionary) {
                result.append(dictionary)
            }
            for nested in dictionary.values {
                result.append(contentsOf: findGradeObjects(in: nested))
            }
            return result
        }
        if let array = value as? [Any] {
            return array.flatMap(findGradeObjects)
        }
        return []
    }

    private func looksLikeGrade(_ value: [String: Any]) -> Bool {
        let keys = Set(value.keys)
        let hasCourse = !keys.isDisjoint(with: ["courseName", "courseNameZh", "lessonName", "course"])
        let hasScore = !keys.isDisjoint(with: ["grade", "score", "gaGrade", "gradePoint"])
        return hasCourse && hasScore
    }

    private func parseGrade(_ value: [String: Any]) -> CampusGrade? {
        guard let courseName = string(keys: ["courseName", "courseNameZh", "lessonName", "course"], in: value),
              let score = string(keys: ["grade", "score", "gaGrade", "gradePoint"], in: value) else {
            return nil
        }
        return CampusGrade(
            courseName: courseName,
            courseCode: string(keys: ["courseCode", "lessonCode", "courseNum"], in: value) ?? courseName,
            credit: double(keys: ["credit", "credits"], in: value),
            score: score,
            gradePoint: double(keys: ["gradePoint", "gp"], in: value),
            courseProperty: string(keys: ["courseProperty", "courseType", "courseNature"], in: value) ?? "",
            semesterID: int(keys: ["semesterId", "semesterID"], in: value),
            semesterName: string(keys: ["semesterName", "term"], in: value) ?? ""
        )
    }

    private func unique(_ grades: [CampusGrade]) -> [CampusGrade] {
        var seen: Set<String> = []
        return grades.filter { seen.insert($0.id).inserted }
    }

    private func collectStrings(keys: [String], in dictionary: [String: Any]) -> [String] {
        dictionary.compactMap { key, value in
            keys.contains(key) ? scalarString(value) : nil
        }
    }

    private func findStrings(keys: [String], in value: Any) -> [String] {
        if let dictionary = value as? [String: Any] {
            return collectStrings(keys: keys, in: dictionary)
                + dictionary.values.flatMap { findStrings(keys: keys, in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { findStrings(keys: keys, in: $0) }
        }
        return []
    }

    private func findDouble(keys: [String], in value: Any) -> Double? {
        if let dictionary = value as? [String: Any] {
            if let found = double(keys: keys, in: dictionary) { return found }
            for nested in dictionary.values {
                if let found = findDouble(keys: keys, in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findDouble(keys: keys, in: nested) { return found }
            }
        }
        return nil
    }

    private func findString(keys: [String], in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            if let found = string(keys: keys, in: dictionary) { return found }
            for nested in dictionary.values {
                if let found = findString(keys: keys, in: nested) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = findString(keys: keys, in: nested) { return found }
            }
        }
        return nil
    }

    private func string(keys: [String], in value: [String: Any]) -> String? {
        for key in keys {
            if let result = scalarString(value[key]), !result.isEmpty { return result }
        }
        return nil
    }

    private func double(keys: [String], in value: [String: Any]) -> Double? {
        for key in keys {
            if let number = value[key] as? NSNumber { return number.doubleValue }
            if let string = value[key] as? String, let number = Double(string) { return number }
        }
        return nil
    }

    private func int(keys: [String], in value: [String: Any]) -> Int? {
        double(keys: keys, in: value).map(Int.init)
    }

    private func scalarString(_ value: Any?) -> String? {
        if let string = value as? String { return string.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let number = value as? NSNumber { return number.stringValue }
        if let nested = value as? [String: Any] {
            return string(keys: ["nameZh", "name", "value"], in: nested)
        }
        return nil
    }
}
