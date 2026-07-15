import ActivityKit
import Foundation

struct CourseActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        let courseName: String
        let location: String
        let startDate: Date
        let endDate: Date
    }

    let courseID: String
}
