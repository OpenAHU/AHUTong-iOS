import Foundation
import UserNotifications

struct CourseReminderRequest: Equatable, Sendable {
    let identifier: String
    let title: String
    let body: String
    let date: Date
}

enum ReminderAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
}

protocol NotificationScheduling: Sendable {
    func authorization() async -> ReminderAuthorization
    func requestAuthorization() async throws -> Bool
    func replaceCourseReminders(with requests: [CourseReminderRequest]) async throws
}

actor SystemNotificationScheduler: NotificationScheduling {
    private let center = UNUserNotificationCenter.current()

    func authorization() async -> ReminderAuthorization {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return ReminderAuthorization.authorized
        case .denied:
            return ReminderAuthorization.denied
        default:
            return ReminderAuthorization.notDetermined
        }
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func replaceCourseReminders(with requests: [CourseReminderRequest]) async throws {
        let pending = await center.pendingNotificationRequests()
        center.removePendingNotificationRequests(
            withIdentifiers: pending.map(\.identifier).filter { $0.hasPrefix("course-reminder.") }
        )
        for request in requests {
            let content = UNMutableNotificationContent()
            content.title = request.title
            content.body = request.body
            content.sound = .default
            let components = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute, .timeZone],
                from: request.date
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try await center.add(UNNotificationRequest(identifier: request.identifier, content: content, trigger: trigger))
        }
    }
}

struct CourseReminderPlanner: Sendable {
    private let startTimes = [
        1: (8, 0), 2: (8, 50), 3: (9, 50), 4: (10, 40), 5: (11, 30),
        6: (14, 0), 7: (14, 50), 8: (15, 50), 9: (16, 40), 10: (17, 30),
        11: (19, 0), 12: (19, 50), 13: (20, 40)
    ]

    func requests(
        courses: [Course],
        currentWeek: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> [CourseReminderRequest] {
        let weekday = calendar.component(.weekday, from: now)
        let monday = calendar.date(byAdding: .day, value: -((weekday + 5) % 7), to: calendar.startOfDay(for: now)) ?? now
        let requests = (0..<21).flatMap { dayOffset -> [CourseReminderRequest] in
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: monday) else { return [] }
            let week = currentWeek + dayOffset / 7
            let dayOfWeek = dayOffset % 7 + 1
            return courses.filter { $0.weekday == dayOfWeek && $0.occurs(inWeek: week) }.compactMap { course in
                guard let time = startTimes[course.startPeriod],
                      let start = calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: day),
                      let reminder = calendar.date(byAdding: .minute, value: -10, to: start),
                      reminder > now else { return nil }
                return CourseReminderRequest(
                    identifier: "course-reminder.\(week).\(course.id)",
                    title: "10 分钟后上课",
                    body: "\(course.name) · \(course.location)",
                    date: reminder
                )
            }
        }
        return requests.sorted { $0.date < $1.date }.prefix(60).map { $0 }
    }
}

actor CourseReminderCoordinator {
    private let scheduler: any NotificationScheduling
    private let planner: CourseReminderPlanner

    init(
        scheduler: any NotificationScheduling = SystemNotificationScheduler(),
        planner: CourseReminderPlanner = CourseReminderPlanner()
    ) {
        self.scheduler = scheduler
        self.planner = planner
    }

    func setEnabled(
        _ enabled: Bool,
        courses: [Course],
        currentWeek: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) async throws -> Bool {
        if !enabled {
            try await scheduler.replaceCourseReminders(with: [])
            return false
        }
        let status = await scheduler.authorization()
        let granted: Bool
        switch status {
        case .authorized: granted = true
        case .notDetermined: granted = try await scheduler.requestAuthorization()
        case .denied: granted = false
        }
        guard granted else { return false }
        try await scheduler.replaceCourseReminders(
            with: planner.requests(courses: courses, currentWeek: currentWeek, now: now, calendar: calendar)
        )
        return true
    }
}
