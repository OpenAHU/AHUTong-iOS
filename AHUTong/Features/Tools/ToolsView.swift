import SwiftUI

struct ToolsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let tools = AndroidToolItem.all
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "小工具")

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(tools) { tool in
                            destination(for: tool)
                        }
                    }
                    .padding(.horizontal, 16)

                    desktopWidgetCard
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 96)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("screen.tools")
    }

    @ViewBuilder
    private func destination(for tool: AndroidToolItem) -> some View {
        NavigationLink {
            switch tool.id {
            case "phone-book": PhoneBookView().androidDetailScreen()
            case "school-calendar": SchoolCalendarView().androidDetailScreen()
            case "weather": WeatherView().androidDetailScreen()
            case "study-repository": StudyRepositoryView().androidDetailScreen()
            default: AndroidToolPlaceholder(title: tool.title).androidDetailScreen()
            }
        } label: {
            AndroidToolCell(tool: tool)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("tools.\(tool.id)")
    }

    private var desktopWidgetCard: some View {
        AndroidCard(radius: 32) {
            VStack(spacing: 16) {
                Text("添加桌面课表微件")
                    .font(.title2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(24)

                ScheduleWidgetPreview()
                    .padding(.horizontal, 24)

                Button("添加") {}
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(AndroidParityPalette.primaryContainer(colorScheme), in: Capsule())
                    .padding(16)
            }
        }
    }
}

private struct AndroidToolItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color

    static let all = [
        AndroidToolItem(id: "grade", title: "成绩单", systemImage: "chart.bar.doc.horizontal", tint: .yellow),
        AndroidToolItem(id: "phone-book", title: "电话本", systemImage: "person.crop.rectangle.stack", tint: Color(red: 0, green: 150 / 255, blue: 136 / 255)),
        AndroidToolItem(id: "exam", title: "考场查询", systemImage: "mappin.and.ellipse", tint: AndroidParityPalette.success),
        AndroidToolItem(id: "school-calendar", title: "校历", systemImage: "square.grid.2x2", tint: .purple),
        AndroidToolItem(id: "free-classroom", title: "空闲教室", systemImage: "building.2", tint: Color(red: 3 / 255, green: 169 / 255, blue: 244 / 255)),
        AndroidToolItem(id: "lost-found", title: "失物招领", systemImage: "questionmark.bag", tint: Color(red: 25 / 255, green: 118 / 255, blue: 210 / 255)),
        AndroidToolItem(id: "weather", title: "天气", systemImage: "sun.max.fill", tint: AndroidParityPalette.warning),
        AndroidToolItem(id: "study-repository", title: "学习资料", systemImage: "doc.on.doc", tint: Color(red: 141 / 255, green: 110 / 255, blue: 99 / 255))
    ]
}

private struct AndroidToolCell: View {
    let tool: AndroidToolItem

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(tool.tint)
                .frame(width: 40, height: 40)
            Text(tool.title)
                .font(.caption)
                .fontWeight(.bold)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 4)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct ScheduleWidgetPreview: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("本周课表").font(.caption).fontWeight(.bold)
                Spacer()
                Text("第 1 周").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(0..<3, id: \.self) { row in
                HStack(spacing: 5) {
                    ForEach(0..<5, id: \.self) { column in
                        RoundedRectangle(cornerRadius: 4)
                            .fill((row + column).isMultiple(of: 3) ? AndroidParityPalette.primaryContainer(colorScheme) : AndroidParityPalette.background(colorScheme))
                            .frame(height: 24)
                    }
                }
            }
        }
        .padding(14)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct AndroidToolPlaceholder: View {
    let title: String

    var body: some View {
        AndroidScreen {
            VStack(spacing: 24) {
                AndroidHeader(title: title)
                AndroidEmptyState(text: "该功能正在按 Android 版本迁移")
                Spacer()
            }
        }
    }
}
