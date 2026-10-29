import SwiftUI

@MainActor
final class LostFoundViewModel: ObservableObject {
    enum MutationState: Equatable {
        case idle
        case working
        case succeeded(String)
        case failed(String)

        var message: String? {
            switch self {
            case let .succeeded(message), let .failed(message): message
            case .idle, .working: nil
            }
        }
    }

    @Published private(set) var catalog = LostFoundCatalog(campuses: [], types: [])
    @Published private(set) var state: LoadableState<[LostFoundItem]> = .idle
    @Published private(set) var mutation: MutationState = .idle
    @Published private(set) var needsCampusLogin = false
    @Published private(set) var isLoggingIntoCampus = false
    @Published private(set) var myPostsState: LoadableState<[LostFoundItem]> = .idle
    @Published private(set) var currentState = 1
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published var searchQuery = ""
    @Published var selectedCampusID: String?
    @Published var selectedTypeID: String?

    let currentUserID: String
    private let remote: any LostFoundRemote
    private let campusAPI: any CampusCoreAPI
    private let demo: Bool
    private let catalogCache: JSONStore<LostFoundCatalog>
    private let itemCache: UserScopedStore
    private var currentPage = 1
    private let pageSize = 20

    init(appModel: AppModel) {
        demo = AppRuntime.isDemoSession
        campusAPI = appModel.campusAPI
        remote = demo ? DemoLostFoundRemote() : CampusLostFoundRemote(campusAPI: appModel.campusAPI)
        if case let .authenticated(user) = appModel.sessionState { currentUserID = user.studentID } else { currentUserID = "" }
        let scoped = UserScopedStore(
            store: AppPersistence.migratingFileCache(),
            userID: currentUserID.isEmpty ? "demo" : currentUserID
        )
        itemCache = scoped
        catalogCache = JSONStore(store: scoped, key: "lost-found.catalog.v1")
    }

    var filteredItems: [LostFoundItem] {
        (state.value ?? []).filter {
            $0.matches(query: searchQuery, campusID: selectedCampusID, typeID: selectedTypeID)
        }
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
        let itemsStore = JSONStore<[LostFoundItem]>(store: itemCache, key: "lost-found.items.\(currentState).v1")
        let cachedCatalog = try? await catalogCache.load()
        let cachedItems = try? await itemsStore.load()
        if let cachedCatalog { catalog = cachedCatalog }
        if let cachedItems { state = cachedItems.isEmpty ? .empty : .loaded(cachedItems) }
        do {
            async let loadedCatalog = remote.catalog()
            async let loadedPage = remote.page(state: currentState, page: 1, size: pageSize)
            let (catalogValue, pageValue) = try await (loadedCatalog, loadedPage)
            catalog = catalogValue
            try await catalogCache.save(catalogValue)
            try await itemsStore.save(pageValue.list)
            currentPage = 1
            hasMore = pageValue.pageNum < pageValue.pages
            state = pageValue.list.isEmpty ? .empty : .loaded(pageValue.list)
            needsCampusLogin = false
        } catch {
            recordAuthorizationFailure(error)
            if cachedItems == nil { state = .failed(AppErrorState(message: error.localizedDescription)) }
        }
    }

    func loginCampusService() async {
        guard !isLoggingIntoCampus else { return }
        isLoggingIntoCampus = true
        defer { isLoggingIntoCampus = false }
        do {
            try await campusAPI.refreshSession(scope: .campusCard)
            needsCampusLogin = false
            await load()
        } catch {
            mutation = .failed(error.localizedDescription)
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
            let combined = existing + page.list.filter { !ids.contains($0.id) }
            state = .loaded(combined)
            try await JSONStore<[LostFoundItem]>(
                store: itemCache,
                key: "lost-found.items.\(currentState).v1"
            ).save(combined)
        } catch {
            recordAuthorizationFailure(error)
            mutation = .failed(error.localizedDescription)
        }
    }

    func loadMyPosts() async {
        myPostsState = .loading
        do {
            let items = try await remote.ownedPosts(userID: currentUserID)
            myPostsState = items.isEmpty ? .empty : .loaded(items)
        } catch {
            recordAuthorizationFailure(error)
            myPostsState = .failed(AppErrorState(message: error.localizedDescription))
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
            recordAuthorizationFailure(error)
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
            async let list: Void = load()
            async let owned: Void = loadMyPosts()
            _ = await (list, owned)
            mutation = .succeeded("删除成功")
            return true
        } catch {
            recordAuthorizationFailure(error)
            mutation = .failed(error.localizedDescription)
            return false
        }
    }

    func clearMutation() { mutation = .idle }

    private func recordAuthorizationFailure(_ error: Error) {
        if error as? CampusWebError == .unauthorized {
            needsCampusLogin = true
        }
    }
}

struct LostFoundView: View {
    @StateObject private var model: LostFoundViewModel
    @State private var selectedItem: LostFoundItem?
    @State private var showPublish = false
    @State private var showMyPosts = false

    init(appModel: AppModel) {
        _model = StateObject(wrappedValue: LostFoundViewModel(appModel: appModel))
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 24) {
                filters
                HStack {
                    Text("共 \(model.filteredItems.count) 条记录").font(.headline)
                    Spacer()
                    Button("管理我的帖子") { showMyPosts = true }.buttonStyle(.bordered)
                }
                .padding(.horizontal, 24)
                if model.needsCampusLogin {
                    Button(model.isLoggingIntoCampus ? "正在连接…" : "重试连接校园服务") {
                        Task { await model.loginCampusService() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isLoggingIntoCampus)
                    .accessibilityIdentifier("lost-found.login-campus-service")
                }
                content
                if model.hasMore && model.filteredItems.isEmpty {
                    Button { Task { await model.loadMore() } } label: {
                        if model.isLoadingMore { ProgressView() } else { Text("加载更多") }
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.isLoadingMore)
                } else if model.isLoadingMore {
                    ProgressView().padding(24)
                }
            }
            .padding(.top, 16)
            .padding(.bottom, 104)
        }
        .accessibilityIdentifier("lost-found.screen")
        .appBackground()
        .overlay(alignment: .bottomTrailing) {
            publishButton.accessibilityIdentifier("lost-found.publish").padding(24)
        }
        .navigationTitle("失物招领")
        .searchable(text: $model.searchQuery, prompt: "搜索帖子或联系人")
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("刷新帖子", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    .disabled(model.state.isLoading)
            }
        }
        .task { await model.load() }
        .sheet(item: $selectedItem) { item in
            NavigationStack { LostFoundDetailView(item: item) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPublish) {
            NavigationStack { LostFoundPublishView(model: model, isPresented: $showPublish) }
        }
        .sheet(isPresented: $showMyPosts) {
            NavigationStack { LostFoundMyPostsView(model: model) }
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .alert("操作结果", isPresented: Binding(
            get: { !showPublish && !showMyPosts && model.mutation.message != nil },
            set: { if !$0 { model.clearMutation() } }
        )) {
            Button("确定", role: .cancel) { model.clearMutation() }
        } message: { Text(model.mutation.message ?? "") }
    }

    private var filters: some View {
        VStack(spacing: 16) {
            Picker("帖子类型", selection: Binding(
                get: { model.currentState },
                set: { value in Task { await model.switchState(value) } }
            )) {
                Text("失物招领").tag(1)
                Text("寻物启事").tag(2)
            }
            .pickerStyle(.segmented)
            LabeledContent("校区") {
                Picker("校区", selection: $model.selectedCampusID) {
                    Text("全部校区").tag(String?.none)
                    ForEach(model.catalog.campuses) { Text($0.campusName).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
            LabeledContent("物品类型") {
                Picker("物品类型", selection: $model.selectedTypeID) {
                    Text("全部类型").tag(String?.none)
                    ForEach(model.catalog.types) { Text($0.typeName).tag(Optional($0.id)) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
        .padding(.horizontal, 24)
    }

    private var publishAction: some View {
        Button { showPublish = true } label: {
            Image(systemName: "plus").font(.title2).frame(width: 28, height: 28)
        }
        .buttonBorderShape(.roundedRectangle(radius: 20))
        .controlSize(.large)
        .accessibilityLabel("发布帖子")
    }

    @ViewBuilder
    private var publishButton: some View {
        if #available(iOS 26, *) { publishAction.buttonStyle(.glassProminent) }
        else { publishAction.buttonStyle(.borderedProminent) }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .idle, .loading:
            ProgressView("加载失物招领…").padding(64)
                .accessibilityIdentifier("lost-found.loading")
        case .empty:
            ContentUnavailableView("暂无相关帖子", systemImage: "tray")
                .accessibilityIdentifier("lost-found.empty")
        case let .failed(error):
            ContentUnavailableView {
                Label("加载失败", systemImage: "wifi.exclamationmark")
            } description: { Text(error.message) } actions: {
                Button("重试") { Task { await model.load() } }.buttonStyle(.bordered)
            }
            .accessibilityIdentifier("lost-found.error")
        case .loaded:
            if model.filteredItems.isEmpty {
                ContentUnavailableView("没有匹配的帖子", systemImage: "magnifyingglass",
                                       description: Text("试试其他关键词或筛选条件。"))
            }
            ForEach(model.filteredItems) { item in
                Button { selectedItem = item } label: { itemCard(item) }
                    .buttonStyle(PressFeedbackStyle(cornerRadius: 20))
                    .padding(.horizontal, 16)
                    .accessibilityIdentifier("lost-found.item.\(item.id)")
                    .onAppear {
                        if item.id == model.filteredItems.last?.id { Task { await model.loadMore() } }
                    }
            }
        }
    }

    private func itemCard(_ item: LostFoundItem) -> some View {
        AndroidCard(radius: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.headline.bold())
                Text("联系人：\(item.linkman ?? "未知")")
                Text("联系电话：\(item.phone ?? "未知")")
                Text("校区：\(item.campusName ?? "未知")")
                Text("类型：\(item.lostType?.typeName ?? "未知")")
                Text("证件号：\(item.num1 ?? "未知")")
                Text(item.createtime ?? "未知时间").foregroundStyle(Color.secondary)
            }
            .foregroundStyle(Color.primary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
    }

}

private struct LostFoundItemRow: View {
    let item: LostFoundItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.title).font(.headline).foregroundStyle(Color.primary)
            Text([item.campusName, item.lostType?.typeName, item.createtime]
                .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.subheadline).foregroundStyle(Color.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct LostFoundDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let item: LostFoundItem
    @State private var selectedImageIndex: Int?

    var body: some View {
        Form {
            Section {
                Text(item.title).textSelection(.enabled)
            }
            Section("联系信息") {
                LabeledContent("联系人", value: item.linkman ?? "未提供")
                LabeledContent("联系电话", value: item.phone ?? "未提供")
            }
            .textSelection(.enabled)
            Section("物品信息") {
                LabeledContent("校区", value: item.campusName ?? "未提供")
                LabeledContent("类型", value: item.lostType?.typeName ?? "未提供")
                LabeledContent("证件号", value: item.num1 ?? "未提供")
                LabeledContent("发布时间", value: item.createtime ?? "未提供")
            }
            .textSelection(.enabled)
            if !item.imgs.isEmpty {
                Section("相关图片") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(Array(item.imgs.enumerated()), id: \.element.id) { index, photo in
                                Button { selectedImageIndex = index } label: {
                                    AsyncImage(url: imageURL(photo.imgPath)) { image in
                                        image.resizable().scaledToFill()
                                    } placeholder: { ProgressView() }
                                    .frame(width: 160, height: 160)
                                    .clipShape(.rect(cornerRadius: 12))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("预览第 \(index + 1) 张图片")
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("帖子详情")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .fullScreenCover(isPresented: Binding(
            get: { selectedImageIndex != nil },
            set: { if !$0 { selectedImageIndex = nil } }
        )) {
            LostFoundImageGallery(
                images: item.imgs,
                selectedIndex: Binding(get: { selectedImageIndex ?? 0 }, set: { selectedImageIndex = $0 }),
                imageURL: imageURL,
                onClose: { selectedImageIndex = nil }
            )
        }
        .accessibilityIdentifier("lost-found.detail")
    }

    private func imageURL(_ value: String) -> URL? {
        if value.hasPrefix("http") { return URL(string: value) }
        return URL(string: "https://adwmh.ahu.edu.cn\(value)")
    }
}

private struct LostFoundImageGallery: View {
    let images: [LostFoundImage]
    @Binding var selectedIndex: Int
    let imageURL: (String) -> URL?
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                    AsyncImage(url: imageURL(item.imgPath)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: { ProgressView() }
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .background(.black)
            .navigationTitle("相关图片")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成", action: onClose) } }
        }
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("lost-found.image-gallery")
    }
}

private struct LostFoundPublishView: View {
    @ObservedObject var model: LostFoundViewModel
    @Binding var isPresented: Bool
    @State private var draft = LostFoundPublishDraft()

    var body: some View {
        Form {
            Section("帖子类型") {
                Picker("帖子类型", selection: $draft.state) {
                    Text("失物招领").tag(1)
                    Text("寻物启事").tag(2)
                }
                .pickerStyle(.segmented)
            }
            Section("联系信息") {
                TextField("联系人", text: $draft.contact).textContentType(.name)
                TextField("联系电话", text: $draft.phone)
                    .keyboardType(.phonePad).textContentType(.telephoneNumber)
            }
            Section {
                TextField("描述物品及拾取或遗失地点", text: $draft.title, axis: .vertical)
                    .lineLimit(3...6)
                TextField("证件号（可选）", text: $draft.documentNumber)
                Picker("校区", selection: $draft.campusID) {
                    Text("请选择").tag(String?.none)
                    ForEach(model.catalog.campuses) { Text($0.campusName).tag(Optional($0.id)) }
                }
                Picker("物品类型", selection: $draft.typeID) {
                    Text("请选择").tag(String?.none)
                    ForEach(model.catalog.types) { Text($0.typeName).tag(Optional($0.id)) }
                }
            } header: {
                Text("物品信息")
            } footer: {
                Text("除证件号外均为必填，请尽量描述清楚物品特征。")
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("发布帖子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("取消") { isPresented = false } }
            ToolbarItem(placement: .confirmationAction) {
                Button(model.mutation == .working ? "发布中…" : "发布") {
                    Task {
                        if await model.publish(draft) {
                            model.clearMutation()
                            isPresented = false
                        }
                    }
                }
                .disabled(model.mutation == .working || draft.validationMessage != nil)
                .accessibilityIdentifier("lost-found.publish.submit")
            }
        }
        .alert("无法发布", isPresented: Binding(
            get: { if case .failed = model.mutation { return true }; return false },
            set: { if !$0 { model.clearMutation() } }
        )) {
            Button("确定", role: .cancel) { model.clearMutation() }
        } message: { Text(model.mutation.message ?? "") }
        .accessibilityIdentifier("lost-found.publish.sheet")
    }
}

private struct LostFoundMyPostsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: LostFoundViewModel
    @State private var pendingDelete: LostFoundItem?

    var body: some View {
        List {
            switch model.myPostsState {
            case .idle, .loading:
                ProgressView("加载我的帖子…")
            case .empty:
                ContentUnavailableView("暂无帖子", systemImage: "tray")
            case let .failed(error):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("重试") { Task { await model.loadMyPosts() } }.buttonStyle(.bordered)
                }
            case let .loaded(items):
                ForEach(items) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            LostFoundItemRow(item: item)
                            Text(item.state == 1 ? "失物招领" : "寻物启事").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("删除", systemImage: "trash", role: .destructive) { pendingDelete = item }
                            .labelStyle(.iconOnly)
                            .disabled(model.mutation == .working)
                    }
                }
            }
        }
        .navigationTitle("我的帖子")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .refreshable { await model.loadMyPosts() }
        .task { await model.loadMyPosts() }
        .confirmationDialog("删除这条帖子？", isPresented: Binding(
            get: { pendingDelete != nil },
            set: { if !$0 { pendingDelete = nil } }
        ), titleVisibility: .visible) {
            Button("删除", role: .destructive) {
                if let item = pendingDelete { Task { _ = await model.delete(item) } }
                pendingDelete = nil
            }
        }
        .alert("操作结果", isPresented: Binding(
            get: { model.mutation.message != nil },
            set: { if !$0 { model.clearMutation() } }
        )) {
            Button("确定", role: .cancel) { model.clearMutation() }
        } message: { Text(model.mutation.message ?? "") }
        .accessibilityIdentifier("lost-found.my-posts")
    }
}
