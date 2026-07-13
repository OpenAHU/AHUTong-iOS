import Foundation

struct User: Codable, Equatable, Hashable, Identifiable, Sendable {
    let name: String
    let studentID: String

    var id: String { studentID }

    enum CodingKeys: String, CodingKey {
        case name
        case studentID = "xh"
    }

    func academicYears(asOf date: Date, calendar: Calendar) -> [String] {
        let characters = Array(studentID)
        guard characters.count >= 4,
              let enrollmentSuffix = Int(String(characters[2...3])) else {
            return []
        }

        let components = calendar.dateComponents([.year, .month], from: date)
        guard let year = components.year, let month = components.month else {
            return []
        }

        let enrollmentYear = 2000 + enrollmentSuffix
        let currentAcademicYear = month < 9 ? year - 1 : year
        guard enrollmentYear <= currentAcademicYear else {
            return []
        }

        return stride(from: currentAcademicYear, through: enrollmentYear, by: -1)
            .map { "\($0)-\($0 + 1)" }
    }
}

enum LoginProvider: String, Codable, Sendable {
    case wisdom = "2"
    case local = "0"
}
