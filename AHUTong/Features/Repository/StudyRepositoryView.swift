import QuickLook
import SwiftUI

@MainActor
final class StudyRepositoryViewModel: ObservableObject {
    @Published private(set) var state: LoadableState<RepositoryDirectorySnapshot> = .idle
    @Published private(set) var currentPath = ""
    @Published private(set) var downloadedFiles: [DownloadedStudyFile] = []
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published var selectedRepositoryID = StudyRepositoryCatalog.repositories[0].id
    @Published var alertMessage: String?

    let service: StudyRepositoryService

    init(service: StudyRepositoryService = .live()) {
        self.service = service
    }

    var selectedRepository: StudyRepositoryConfiguration {
        StudyRepositoryCatalog.repository(id: selectedRepositoryID)
            ?? StudyRepositoryCatalog.repositories[0]
    }

    func start() async {
        await refreshDownloads()
        await load()
    }

    func selectRepository(_ id: String) async {
        guard id != selectedRepositoryID else { return }
        selectedRepositoryID = id
        currentPath = ""
        await load()
    }

    func openDirectory(_ item: GitHubContentItem) async {
        guard item.isDirectory else { return }
        currentPath = item.path
        await load()
    }

    func goUp() async {
        guard !currentPath.isEmpty else { return }
        currentPath = currentPath
            .split(separator: "/")
            .dropLast()
            .joined(separator: "/")
        await load()
    }

    func load(policy: RepositoryLoadPolicy = .cacheFirst) async {
        state = .loading
        do {
            let snapshot = try await service.loadDirectory(
                repositoryID: selectedRepositoryID,
                path: currentPath,
                policy: policy
            )
            state = snapshot.items.isEmpty ? .empty : .loaded(snapshot)
        } catch {
            state = .failed(
                AppErrorState(
                    title: "资料目录加载失败",
                    message: "请检查网络后重试；成功访问过的目录会保留离线缓存。"
                )
            )
        }
    }

    func download(_ item: GitHubContentItem) async {
        guard downloadProgress[item.id] == nil else { return }
        downloadProgress[item.id] = 0
        do {
            _ = try await service.download(
                repositoryID: selectedRepositoryID,
                item: item
            ) { [weak self] value in
                await MainActor.run {
                    self?.downloadProgress[item.id] = value
                }
            }
            downloadProgress[item.id] = nil
            await refreshDownloads()
        } catch is CancellationError {
            downloadProgress[item.id] = nil
        } catch {
            downloadProgress[item.id] = nil
            alertMessage = "下载失败，请稍后重试。"
        }
    }

    func refreshDownloads() async {
        do {
            downloadedFiles = try await service.downloadedFiles()
        } catch {
            alertMessage = "本地下载记录读取失败。"
        }
    }

    func downloadedFile(for item: GitHubContentItem) -> DownloadedStudyFile? {
        downloadedFiles.first {
            $0.repositoryID == selectedRepositoryID && $0.path == item.path
        }
    }
}

struct StudyRepositoryView: View {
    @StateObject private var model: StudyRepositoryViewModel
    @State private var previewURL: URL?

    init(service: StudyRepositoryService = .live()) {
        _model = StateObject(wrappedValue: StudyRepositoryViewModel(service: service))
    }

    var body: some View {
        List {
            Section("资料仓库") {
                Picker(
                    "学院",
                    selection: Binding(
                        get: { model.selectedRepositoryID },
                        set: { id in Task { await model.selectRepository(id) } }
                    )
                ) {
                    ForEach(StudyRepositoryCatalog.repositories) { repository in
                        Text(repository.name).tag(repository.id)
                    }
                }

                Link(destination: model.selectedRepository.githubURL) {
                    Label("查看 GitHub 来源仓库", systemImage: "link")
                }
            }

            if !model.currentPath.isEmpty {
                Section {
                    Button {
                        Task { await model.goUp() }
                    } label: {
                        Label("返回上一级", systemImage: "arrow.up.left")
                    }
                    Text(model.currentPath)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }

            directoryContent
        }
        .navigationTitle("学习资料")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    RepositoryDownloadsView(service: model.service)
                } label: {
                    Label("已下载", systemImage: "arrow.down.circle")
                }
                .accessibilityIdentifier("repository.downloads")
            }
        }
        .refreshable { await model.load(policy: .refresh) }
        .quickLookPreview($previewURL)
        .task { await model.start() }
        .alert(
            "提示",
            isPresented: Binding(
                get: { model.alertMessage != nil },
                set: { if !$0 { model.alertMessage = nil } }
            )
        ) {
            Button("知道了", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    @ViewBuilder
    private var directoryContent: some View {
        switch model.state {
        case .idle, .loading:
            Section {
                HStack {
                    Spacer()
                    ProgressView("正在加载目录")
                    Spacer()
                }
            }
        case let .loaded(snapshot):
            Section {
                ForEach(snapshot.items) { item in
                    RepositoryContentRow(
                        item: item,
                        downloaded: model.downloadedFile(for: item),
                        progress: model.downloadProgress[item.id],
                        openDirectory: { Task { await model.openDirectory(item) } },
                        download: { Task { await model.download(item) } },
                        preview: { previewURL = $0 }
                    )
                }
            } header: {
                HStack {
                    Text("目录")
                    Spacer()
                    Text(sourceLabel(snapshot))
                }
            }
        case .empty:
            Section {
                ContentUnavailableView(
                    "目录为空",
                    systemImage: "folder",
                    description: Text("此目录暂时没有公开资料。")
                )
            }
        case let .failed(error):
            Section {
                ContentUnavailableView {
                    Label(error.title, systemImage: "wifi.exclamationmark")
                } description: {
                    Text(error.message)
                } actions: {
                    Button("重试") {
                        Task { await model.load(policy: .refresh) }
                    }
                }
            }
        }
    }

    private func sourceLabel(_ snapshot: RepositoryDirectorySnapshot) -> String {
        switch snapshot.source {
        case .remote: "刚刚更新"
        case .cache: "本地缓存"
        case .staleCache: "离线缓存"
        }
    }
}

private struct RepositoryContentRow: View {
    let item: GitHubContentItem
    let downloaded: DownloadedStudyFile?
    let progress: Double?
    let openDirectory: () -> Void
    let download: () -> Void
    let preview: (URL) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item.name))
                .foregroundStyle(item.isDirectory ? .yellow : .accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(item.name)
                    .lineLimit(2)
                if !item.isDirectory, item.size > 0 {
                    Text(formatByteCount(item.size))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let progress {
                    ProgressView(value: progress)
                    Text("正在下载 \(Int(progress * 100))%")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if item.isDirectory {
                Button(action: openDirectory) {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("打开 \(item.name)")
            } else if let downloaded {
                Button {
                    preview(downloaded.localURL)
                } label: {
                    Image(systemName: "doc.text.magnifyingglass")
                }
                .accessibilityLabel("预览 \(item.name)")
                ShareLink(item: downloaded.localURL) {
                    Image(systemName: "square.and.arrow.up")
                }
                .accessibilityLabel("分享 \(item.name)")
            } else if progress == nil {
                Button(action: download) {
                    Image(systemName: "arrow.down.circle")
                }
                .accessibilityLabel("下载 \(item.name)")
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory { openDirectory() }
            else if let downloaded { preview(downloaded.localURL) }
        }
    }
}

struct RepositoryDownloadsView: View {
    let service: StudyRepositoryService

    @State private var files: [DownloadedStudyFile] = []
    @State private var selectedIDs: Set<String> = []
    @State private var editMode: EditMode = .inactive
    @State private var previewURL: URL?
    @State private var showBatchConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if files.isEmpty {
                ContentUnavailableView(
                    "暂无下载文件",
                    systemImage: "arrow.down.circle",
                    description: Text("浏览学习资料时可将文件保存到本机。")
                )
            } else {
                List {
                    ForEach(files) { file in
                        HStack(spacing: 12) {
                            if editMode.isEditing {
                                Button {
                                    toggle(file.id)
                                } label: {
                                    Image(systemName: selectedIDs.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                }
                            }
                            Image(systemName: fileIcon(file.name))
                                .foregroundStyle(.accent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name).lineLimit(2)
                                Text("\(formatByteCount(file.size)) · \(file.path)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            Spacer()
                            if !editMode.isEditing {
                                Button {
                                    previewURL = file.localURL
                                } label: {
                                    Image(systemName: "doc.text.magnifyingglass")
                                }
                                ShareLink(item: file.localURL) {
                                    Image(systemName: "square.and.arrow.up")
                                }
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if editMode.isEditing { toggle(file.id) }
                            else { previewURL = file.localURL }
                        }
                        .swipeActions {
                            Button("删除", role: .destructive) {
                                Task { await delete(ids: [file.id]) }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(editMode.isEditing ? "已选择 \(selectedIDs.count) 项" : "已下载文件")
        .environment(\.editMode, $editMode)
        .toolbar {
            if !files.isEmpty {
                ToolbarItem(placement: .topBarTrailing) { EditButton() }
            }
            if editMode.isEditing {
                ToolbarItem(placement: .bottomBar) {
                    Button("删除所选", role: .destructive) {
                        showBatchConfirmation = true
                    }
                    .disabled(selectedIDs.isEmpty)
                }
            }
        }
        .task { await reload() }
        .quickLookPreview($previewURL)
        .confirmationDialog(
            "删除选中的 \(selectedIDs.count) 个文件？",
            isPresented: $showBatchConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                Task { await delete(ids: selectedIDs) }
            }
            Button("取消", role: .cancel) {}
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    private func reload() async {
        do {
            files = try await service.downloadedFiles()
            selectedIDs.formIntersection(files.map(\.id))
        } catch {
            errorMessage = "无法读取下载记录。"
        }
    }

    private func delete(ids: Set<String>) async {
        do {
            try await service.deleteDownloadedFiles(ids: ids)
            await reload()
        } catch {
            errorMessage = "无法删除所选文件。"
        }
    }
}

func formatByteCount(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}

private func fileIcon(_ name: String) -> String {
    switch URL(fileURLWithPath: name).pathExtension.lowercased() {
    case "pdf": "doc.richtext"
    case "doc", "docx": "doc.text"
    case "ppt", "pptx": "rectangle.on.rectangle"
    case "xls", "xlsx", "csv": "tablecells"
    case "png", "jpg", "jpeg", "gif", "svg": "photo"
    case "zip", "rar", "7z": "archivebox"
    default: "doc"
    }
}
