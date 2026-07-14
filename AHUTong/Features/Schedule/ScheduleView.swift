import SwiftUI

struct ScheduleView: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedWeek = 1

    private let times = [
        "08:00", "08:50", "09:50", "10:40", "11:30", "14:00", "14:50",
        "15:50", "16:40", "17:30", "19:00", "19:50", "20:40"
    ]
    private let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]

    var body: some View {
        AndroidScreen {
            ScrollView(.vertical) {
                VStack(spacing: 8) {
                    controls
                    scheduleGrid
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(1...20, id: \.self) { week in
                            Button {
                                selectedWeek = week
                                withAnimation { proxy.scrollTo(max(1, week - 2), anchor: .leading) }
                            } label: {
                                Text("\(week)")
                                    .font(.headline)
                                    .fontWeight(.bold)
                                    .foregroundStyle(selectedWeek == week ? Color.white : Color.primary)
                                    .padding(.horizontal, 16)
                                    .padding(.vertical, 8)
                                    .background(
                                        selectedWeek == week ? AndroidParityPalette.brand : .clear,
                                        in: Capsule(style: .continuous)
                                    )
                            }
                            .buttonStyle(.plain)
                            .id(week)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .scrollIndicators(.hidden)
            }

            HStack(spacing: 0) {
                scheduleAction("location", "回到当前周") { selectedWeek = 1 }
                scheduleAction("gearshape", "课表设置") {}
                scheduleAction("arrow.clockwise", "刷新课表") {}
            }
            .padding(2)
            .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
            .padding(.trailing, 8)
        }
    }

    private func scheduleAction(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .frame(width: 38, height: 38)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var scheduleGrid: some View {
        GeometryReader { geometry in
            let spacing: CGFloat = 4
            let timeWidth: CGFloat = 40
            let dayWidth = (geometry.size.width - timeWidth - spacing * 9) / 7

            VStack(spacing: spacing) {
                HStack(spacing: spacing) {
                    Color.clear.frame(width: timeWidth, height: 64)
                    ForEach(Array(weekdays.enumerated()), id: \.offset) { index, weekday in
                        VStack(spacing: 2) {
                            Text(weekday).font(.caption).fontWeight(.semibold)
                            Text(dateLabel(dayIndex: index)).font(.caption2).foregroundStyle(.secondary)
                        }
                        .frame(width: dayWidth, height: 64)
                        .background(
                            index == currentWeekdayIndex && selectedWeek == 1
                                ? AndroidParityPalette.primaryContainer(colorScheme)
                                : .clear,
                            in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                        )
                    }
                }

                ForEach(Array(times.enumerated()), id: \.offset) { index, time in
                    HStack(spacing: spacing) {
                        VStack(spacing: 1) {
                            Text("\(index + 1)").font(.caption).fontWeight(.semibold)
                            Text(time).font(.system(size: 9)).foregroundStyle(.secondary)
                        }
                        .frame(width: timeWidth, height: 48)

                        ForEach(0..<7, id: \.self) { _ in
                            Color.clear.frame(width: dayWidth, height: 48)
                        }
                    }
                }
            }
            .padding(.top, 8)
            .padding(4)
        }
        .frame(height: 64 + 13 * 52 + 24)
        .background(
            AndroidParityPalette.raisedSurface(colorScheme),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
    }

    private var currentWeekdayIndex: Int {
        let value = Calendar.current.component(.weekday, from: Date())
        return (value + 5) % 7
    }

    private func dateLabel(dayIndex: Int) -> String {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)) ?? Date()
        let date = calendar.date(byAdding: .day, value: (selectedWeek - 1) * 7 + dayIndex, to: start) ?? start
        let components = calendar.dateComponents([.month, .day], from: date)
        return String(format: "%02d-%02d", components.month ?? 0, components.day ?? 0)
    }
}
