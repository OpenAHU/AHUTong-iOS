import Foundation

struct Semester: Codable, Equatable, Hashable, Sendable {
    let schoolYear: String
    let term: String

    enum CodingKeys: String, CodingKey {
        case schoolYear
        case term
    }

    var rawValue: String {
        "\(schoolYear)-\(term)"
    }

    init?(schoolYear: String, term: String) {
        let normalizedYear = schoolYear.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedTerm = term.trimmingCharacters(in: .whitespacesAndNewlines)
        let yearParts = normalizedYear.split(separator: "-", omittingEmptySubsequences: false)
        guard yearParts.count == 2,
              let startYear = Int(yearParts[0]),
              let endYear = Int(yearParts[1]),
              endYear == startYear + 1,
              !normalizedTerm.isEmpty else {
            return nil
        }
        self.schoolYear = normalizedYear
        self.term = normalizedTerm
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let schoolYear = try container.decode(String.self, forKey: .schoolYear)
        let term = try container.decode(String.self, forKey: .term)
        guard let semester = Semester(schoolYear: schoolYear, term: term) else {
            throw DecodingError.dataCorruptedError(
                forKey: .schoolYear,
                in: container,
                debugDescription: "Invalid semester year or term"
            )
        }
        self = semester
    }

    static func parse(_ rawValue: String?, fallbackSchoolYear: String? = nil) -> Semester? {
        guard let normalized = rawValue?.trimmingCharacters(in: .whitespacesAndNewlines),
              !normalized.isEmpty else {
            return nil
        }

        let parts = normalized.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count == 3 {
            return Semester(
                schoolYear: "\(parts[0])-\(parts[1])",
                term: String(parts[2])
            )
        }
        if parts.count == 1, let fallbackSchoolYear {
            return Semester(schoolYear: fallbackSchoolYear, term: normalized)
        }
        return nil
    }
}
