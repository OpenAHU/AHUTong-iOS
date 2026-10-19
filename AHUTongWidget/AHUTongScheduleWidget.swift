import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

enum ScheduleWidgetAppearance: String, AppEnum {
    case system, light, dark
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "外观"
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.system: "跟随系统", .light: "浅色", .dark: "深色"]
}

struct ScheduleWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "课表外观"
    static let description = IntentDescription("选择课表小组件的深浅色。")
    @Parameter(title: "外观", default: .system) var appearance: ScheduleWidgetAppearance
}

struct ScheduleWidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: ScheduleWidgetSnapshot
    var appearance: ScheduleWidgetAppearance = .system
}

struct ScheduleWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ScheduleWidgetEntry {
        ScheduleWidgetEntry(date: Date(), snapshot: .make(courses: Self.placeholderCourses, currentWeek: 1))
    }
    func snapshot(for configuration: ScheduleWidgetConfiguration, in context: Context) async -> ScheduleWidgetEntry {
        if context.isPreview { return ScheduleWidgetEntry(date: Date(), snapshot: .make(courses: Self.placeholderCourses, currentWeek: 1), appearance: configuration.appearance) }
        let now = Date()
        return ScheduleWidgetEntry(date: now, snapshot: ScheduleWidgetSnapshotStore.loadSharedSnapshot().resolved(at: now), appearance: configuration.appearance)
    }
    func timeline(for configuration: ScheduleWidgetConfiguration, in context: Context) async -> Timeline<ScheduleWidgetEntry> {
        let now = Date()
        let source = ScheduleWidgetSnapshotStore.loadSharedSnapshot()
        let entries = (0...48).compactMap { Calendar.current.date(byAdding: .minute, value: $0 * 30, to: now) }.map {
            ScheduleWidgetEntry(date: $0, snapshot: source.resolved(at: $0), appearance: configuration.appearance)
        }
        return Timeline(entries: entries, policy: .atEnd)
    }
    private static let placeholderCourses = (1...5).flatMap { day in
        [Course(weekday: day, startWeek: 1, endWeek: 16, location: "博学南楼 A301", name: day.isMultiple(of: 2) ? "计算机网络" : "移动应用开发", teacher: "", duration: 2, startPeriod: day.isMultiple(of: 2) ? 3 : 1, courseID: "widget-\(day)", weekIndexes: Array(1...16))]
    }
}

struct AHUTongScheduleWidgetView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    let entry: ScheduleWidgetEntry
    var body: some View {
        ScheduleWidgetContent(date: entry.date, snapshot: entry.snapshot, family: family,
                              dark: entry.appearance == .dark || (entry.appearance == .system && colorScheme == .dark))
    }
}

struct AHUTongScheduleWidget: Widget {
    let kind = "AHUTongScheduleWidget"
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: kind, intent: ScheduleWidgetConfiguration.self, provider: ScheduleWidgetProvider()) { entry in
            AHUTongScheduleWidgetView(entry: entry)
        }
        .configurationDisplayName("安大通课表")
        .description("查看课程与地点，支持深浅色配置")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CourseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: CourseActivityAttributes.self) { context in
            if !context.isStale {
                CourseLiveActivityCard(state: context.state)
                    .padding()
                    .activitySystemActionForegroundColor(.blue)
                    .widgetURL(URL(string: "ahutong://schedule"))
            }
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    if !context.isStale { Image(systemName: "calendar.badge.clock").foregroundStyle(.blue) }
                }
                DynamicIslandExpandedRegion(.center) {
                    if !context.isStale { Text(context.state.courseName).font(.headline).lineLimit(1) }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if !context.isStale {
                        HStack {
                            Text(context.state.location).font(.caption).lineLimit(1)
                            Spacer()
                            CoursePreclassCountdown(state: context.state)
                        }
                    }
                }
            } compactLeading: {
                if !context.isStale { Image(systemName: "book.closed.fill").foregroundStyle(.blue) }
            } compactTrailing: {
                if !context.isStale {
                    CourseCountdownText(state: context.state)
                        .font(.caption.monospacedDigit()).frame(width: 62, alignment: .trailing)
                }
            } minimal: {
                if !context.isStale { Image(systemName: "book.closed.fill").foregroundStyle(.blue) }
            }
            .widgetURL(URL(string: "ahutong://schedule"))
            .keylineTint(.blue)
        }
    }
}

private struct CourseLiveActivityCard: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock").font(.title2).foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.courseName).font(.headline).lineLimit(1)
                Text(state.location).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            CoursePreclassCountdown(state: state)
        }
    }
}

private struct CoursePreclassCountdown: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text("距上课").font(.caption2).foregroundStyle(.secondary)
            CourseCountdownText(state: state).font(.headline.monospacedDigit())
        }
        .accessibilityElement(children: .combine)
    }
}

private struct CourseCountdownText: View {
    let state: CourseActivityAttributes.ContentState

    var body: some View {
        Text(timerInterval: state.countdownInterval(to: state.startDate), countsDown: true, showsHours: true)
            .multilineTextAlignment(.trailing)
            .contentTransition(.numericText(countsDown: true))
    }
}

@main
struct AHUTongWidgetBundle: WidgetBundle {
    var body: some Widget {
        AHUTongScheduleWidget()
        CourseLiveActivityWidget()
    }
}
