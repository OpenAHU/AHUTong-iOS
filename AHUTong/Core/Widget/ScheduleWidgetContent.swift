import SwiftUI
import WidgetKit

struct ScheduleWidgetAgenda: Sendable {
    let day: Int
    let courses: [ScheduleWidgetCourse]
    static func make(snapshot: ScheduleWidgetSnapshot, date: Date, limit: Int) -> [Self] {
        let today = (ScheduleCalendar.campus.component(.weekday, from: date) + 5) % 7 + 1
        let days = Array(today...7)
        return days.map { day in
            Self(day: day, courses: snapshot.courses.filter { course in
                course.weekday == day && (day != today || (ScheduleCalendar.endTime(period: course.endPeriod, on: date) ?? date) > date)
            }.sorted { $0.startPeriod < $1.startPeriod })
        }.filter { !$0.courses.isEmpty }.prefix(limit).map { $0 }
    }
}

/// Overlapping classes share a visible block instead of covering each other.
struct ScheduleWidgetBlock: Identifiable, Sendable {
    let courses: [ScheduleWidgetCourse]
    var id: String { courses.map(\.id).joined(separator: ":") }
    var start: Int { courses.map(\.startPeriod).min() ?? 1 }
    var end: Int { courses.map(\.endPeriod).max() ?? start }
    static func make(courses: [ScheduleWidgetCourse], day: Int) -> [Self] {
        var blocks: [Self] = []
        for course in courses.filter({ $0.weekday == day }).sorted(by: { $0.startPeriod < $1.startPeriod }) {
            if let last = blocks.last, course.startPeriod <= last.end {
                blocks[blocks.count - 1] = Self(courses: last.courses + [course])
            } else { blocks.append(Self(courses: [course])) }
        }
        return blocks
    }
}

struct ScheduleWidgetContent: View {
    let date: Date
    let snapshot: ScheduleWidgetSnapshot
    let family: WidgetFamily
    let dark: Bool
    private var background: Color { dark ? Color(red: 0.065, green: 0.09, blue: 0.14) : Color(red: 0.96, green: 0.97, blue: 0.99) }
    private var ink: Color { dark ? Color(red: 0.94, green: 0.96, blue: 1) : Color(red: 0.07, green: 0.12, blue: 0.21) }
    private var secondary: Color { dark ? Color(red: 0.73, green: 0.79, blue: 0.88) : Color(red: 0.29, green: 0.35, blue: 0.45) }
    private var card: Color { dark ? Color(red: 0.14, green: 0.23, blue: 0.37) : Color(red: 0.84, green: 0.90, blue: 0.99) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(family == .systemLarge ? "本周课表" : "接下来").font(.system(.headline, design: .rounded))
                Spacer(minLength: 2)
                Text("第\(snapshot.currentWeek)周").font(.caption).foregroundStyle(secondary)
            }
            if snapshot.status == .ready {
                if family == .systemLarge { weeklyGrid } else { agenda }
            } else { status }
            if family != .systemSmall {
                Text("同步 \(snapshot.updatedAt.formatted(.dateTime.month().day().hour().minute()))")
                    .font(.system(size: 9)).foregroundStyle(secondary)
            }
        }
        .foregroundStyle(ink)
        .containerBackground(background, for: .widget)
        .widgetURL(URL(string: "ahutong://schedule"))
    }

    private var agenda: some View {
        let days = ScheduleWidgetAgenda.make(snapshot: snapshot, date: date, limit: family == .systemSmall ? 1 : 2)
        return HStack(alignment: .top, spacing: 12) {
            ForEach(days, id: \.day) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("周\(weekday(item.day))").font(.caption.bold()).foregroundStyle(secondary)
                    ForEach(item.courses.prefix(2)) { course in
                        VStack(alignment: .leading, spacing: 1) {
                            Text(course.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                            Text("\(course.startPeriod)–\(course.endPeriod)节 · \(ScheduleTextFormatter.shortLocation(course.location))")
                                .font(.system(size: 10)).lineLimit(1).foregroundStyle(secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                    if item.courses.count > 2 { Text("另\(item.courses.count - 2)门，点按查看").font(.system(size: 9)).foregroundStyle(secondary) }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            if days.isEmpty { Text("今天课程已结束，点按查看本周课表").font(.caption).foregroundStyle(secondary) }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var weeklyGrid: some View {
        let days = snapshot.courses.contains { $0.weekday > 5 } ? 1...7 : 1...5
        let periods = max(10, min(13, snapshot.courses.map(\.endPeriod).max() ?? 10))
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                Color.clear.frame(width: 13, height: 13)
                ForEach(days, id: \.self) { day in Text(weekday(day)).font(.system(size: 10, weight: .semibold)).frame(maxWidth: .infinity).foregroundStyle(secondary) }
            }
            GeometryReader { proxy in
                let row = proxy.size.height / CGFloat(periods)
                HStack(alignment: .top, spacing: 3) {
                    VStack(spacing: 0) {
                        ForEach(1...periods, id: \.self) { period in
                            Text("\(period)").font(.system(size: 8)).foregroundStyle(secondary).frame(height: row)
                        }
                    }.frame(width: 13)
                    ForEach(days, id: \.self) { day in
                        ZStack(alignment: .top) {
                            VStack(spacing: 0) {
                                ForEach(1...periods, id: \.self) { _ in
                                    Rectangle().fill(secondary.opacity(0.07)).frame(height: max(0, row - 1)).padding(.bottom, 1)
                                }
                            }
                            ForEach(ScheduleWidgetBlock.make(courses: snapshot.courses, day: day)) { block in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(block.courses.map(\.name).joined(separator: " / "))
                                        .font(.system(size: 10, weight: .semibold)).lineLimit(block.end > block.start ? 2 : 1)
                                        .fixedSize(horizontal: false, vertical: true)
                                    if block.end > block.start {
                                        Text(block.courses.count > 1 ? "\(block.courses.count)门重叠" : ScheduleTextFormatter.shortLocation(block.courses[0].location))
                                            .font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.85).truncationMode(.head).foregroundStyle(secondary)
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(3)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .frame(height: max(0, CGFloat(block.end - block.start + 1) * row - 2), alignment: .top)
                                .background(card, in: RoundedRectangle(cornerRadius: 4))
                                .clipped()
                                .offset(y: CGFloat(block.start - 1) * row)
                                .accessibilityLabel(Text(blockLabel(block, day: day)))
                            }
                        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                }
            }
        }
    }
    private func blockLabel(_ block: ScheduleWidgetBlock, day: Int) -> String {
        let details: [String] = block.courses.map { course in course.name + "，" + course.location }
        let period = String(block.start) + "至" + String(block.end) + "节"
        return "周" + weekday(day) + "，" + period + "，" + details.joined(separator: "；")
    }

    private var status: some View {
        let message: String = switch snapshot.status {
        case .ready: ""
        case .empty: "本周暂无课程"
        case .signedOut: "打开安大通同步课表"
        case .expired: "课表同步失败，请打开安大通重试"
        case .sharingUnavailable: "当前签名无法共享课表，请在安大通查看小组件指引"
        }
        return VStack(spacing: 8) {
            Image(systemName: snapshot.status == .empty ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark").font(.title2)
            Text(message).font(.caption).multilineTextAlignment(.center)
        }.foregroundStyle(secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private func weekday(_ day: Int) -> String { ["一", "二", "三", "四", "五", "六", "日"][max(1, min(7, day)) - 1] }
}
