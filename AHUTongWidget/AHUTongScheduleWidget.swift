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
        completion(ScheduleWidgetEntry(date: Date(), snapshot: ScheduleWidgetSnapshotStore.loadSharedSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleWidgetEntry>) -> Void) {
        let entry = ScheduleWidgetEntry(date: Date(), snapshot: ScheduleWidgetSnapshotStore.loadSharedSnapshot())
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(30 * 60))))
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
        VStack(alignment: .leading, spacing: 5) {
            ForEach(entry.snapshot.courses.prefix(3)) { course in
                Text("周\(chineseWeekday(course.weekday)) \(course.startPeriod)-\(course.endPeriod)  \(course.name)")
                    .font(.caption)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
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

@main
struct AHUTongWidgetBundle: WidgetBundle {
    var body: some Widget { AHUTongScheduleWidget() }
}
