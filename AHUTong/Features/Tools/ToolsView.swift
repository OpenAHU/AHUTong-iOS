import SwiftUI

struct ToolsView: View {
    @Environment(\.colorScheme) private var colorScheme
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 4)
    let appModel: AppModel
    let homeEditEnabled: Bool
    let onEditHome: () -> Void
    let onOpenSchedule: () -> Void
    @State private var showsWidgetGuide = false
    @State private var widgetSnapshot: ScheduleWidgetSnapshot?
    @State private var homeLayout = HomeWidgetLayout()
    private let layoutStore: JSONStore<HomeWidgetLayout>

    init(
        appModel: AppModel,
        homeEditEnabled: Bool = true,
        onOpenSchedule: @escaping () -> Void = {},
        onEditHome: @escaping () -> Void = {}
    ) {
        self.appModel = appModel
        self.homeEditEnabled = homeEditEnabled
        self.onEditHome = onEditHome
        self.onOpenSchedule = onOpenSchedule
        let userID = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "guest" }
        layoutStore = JSONStore(
            store: UserScopedStore(store: AppPersistence.migratingDefaults(), userID: userID),
            key: "home.widget-layout.v2"
        )
    }

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(spacing: 24) {
                    AndroidHeader(title: "小工具") {
                        if homeEditEnabled {
                            NativeHeaderIconButton(systemName: "pencil", accessibilityLabel: "编辑首页", action: onEditHome)
                                .accessibilityIdentifier("tools.edit-home")
                        }
                    }

                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(visibleTools) { tool in
                            destination(for: tool)
                        }
                    }
                    .padding(.horizontal, 16)

                    if visibleTools.isEmpty {
                        AndroidEmptyState(text: "所有工具都已放到首页")
                            .padding(.horizontal, 16)
                    }

                    desktopWidgetCard
                        .padding(.horizontal, 16)
                }
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("小工具")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showsWidgetGuide) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("添加课表小组件").font(.title2.bold())
                        Label("长按 iPhone 主屏幕空白处", systemImage: "hand.tap")
                        Label("点击左上角“编辑”或“+”", systemImage: "plus.circle")
                        Label("搜索“安大通课表”，选择尺寸并添加", systemImage: "rectangle.grid.2x2")
                        Label("长按已添加的课表，选“编辑小组件”调整深浅色", systemImage: "circle.lefthalf.filled")
                        if let issue = ScheduleWidgetSnapshotStore.sharing.issue {
                            Label(issue.guidance, systemImage: "exclamationmark.triangle")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("tools.widget-guide.sharing-issue")
                        } else {
                            Text(widgetSnapshot?.synchronizationSummary ?? "正在检查课表同步…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("tools.widget-guide.sync-status")
                            Button("打开课表同步") {
                                showsWidgetGuide = false
                                onOpenSchedule()
                            }
                            .accessibilityIdentifier("tools.widget-guide.sync")
                        }
                        ShareLink(item: ScheduleWidgetSnapshotStore.sharing.diagnosticSummary
                            + (widgetSnapshot.map { "\n" + $0.diagnosticSummary } ?? "")) {
                            Label("分享安装检查", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("tools.widget-guide.share-check")
                        Text("检查不含账号、课表或设备标识。Sideloadly 重签时，保留小组件扩展，并让 App 和扩展使用同一团队及同一 App Group。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Text("未找到安大通？重签时保留小组件扩展，安装后先打开 App。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(24)
                }
                .task {
                    widgetSnapshot = await AppRuntime.widgetSnapshotStore.load().resolved(at: Date())
                }
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showsWidgetGuide = false }
                            .accessibilityIdentifier("tools.widget-guide.done")
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .accessibilityIdentifier("tools.widget-guide")
        }
        .task { homeLayout = (try? await layoutStore.load()) ?? HomeWidgetLayout() }
    }

    private var visibleTools: [AndroidToolItem] {
        AndroidToolItem.visible(in: homeLayout)
    }

    @ViewBuilder
    private func destination(for tool: AndroidToolItem) -> some View {
        NavigationLink {
            switch tool.id {
            case "bathroom": BathroomPaymentView(appModel: appModel).androidDetailScreen()
            case "electricity": ElectricityPaymentView(appModel: appModel).androidDetailScreen()
            case "program-completion": ProgramCompletionView(appModel: appModel).modifier(NativeServiceDetailModifier())
            case "card-billing": CardBillingView(appModel: appModel).modifier(NativeServiceDetailModifier())
            case "grade": GradeView(appModel: appModel).androidDetailScreen()
            case "exam": ExamView(appModel: appModel).androidDetailScreen()
            case "network-recharge": NetworkRechargeView(appModel: appModel).androidDetailScreen()
            case "phone-book": PhoneBookView()
            case "student-mail": StudentMailView(appModel: appModel)
            case "school-calendar": SchoolCalendarView().androidDetailScreen()
            case "weather": WeatherView().androidDetailScreen()
            case "study-repository": StudyRepositoryView().androidDetailScreen()
            case "free-classroom": FreeClassroomView(appModel: appModel).androidDetailScreen()
            case "lost-found": LostFoundView(appModel: appModel).androidDetailScreen()
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

                Button("添加") { showsWidgetGuide = true }
                    .accessibilityIdentifier("tools.widget-add")
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

struct AndroidToolItem: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color

    var homeWidgetID: String {
        switch id {
        case "phone-book": "phone_book"
        case "school-calendar": "school_calendar"
        case "free-classroom": "free_classroom"
        case "lost-found": "lost_found"
        case "study-repository": "repository"
        default: id
        }
    }

    static let all = [
        AndroidToolItem(id: "bathroom", title: "浴室缴费", systemImage: "shower.fill", tint: Color(red: 38 / 255, green: 166 / 255, blue: 154 / 255)),
        AndroidToolItem(id: "electricity", title: "电控缴费", systemImage: "bolt.fill", tint: Color(red: 1, green: 179 / 255, blue: 0)),
        AndroidToolItem(id: "grade", title: "成绩单", systemImage: "chart.bar.doc.horizontal", tint: .yellow),
        AndroidToolItem(id: "phone-book", title: "电话本", systemImage: "person.crop.rectangle.stack", tint: Color(red: 0, green: 150 / 255, blue: 136 / 255)),
        AndroidToolItem(id: "exam", title: "考场查询", systemImage: "mappin.and.ellipse", tint: AndroidParityPalette.success),
        AndroidToolItem(id: "school-calendar", title: "校历", systemImage: "square.grid.2x2", tint: .purple),
        AndroidToolItem(id: "free-classroom", title: "空闲教室", systemImage: "building.2", tint: Color(red: 3 / 255, green: 169 / 255, blue: 244 / 255)),
        AndroidToolItem(id: "lost-found", title: "失物招领", systemImage: AndroidParitySymbol.lostAndFoundBag, tint: Color(red: 25 / 255, green: 118 / 255, blue: 210 / 255)),
        AndroidToolItem(id: "weather", title: "天气", systemImage: "sun.max.fill", tint: AndroidParityPalette.warning),
        AndroidToolItem(id: "study-repository", title: "学习资料", systemImage: "doc.on.doc", tint: Color(red: 141 / 255, green: 110 / 255, blue: 99 / 255)),
        AndroidToolItem(id: "program-completion", title: "培养方案", systemImage: "graduationcap", tint: .indigo),
        AndroidToolItem(id: "card-billing", title: "校园卡账单", systemImage: "list.bullet.rectangle", tint: .teal),
        AndroidToolItem(id: "student-mail", title: "校园邮箱", systemImage: "envelope", tint: .blue),
        AndroidToolItem(id: "network-recharge", title: "网费充值", systemImage: "network", tint: Color(red: 30 / 255, green: 136 / 255, blue: 229 / 255))
    ]

    static func visible(in layout: HomeWidgetLayout) -> [Self] {
        let placed = Set(layout.slots.compactMap { $0 })
        return all.filter { !placed.contains($0.homeWidgetID) }
    }
}

private struct AndroidToolCell: View {
    let tool: AndroidToolItem

    var body: some View {
        VStack(spacing: 8) {
            toolIcon
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

    @ViewBuilder
    private var toolIcon: some View {
        if tool.id == "lost-found" {
            ZStack {
                Image(systemName: AndroidParitySymbol.lostAndFoundBag)
                    .font(.system(size: 36, weight: .regular))
                Image(systemName: AndroidParitySymbol.lostAndFoundQuestion)
                    .font(.system(size: 13, weight: .semibold))
                    .offset(y: 2)
            }
        } else {
            Image(systemName: tool.systemImage)
                .font(.system(size: 36, weight: .regular))
        }
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

private struct NativeServiceDetailModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.navigationBarTitleDisplayMode(.inline)
            .toolbar(.visible, for: .navigationBar)
            .toolbar(.hidden, for: .tabBar)
            .background(NativeNavigationGestureBridge())
    }
}
