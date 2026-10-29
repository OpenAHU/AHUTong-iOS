import SwiftUI

struct ToolsView: View {
    @ObservedObject var appModel: AppModel
    var onOpenSchedule: () -> Void = {}
    var onEditHome: () -> Void = {}
    @State private var searchText = ""
    @State private var showsWidgetGuide = false
    @State private var widgetSnapshot: ScheduleWidgetSnapshot?

    private var query: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var matchingTools: [ToolItem] {
        ToolItem.allCases.filter { query.isEmpty || $0.title.localizedStandardContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(ToolCategory.allCases, id: \.self) { category in
                    let tools = matchingTools.filter { $0.category == category }
                    if !tools.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(category.rawValue)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.secondary)
                                .padding(.horizontal, 4)
                                .accessibilityAddTraits(.isHeader)
                            LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())], spacing: 10) {
                                ForEach(tools) { tool in
                                    NavigationLink { ToolDestination(tool: tool, appModel: appModel) } label: { card(for: tool) }
                                        .buttonStyle(PressFeedbackStyle(cornerRadius: 18))
                                        .accessibilityLabel(tool.title)
                                        .accessibilityIdentifier("tools.\(tool.id)")
                                        .accessibilityHint(category.rawValue)
                                }
                            }
                        }
                    }
                }
                if query.isEmpty {
                    Button {
                        showsWidgetGuide = true
                    } label: {
                        Label("添加课表小组件", systemImage: "rectangle.grid.2x2")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.roundedRectangle(radius: 16))
                    .accessibilityIdentifier("tools.widget-add")
                }
            }
            .padding(16)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("tools.grid")
        .overlay {
            if matchingTools.isEmpty { ContentUnavailableView.search(text: query) }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索小工具")
        .navigationTitle("小工具")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("编辑首页", systemImage: "square.grid.2x2") { onEditHome() }
                    .accessibilityIdentifier("tools.edit-home")
            }
        }
        .sheet(isPresented: $showsWidgetGuide) { widgetGuide }
    }

    private func card(for tool: ToolItem) -> some View {
        HStack(spacing: 10) {
            ToolIcon(tool: tool)
                .font(.system(size: 22))
                .frame(width: 28)
            Text(tool.title)
                .font(.body.weight(.medium))
                .foregroundStyle(Color.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: 18))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color(uiColor: .separator).opacity(0.5), lineWidth: 1)
                .allowsHitTesting(false)
        }
        .contentShape(.rect(cornerRadius: 18))
    }

    private var widgetGuide: some View {
        NavigationStack {
            Form {
                Section {
                    Label("长按主屏幕空白处", systemImage: "hand.tap")
                    Label("点击“编辑”或“+”", systemImage: "plus.circle")
                    Label("搜索“安大通课表”并添加", systemImage: "rectangle.grid.2x2")
                } header: {
                    Text("添加课表小组件")
                } footer: {
                    Text("长按已添加的小组件，选择“编辑小组件”可调整深浅色。")
                }
                Section("课表同步") {
                    if let issue = ScheduleWidgetSnapshotStore.sharing.issue {
                        Label(issue.guidance, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("tools.widget-guide.sharing-issue")
                    } else {
                        Text(widgetSnapshot?.synchronizationSummary ?? "正在检查课表同步…")
                            .foregroundStyle(.secondary)
                            .accessibilityIdentifier("tools.widget-guide.sync-status")
                        Button("打开课表同步") {
                            showsWidgetGuide = false
                            onOpenSchedule()
                        }
                        .accessibilityIdentifier("tools.widget-guide.sync")
                    }
                }
                Section {
                    ShareLink(item: ScheduleWidgetSnapshotStore.sharing.diagnosticSummary
                        + (widgetSnapshot.map { "\n" + $0.diagnosticSummary } ?? "")) {
                        Label("分享安装检查", systemImage: "square.and.arrow.up")
                    }
                    .accessibilityIdentifier("tools.widget-guide.share-check")
                } footer: {
                    Text("检查不含账号或课程内容。重签安装需保留小组件扩展，并授权 App 和扩展访问同一 App Group。")
                }
            }
            .navigationTitle("课表小组件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showsWidgetGuide = false }
                        .accessibilityIdentifier("tools.widget-guide.done")
                }
            }
            .task { widgetSnapshot = await AppRuntime.widgetSnapshotStore.load().resolved(at: Date()) }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .accessibilityIdentifier("tools.widget-guide")
    }

}
