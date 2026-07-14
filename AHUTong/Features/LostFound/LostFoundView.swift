import SwiftUI

@MainActor
final class LostFoundViewModel: ObservableObject {
    enum MutationState: Equatable {
        case idle
        case working
        case succeeded(String)
        case failed(String)
    }

    @Published private(set) var catalog = LostFoundCatalog(campuses: [], types: [])
    @Published private(set) var state: LoadableState<[LostFoundItem]> = .idle
    @Published private(set) var mutation: MutationState = .idle
    @Published private(set) var currentState = 1
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published var searchQuery = ""
    @Published var selectedCampusID: String?
    @Published var selectedTypeID: String?

    let currentUserID: String
    private let remote: any LostFoundRemote
    private let demo: Bool
    private var currentPage = 1
    private let pageSize = 20

    init(appModel: AppModel) {
        demo = ProcessInfo.processInfo.arguments.contains("--demo-session")
        remote = demo ? DemoLostFoundRemote() : CampusLostFoundRemote(campusAPI: appModel.campusAPI)
        if case let .authenticated(user) = appModel.sessionState { currentUserID = user.studentID } else { currentUserID = "" }
    }

    var filteredItems: [LostFoundItem] {
        (state.value ?? []).filter {
            $0.matches(query: searchQuery, campusID: selectedCampusID, typeID: selectedTypeID)
        }
    }

    var myPosts: [LostFoundItem] {
        (state.value ?? []).filter { $0.pubuser?.idNumber == currentUserID }
    }

    func load() async {
        state = .loading
        if demo {
            switch DemoDataState.current {
            case .loading: return
            case .empty:
                catalog = (try? await remote.catalog()) ?? catalog
                state = .empty
                return
            case .error:
                state = .failed(AppErrorState(message: "Mock 场景：接口返回 500"))
                return
            case .normal: break
            }
        }
        do {
            async let loadedCatalog = remote.catalog()
            async let loadedPage = remote.page(state: currentState, page: 1, size: pageSize)
            let (catalogValue, pageValue) = try await (loadedCatalog, loadedPage)
            catalog = catalogValue
            currentPage = 1
            hasMore = pageValue.pageNum < pageValue.pages
            state = pageValue.list.isEmpty ? .empty : .loaded(pageValue.list)
        } catch {
            state = .failed(AppErrorState(message: error.localizedDescription))
        }
    }

    func switchState(_ value: Int) async {
        guard currentState != value else { return }
        currentState = value
        searchQuery = ""
        selectedCampusID = nil
        selectedTypeID = nil
        await load()
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, let existing = state.value else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await remote.page(state: currentState, page: currentPage + 1, size: pageSize)
            currentPage = page.pageNum
            hasMore = page.pageNum < page.pages
            let ids = Set(existing.map(\.id))
            state = .loaded(existing + page.list.filter { !ids.contains($0.id) })
        } catch {
            mutation = .failed(error.localizedDescription)
        }
    }

    func publish(_ draft: LostFoundPublishDraft) async -> Bool {
        if let message = draft.validationMessage {
            mutation = .failed(message)
            return false
        }
        mutation = .working
        do {
            _ = try await remote.publish(draft)
            currentState = draft.state
            await load()
            mutation = .succeeded("发布成功")
            return true
        } catch {
            mutation = .failed(error.localizedDescription)
            return false
        }
    }

    func delete(_ item: LostFoundItem) async -> Bool {
        guard item.pubuser?.idNumber == currentUserID else {
            mutation = .failed("只能删除自己发布的帖子")
            return false
        }
        mutation = .working
        do {
            try await remote.delete(id: item.id)
            await load()
            mutation = .succeeded("删除成功")
            return true
        } catch {
            mutation = .failed(error.localizedDescription)
            return false
        }
    }

    func clearMutation() { mutation = .idle }
}

struct LostFoundView: View {
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var model: LostFoundViewModel
    @State private var searchExpanded = false
    @State private var selectedItem: LostFoundItem?
    @State private var showPublish = false
    @State private var showMyPosts = false

    init(appModel: AppModel) {
        _model = StateObject(wrappedValue: LostFoundViewModel(appModel: appModel))
    }

    var body: some View {
        AndroidScreen {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 24) {
                        header
                        if searchExpanded { AndroidSearchField(text: $model.searchQuery, prompt: "搜索帖子") }
                        filters
                        content
                    }
                    .padding(.bottom, 104)
                }
                .scrollIndicators(.hidden)

                Button { showPublish = true } label: {
                    Image(systemName: "plus")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 64, height: 64)
                        .background(AndroidParityPalette.brand, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(24)
                .accessibilityIdentifier("lost-found.publish")
            }
        }
        .task { await model.load() }
        .sheet(item: $selectedItem) { LostFoundDetailView(item: $0) }
        .sheet(isPresented: $showPublish) { LostFoundPublishView(model: model, isPresented: $showPublish) }
        .sheet(isPresented: $showMyPosts) { LostFoundMyPostsView(model: model) }
        .alert("操作结果", isPresented: mutationAlert) {
            Button("确定", role: .cancel) { model.clearMutation() }
        } message: { Text(mutationMessage) }
        .accessibilityIdentifier("lost-found.screen")
    }

    private var header: some View {
        HStack(spacing: 8) {
            stateChip("失物招领", value: 1)
            stateChip("寻物启事", value: 2)
            Spacer()
            HStack(spacing: 0) {
                AndroidIconButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新") { Task { await model.load() } }
                AndroidIconButton(systemName: searchExpanded ? "xmark" : "magnifyingglass", accessibilityLabel: "搜索") {
                    searchExpanded.toggle()
                    if !searchExpanded { model.searchQuery = "" }
                }
                AndroidIconButton(systemName: "person.crop.rectangle.stack", accessibilityLabel: "管理我的帖子") { showMyPosts = true }
            }
            .padding(2)
            .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var filters: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    filterChip("全部校区", selected: model.selectedCampusID == nil) { model.selectedCampusID = nil }
                    ForEach(model.catalog.campuses) { campus in
                        filterChip(campus.campusName, selected: model.selectedCampusID == campus.id) { model.selectedCampusID = campus.id }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    filterChip("全部类型", selected: model.selectedTypeID == nil) { model.selectedTypeID = nil }
                    ForEach(model.catalog.types) { type in
                        filterChip(type.typeName, selected: model.selectedTypeID == type.id) { model.selectedTypeID = type.id }
                    }
                }
                .padding(.horizontal, 24)
            }
            .scrollIndicators(.hidden)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("加载失物招领…")
                .padding(64)
                .accessibilityIdentifier("lost-found.loading")
        case .empty:
            AndroidEmptyState(text: "暂无相关帖子").accessibilityIdentifier("lost-found.empty")
        case let .failed(error):
            VStack(spacing: 12) {
                Text("加载失败").font(.headline)
                Text(error.message).font(.caption).foregroundStyle(.secondary)
                Button("重试") { Task { await model.load() } }
            }
            .padding(48)
            .accessibilityIdentifier("lost-found.error")
        case .loaded:
            if model.filteredItems.isEmpty {
                AndroidEmptyState(text: "没有符合筛选条件的帖子")
            } else {
                ForEach(model.filteredItems) { item in
                    Button { selectedItem = item } label: { itemCard(item) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("lost-found.item.\(item.id)")
                        .onAppear {
                            if item.id == model.filteredItems.last?.id { Task { await model.loadMore() } }
                        }
                }
                if model.isLoadingMore { ProgressView().padding(24) }
            }
        }
    }

    private func itemCard(_ item: LostFoundItem) -> some View {
        AndroidCard(radius: 32) {
            VStack(alignment: .leading, spacing: 10) {
                Text(item.title).font(.headline.bold())
                Text("联系人：\(item.linkman ?? "未知")")
                Text("联系电话：\(item.phone ?? "未知")")
                Text("校区：\(item.campusName ?? "未知")")
                Text("类型：\(item.lostType?.typeName ?? "未知")")
                Text("证件号：\(item.num1 ?? "未知")")
                Text(item.createtime ?? "未知时间").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
        }
        .padding(.horizontal, 16)
    }

    private func stateChip(_ text: String, value: Int) -> some View {
        filterChip(text, selected: model.currentState == value) { Task { await model.switchState(value) } }
            .font(.title3)
    }

    private func filterChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .fontWeight(selected ? .bold : .regular)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AndroidParityPalette.brand : AndroidParityPalette.surface(colorScheme), in: Capsule())
        }
        .buttonStyle(.plain)
    }

    private var mutationAlert: Binding<Bool> {
        Binding(
            get: {
                if case .succeeded = model.mutation { return true }
                if case .failed = model.mutation { return true }
                return false
            },
            set: { if !$0 { model.clearMutation() } }
        )
    }

    private var mutationMessage: String {
        switch model.mutation {
        case let .succeeded(message), let .failed(message): message
        default: ""
        }
    }
}

private struct LostFoundDetailView: View {
    let item: LostFoundItem

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    AndroidHeader(title: item.title, large: true)
                    detail("联系人", item.linkman)
                    detail("联系电话", item.phone)
                    detail("校区", item.campusName)
                    detail("类型", item.lostType?.typeName)
                    detail("发布时间", item.createtime)
                    detail("证件号", item.num1)
                    if !item.imgs.isEmpty {
                        Text("相关图片").font(.headline)
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(item.imgs) { image in
                                    AsyncImage(url: imageURL(image.imgPath)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: { ProgressView() }
                                    .frame(width: 180, height: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .accessibilityIdentifier("lost-found.detail")
    }

    private func detail(_ label: String, _ value: String?) -> some View {
        Text("\(label)：\(value ?? "未知")")
    }

    private func imageURL(_ value: String) -> URL? {
        if value.hasPrefix("http") { return URL(string: value) }
        return URL(string: "https://adwmh.ahu.edu.cn\(value)")
    }
}

private struct LostFoundPublishView: View {
    @ObservedObject var model: LostFoundViewModel
    @Binding var isPresented: Bool
    @State private var draft = LostFoundPublishDraft()

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("*目前智慧安大图片功能有时无法使用，请大家文字描述尽量详尽")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    AndroidHeader(title: "发布帖子", large: true)
                    field("联系人 *", text: $draft.contact)
                    field("联系电话 *", text: $draft.phone)
                    field("描述内容 *", text: $draft.title, axis: .vertical)
                    field("证件号（可选）", text: $draft.documentNumber)
                    selector("选择校区") {
                        ForEach(model.catalog.campuses) { campus in
                            selectionChip(campus.campusName, selected: draft.campusID == campus.id) { draft.campusID = campus.id }
                        }
                    }
                    selector("选择类型") {
                        ForEach(model.catalog.types) { type in
                            selectionChip(type.typeName, selected: draft.typeID == type.id) { draft.typeID = type.id }
                        }
                    }
                    selector("选择事件类型") {
                        selectionChip("失物招领", selected: draft.state == 1) { draft.state = 1 }
                        selectionChip("寻物启事", selected: draft.state == 2) { draft.state = 2 }
                    }
                    Button {
                        Task { if await model.publish(draft) { isPresented = false } }
                    } label: {
                        Text(model.mutation == .working ? "发布中…" : "发布")
                            .font(.headline)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(14)
                            .background(AndroidParityPalette.brand, in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(model.mutation == .working)
                    .accessibilityIdentifier("lost-found.publish.submit")
                }
                .padding(24)
            }
        }
        .accessibilityIdentifier("lost-found.publish.sheet")
    }

    private func field(_ title: String, text: Binding<String>, axis: Axis = .horizontal) -> some View {
        TextField(title, text: text, axis: axis)
            .padding(16)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func selector<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            ScrollView(.horizontal) { HStack(spacing: 8) { content() } }.scrollIndicators(.hidden)
        }
    }

    private func selectionChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AndroidParityPalette.brand : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LostFoundMyPostsView: View {
    @ObservedObject var model: LostFoundViewModel

    var body: some View {
        AndroidScreen {
            VStack(alignment: .leading, spacing: 16) {
                AndroidHeader(title: "管理我的帖子", large: true)
                if model.myPosts.isEmpty {
                    AndroidEmptyState(text: "暂无帖子")
                } else {
                    ForEach(model.myPosts) { item in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(item.title).font(.headline)
                                Text(item.createtime ?? "").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button("删除", role: .destructive) { Task { _ = await model.delete(item) } }
                        }
                        .padding(16)
                    }
                }
                Spacer()
            }
            .padding(24)
        }
        .accessibilityIdentifier("lost-found.my-posts")
    }
}
