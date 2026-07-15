import ActivityKit
import SwiftUI
import WidgetKit

struct ScheduleWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleWidgetSnapshot
}

struct ScheduleWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> ScheduleWidgetEntry {
        ScheduleWidgetEntry(
            date: Date(),
            snapshot: .make(courses: Self.placeholderCourses, currentWeek: 1)
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleWidgetEntry) -> Void) {
        let now = Date()
        completion(ScheduleWidgetEntry(date: now, snapshot: ScheduleWidgetSnapshotStore.loadSharedSnapshot().resolved(at: now)))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleWidgetEntry>) -> Void) {
        let now = Date()
        let source = ScheduleWidgetSnapshotStore.loadSharedSnapshot()
        let dates = (0...48).compactMap { Calendar.current.date(byAdding: .minute, value: $0 * 30, to: now) }
        let entries = dates.map { ScheduleWidgetEntry(date: $0, snapshot: source.resolved(at: $0)) }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static let placeholderCourses = [
        Course(weekday: 1, startWeek: 1, endWeek: 16, location: "博学南楼 A301", name: "移动应用开发", teacher: "张老师", duration: 2, startPeriod: 1, courseID: "widget-1", weekIndexes: Array(1...16)),
        Course(weekday: 2, startWeek: 1, endWeek: 16, location: "笃行北楼 B402", name: "计算机网络", teacher: "王老师", duration: 2, startPeriod: 3, courseID: "widget-2", weekIndexes: Array(1...16))
    ]
}

struct AHUTongScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: ScheduleWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("本周课表").font(.headline)
                Spacer()
                Text("第 \(entry.snapshot.currentWeek) 周").font(.caption).foregroundStyle(.secondary)
            }
            switch entry.snapshot.status {
            case .signedOut:
                status("登录后显示课表", symbol: "person.crop.circle.badge.exclamationmark")
            case .expired:
                status("登录已失效", symbol: "exclamationmark.arrow.circlepath")
            case .empty:
                status("本周暂无课程", symbol: "calendar.badge.checkmark")
            case .ready:
                if family == .systemSmall {
                    compactCourses
                } else {
                    scheduleGrid
                }
            }
        }
        .containerBackground(Color(red: 247 / 255, green: 246 / 255, blue: 252 / 255), for: .widget)
        .widgetURL(URL(string: "ahutong://schedule"))
    }

    private var compactCourses: some View {
        let systemWeekday = Calendar.current.component(.weekday, from: entry.date)
        let weekday = systemWeekday == 1 ? 7 : systemWeekday - 1
        let remaining = entry.snapshot.courses.filter {
            $0.weekday == weekday && endTime(period: $0.endPeriod, on: entry.date) > entry.date
        }
        return VStack(alignment: .leading, spacing: 5) {
            ForEach((remaining.isEmpty ? entry.snapshot.courses : remaining).prefix(3)) { course in
                Text("\(course.weekday == weekday ? "今天" : "周\(chineseWeekday(course.weekday))") \(course.startPeriod)-\(course.endPeriod)  \(course.name)")
                    .font(.caption)
                    .fontWeight(isOngoing(course, at: entry.date) ? .bold : .regular)
                    .foregroundStyle(isOngoing(course, at: entry.date) ? Color.blue : Color.primary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
    }

    private func isOngoing(_ course: ScheduleWidgetCourse, at date: Date) -> Bool {
        startTime(period: course.startPeriod, on: date) <= date && date <= endTime(period: course.endPeriod, on: date)
    }

    private func startTime(period: Int, on date: Date) -> Date {
        let values = [1: (8, 0), 2: (8, 50), 3: (9, 50), 4: (10, 40), 5: (11, 30), 6: (14, 0), 7: (14, 50), 8: (15, 50), 9: (16, 40), 10: (17, 30), 11: (19, 0), 12: (19, 50), 13: (20, 40)]
        let value = values[period] ?? (0, 0)
        return Calendar.current.date(bySettingHour: value.0, minute: value.1, second: 0, of: date) ?? date
    }

    private func endTime(period: Int, on date: Date) -> Date {
        Calendar.current.date(byAdding: .minute, value: 45, to: startTime(period: period, on: date)) ?? date
    }

    private var scheduleGrid: some View {
        Grid(horizontalSpacing: 4, verticalSpacing: 4) {
            GridRow {
                ForEach(1...5, id: \.self) { day in
                    Text("周\(chineseWeekday(day))").font(.caption2).frame(maxWidth: .infinity)
                }
            }
            ForEach(Array(entry.snapshot.courses.prefix(family == .systemLarge ? 10 : 5))) { course in
                GridRow {
                    ForEach(1...5, id: \.self) { day in
                        if day == course.weekday {
                            Text(course.name)
                                .font(.caption2.bold())
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, minHeight: 28)
                                .background(Color(red: 232 / 255, green: 222 / 255, blue: 248 / 255), in: RoundedRectangle(cornerRadius: 5))
                        } else {
                            Color.clear.frame(minHeight: 28)
                        }
                    }
                }
            }
        }
    }

    private func status(_ text: String, symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.title2)
            Text(text).font(.caption).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.secondary)
    }

    private func chineseWeekday(_ value: Int) -> String {
        ["一", "二", "三", "四", "五", "六", "日"][max(1, min(7, value)) - 1]
    }
}

struct AHUTongScheduleWidget: Widget {
    let kind = "AHUTongScheduleWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleWidgetProvider()) { entry in
            AHUTongScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("安大通课表")
        .description("查看本周课程与上课地点")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CourseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.state.courseName).font(.headline).lineLimit(1)
                    Text(context.state.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Text(context.state.startDate, style: .timer)
                    .font(.headline.monospacedDigit())
            }
            .padding()
            .activityBackgroundTint(Color(red: 247 / 255, green: 246 / 255, blue: 252 / 255))
            .activitySystemActionForegroundColor(.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "calendar.badge.clock").foregroundStyle(.blue)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.state.courseName).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.startDate, style: .timer).monospacedDigit()
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.location).font(.caption).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "book.closed.fill").foregroundStyle(.blue)
            } compactTrailing: {
                Text(context.state.startDate, style: .timer).monospacedDigit()
            } minimal: {
                Image(systemName: "book.closed.fill").foregroundStyle(.blue)
            }
            .widgetURL(URL(string: "ahutong://schedule"))
            .keylineTint(.blue)
        }
    }
}

@main
struct AHUTongWidgetBundle: WidgetBundle {
    var body: some Widget {
        AHUTongScheduleWidget()
        CourseLiveActivityWidget()
    }
}
