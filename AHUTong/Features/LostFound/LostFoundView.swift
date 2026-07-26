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
    @Published private(set) var myPostsState: LoadableState<[LostFoundItem]> = .idle
    @Published private(set) var currentState = 1
    @Published private(set) var hasMore = false
    @Published private(set) var isLoadingMore = false
    @Published var searchQuery = ""
    @Published var selectedCampusID: String?
    @Published var selectedTypeID: String?

    let currentUserID: String
    private let remote: any LostFoundRemote
    private let demo: Bool
    private let catalogCache: JSONStore<LostFoundCatalog>
    private let itemCache: UserScopedStore
    private var currentPage = 1
    private let pageSize = 20

    init(appModel: AppModel) {
        demo = AppRuntime.isDemoSession
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
        } catch {
            if cachedItems == nil { state = .failed(AppErrorState(message: error.localizedDescription)) }
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
            mutation = .failed(error.localizedDescription)
        }
    }

    func loadMyPosts() async {
        myPostsState = .loading
        do {
            let items = try await remote.ownedPosts(userID: currentUserID)
            myPostsState = items.isEmpty ? .empty : .loaded(items)
        } catch {
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
                        if searchExpanded {
                            AndroidSearchField(text: $model.searchQuery, prompt: "搜索全部信息")
                                .padding(.horizontal, 24)
                        } else {
                            filters
                        }
                        summary
                        content
                    }
                    .padding(.bottom, 104)
                }
                .scrollIndicators(.hidden)
                .accessibilityIdentifier("lost-found.screen")

                Button { showPublish = true } label: {
                    Image(systemName: "plus")
                        .font(.title.bold())
                        .foregroundStyle(AndroidParityPalette.systemTheme)
                        .frame(width: 64, height: 64)
                        .background(
                            AndroidParityPalette.primaryTone90,
                            in: RoundedRectangle(cornerRadius: 20, style: .continuous)
                        )
                        .shadow(color: .black.opacity(0.22), radius: 10, y: 6)
                }
                .buttonStyle(.plain)
                .padding(24)
                .accessibilityLabel("发布帖子")
                .accessibilityIdentifier("lost-found.publish")
            }
        }
        .task { await model.load() }
        .sheet(item: $selectedItem) {
            LostFoundDetailView(item: $0)
                .presentationDetents([.fraction(0.6)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPublish) {
            LostFoundPublishView(model: model, isPresented: $showPublish)
                .presentationDetents([.fraction(0.6)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showMyPosts) {
            LostFoundMyPostsView(model: model)
                .presentationDetents([.fraction(0.6)])
                .presentationDragIndicator(.visible)
        }
        .alert("操作结果", isPresented: mutationAlert) {
            Button("确定", role: .cancel) { model.clearMutation() }
        } message: { Text(mutationMessage) }
    }

    private var header: some View {
        HStack(spacing: 0) {
            HStack { stateChip("失物招领", value: 1); Spacer() }
                .frame(maxWidth: .infinity)
            HStack { Spacer(); stateChip("寻物启事", value: 2); Spacer() }
                .frame(maxWidth: .infinity)
            HStack {
                Spacer()
                HStack(spacing: 0) {
                    AndroidIconButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新") { Task { await model.load() } }
                    AndroidIconButton(systemName: searchExpanded ? "xmark" : "magnifyingglass", accessibilityLabel: "搜索") {
                        searchExpanded.toggle()
                        if !searchExpanded { model.searchQuery = "" }
                    }
                }
                .padding(2)
                .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
    }

    private var filters: some View {
        VStack(spacing: 24) {
            filterContainer {
                filterChip("全部校区", selected: model.selectedCampusID == nil) { model.selectedCampusID = nil }
                ForEach(model.catalog.campuses) { campus in
                    filterChip(campus.campusName, selected: model.selectedCampusID == campus.id) { model.selectedCampusID = campus.id }
                }
            }
            filterContainer {
                filterChip("全部类型", selected: model.selectedTypeID == nil) { model.selectedTypeID = nil }
                ForEach(model.catalog.types) { type in
                    filterChip(type.typeName, selected: model.selectedTypeID == type.id) { model.selectedTypeID = type.id }
                }
            }
        }
    }

    private func filterContainer<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) { content() }
                .padding(8)
        }
        .scrollIndicators(.hidden)
        .background(AndroidParityPalette.surface(colorScheme), in: Capsule())
        .padding(.horizontal, 16)
    }

    private var summary: some View {
        HStack {
            Text(summaryText).font(.headline)
            Spacer()
            Button("管理我的帖子") { showMyPosts = true }
                .buttonStyle(.plain)
                .foregroundStyle(AndroidParityPalette.systemTheme)
        }
        .padding(.horizontal, 24)
    }

    private var summaryText: String {
        if searchExpanded && !model.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "搜索「\(model.searchQuery)」到 \(model.filteredItems.count) 条记录"
        }
        return "共 \(model.filteredItems.count) 条记录"
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
        AndroidCard(radius: 4) {
            VStack(alignment: .leading, spacing: 8) {
                Text(item.title).font(.headline.bold())
                Text("联系人：\(item.linkman ?? "未知")")
                Text("联系电话：\(item.phone ?? "未知")")
                Text("校区：\(item.campusName ?? "未知")")
                Text("类型：\(item.lostType?.typeName ?? "未知")")
                Text("证件号：\(item.num1 ?? "未知")")
                Text(item.createtime ?? "未知时间").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .padding(.horizontal, 16)
    }

    private func stateChip(_ text: String, value: Int) -> some View {
        let selected = model.currentState == value
        return Button { Task { await model.switchState(value) } } label: {
            Text(text)
                .font(.system(size: 18))
                .foregroundStyle(.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AndroidParityPalette.primaryTone90 : Color.clear, in: RoundedRectangle(cornerRadius: 8))
                .overlay {
                    if !selected {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AndroidParityPalette.separator(colorScheme), lineWidth: 1)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private func filterChip(_ text: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(text)
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AndroidParityPalette.primaryTone90 : Color.clear, in: Capsule())
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
    @State private var selectedImageIndex: Int?

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item.title)
                        .font(.title2.bold())
                        .fixedSize(horizontal: false, vertical: true)
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
                                    Button {
                                        selectedImageIndex = item.imgs.firstIndex(where: { $0.id == image.id })
                                    } label: {
                                        AsyncImage(url: imageURL(image.imgPath)) { image in
                                            image.resizable().scaledToFill()
                                        } placeholder: { ProgressView() }
                                        .frame(width: 180, height: 180)
                                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(24)
            }
        }
        .fullScreenCover(
            isPresented: Binding(
                get: { selectedImageIndex != nil },
                set: { if !$0 { selectedImageIndex = nil } }
            )
        ) {
            LostFoundImageGallery(
                images: item.imgs,
                selectedIndex: Binding(
                    get: { selectedImageIndex ?? 0 },
                    set: { selectedImageIndex = $0 }
                ),
                imageURL: imageURL,
                onClose: { selectedImageIndex = nil }
            )
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

private struct LostFoundImageGallery: View {
    let images: [LostFoundImage]
    @Binding var selectedIndex: Int
    let imageURL: (String) -> URL?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()
            TabView(selection: $selectedIndex) {
                ForEach(Array(images.enumerated()), id: \.element.id) { index, item in
                    AsyncImage(url: imageURL(item.imgPath)) { image in
                        image.resizable().scaledToFit()
                    } placeholder: {
                        ProgressView().tint(.white)
                    }
                    .tag(index)
                    .padding(.vertical, 56)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.headline.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .padding(16)
            .accessibilityLabel("关闭图片预览")
        }
        .accessibilityIdentifier("lost-found.image-gallery")
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
                    Text("发布帖子").font(.title2.bold())
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
                            .background(AndroidParityPalette.systemTheme, in: Capsule())
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
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.secondary.opacity(0.75), lineWidth: 1)
            }
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
                .foregroundStyle(Color.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(selected ? AndroidParityPalette.primaryTone90 : Color.secondary.opacity(0.1), in: Capsule())
        }
        .buttonStyle(.plain)
    }
}

private struct LostFoundMyPostsView: View {
    @ObservedObject var model: LostFoundViewModel

    var body: some View {
        AndroidScreen {
            VStack(alignment: .leading, spacing: 0) {
                AndroidHeader(title: "管理我的帖子", large: true)
                switch model.myPostsState {
                case .idle, .loading:
                    ProgressView("加载我的帖子…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case .empty:
                    AndroidEmptyState(text: "暂无帖子")
                    Spacer()
                case let .failed(error):
                    VStack(spacing: 16) {
                        Text(error.message)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(AndroidParityPalette.error)
                        Button("重试") { Task { await model.loadMyPosts() } }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(32)
                case let .loaded(items):
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(items) { item in
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.title).font(.headline)
                                        Text(item.state == 1 ? "失物招领" : "寻物启事")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        Text(item.createtime ?? "").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("删除", role: .destructive) { Task { _ = await model.delete(item) } }
                                }
                                .padding(16)
                                .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
                            }
                        }
                        .padding(16)
                    }
                }
            }
        }
        .task { await model.loadMyPosts() }
        .accessibilityIdentifier("lost-found.my-posts")
    }
}
