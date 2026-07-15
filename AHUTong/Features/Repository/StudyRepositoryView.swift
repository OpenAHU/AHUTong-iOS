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
        if id != selectedRepositoryID {
            selectedRepositoryID = id
            currentPath = ""
        }
        await load()
    }

    func openDirectory(_ item: GitHubContentItem) async {
        guard item.isDirectory else { return }
        currentPath = item.path
        await load()
    }

    func goUp() async {
        guard !currentPath.isEmpty else { return }
        currentPath = currentPath.split(separator: "/").dropLast().joined(separator: "/")
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
                await MainActor.run { self?.downloadProgress[item.id] = value }
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
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model: StudyRepositoryViewModel
    @State private var previewURL: URL?
    @State private var showsRepositorySelector = true

    init(service: StudyRepositoryService = .live()) {
        _model = StateObject(wrappedValue: StudyRepositoryViewModel(service: service))
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                repositoryHeader
                if showsRepositorySelector {
                    repositorySelector
                } else {
                    directoryView
                }
            }
        }
        .quickLookPreview($previewURL)
        .task { await model.start() }
        .alert("提示", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var repositoryHeader: some View {
        HStack(spacing: 0) {
            AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "返回") {
                if showsRepositorySelector {
                    dismiss()
                } else if model.currentPath.isEmpty {
                    showsRepositorySelector = true
                } else {
                    Task { await model.goUp() }
                }
            }
            Text(headerTitle)
                .font(.title2)
                .fontWeight(.semibold)
                .accessibilityIdentifier("screen.study-repository")
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !showsRepositorySelector {
                if model.state.isLoading {
                    ProgressView().controlSize(.small).frame(width: 48, height: 48)
                } else {
                    AndroidIconButton(systemName: "arrow.clockwise", accessibilityLabel: "刷新") {
                        Task { await model.load(policy: .refresh) }
                    }
                }
            }
            NavigationLink {
                RepositoryDownloadsView(service: model.service)
                    .androidDetailScreen()
            } label: {
                Text("已下载").font(.body).padding(.horizontal, 8).frame(height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("repository.downloads")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private var headerTitle: String {
        if showsRepositorySelector { return "学习资料" }
        if model.currentPath.isEmpty { return model.selectedRepository.name }
        return model.currentPath.split(separator: "/").last.map(String.init) ?? model.selectedRepository.name
    }

    private var repositorySelector: some View {
        ScrollView {
            LazyVStack(spacing: 4) {
                ForEach(StudyRepositoryCatalog.repositories) { repository in
                    Button {
                        showsRepositorySelector = false
                        Task { await model.selectRepository(repository.id) }
                    } label: {
                        RepositorySelectorRow(repository: repository)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
    }

    private var directoryView: some View {
        VStack(spacing: 0) {
            if !model.currentPath.isEmpty {
                Text(model.currentPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 4)
            }

            switch model.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(snapshot):
                ScrollView {
                    LazyVStack(spacing: 4) {
                        if snapshot.source == .staleCache {
                            Text("GitHub 连接失败，当前显示上次缓存")
                                .font(.caption)
                                .foregroundStyle(Color(red: 138 / 255, green: 90 / 255, blue: 0))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(AndroidParityPalette.warning.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                        }
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
                        RepositoryFooter(url: model.selectedRepository.githubURL)
                    }
                }
                .scrollIndicators(.hidden)
            case .empty:
                AndroidEmptyState(text: "此目录为空")
                Spacer()
            case let .failed(error):
                VStack(spacing: 16) {
                    Text(error.message).multilineTextAlignment(.center).foregroundStyle(AndroidParityPalette.error)
                    Button("重试") { Task { await model.load(policy: .refresh) } }
                }
                .padding(32)
                Spacer()
            }
        }
    }
}

private struct RepositorySelectorRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let repository: StudyRepositoryConfiguration

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder").font(.system(size: 28)).foregroundStyle(AndroidParityPalette.folder)
            Text(repository.name).font(.body).lineLimit(1).layoutPriority(1)
            Text(repository.repository)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .contentShape(Rectangle())
    }
}

private struct RepositoryContentRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let item: GitHubContentItem
    let downloaded: DownloadedStudyFile?
    let progress: Double?
    let openDirectory: () -> Void
    let download: () -> Void
    let preview: (URL) -> Void

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if item.isDirectory {
                    Image(systemName: "folder").font(.system(size: 28)).foregroundStyle(AndroidParityPalette.folder)
                } else {
                    RepositoryFileBadge(name: item.name)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.name).font(.body).lineLimit(2)
                    if !item.isDirectory, item.size > 0 {
                        Text(formatByteCount(item.size)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let progress {
                    VStack(spacing: 2) {
                        ProgressView(value: progress).frame(width: 24)
                        Text("\(Int(progress * 100))%").font(.caption2)
                    }
                } else if let downloaded {
                    VStack(spacing: 2) {
                        Label("已下载", systemImage: "checkmark.circle")
                            .font(.caption2).foregroundStyle(AndroidParityPalette.success)
                        Button("打开") { preview(downloaded.localURL) }.font(.caption2)
                    }
                } else if !item.isDirectory {
                    Button(action: download) {
                        Image(systemName: "icloud.and.arrow.down")
                            .font(.system(size: 22)).foregroundStyle(Color(red: 66 / 255, green: 165 / 255, blue: 245 / 255))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                }
            }
            if let progress, progress > 0, progress < 1 {
                ProgressView(value: progress).frame(height: 3)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            if item.isDirectory { openDirectory() }
            else if let downloaded { preview(downloaded.localURL) }
        }
    }
}

private struct RepositoryFileBadge: View {
    let name: String

    var body: some View {
        Text(fileType(name))
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(.white)
            .frame(width: 32, height: 32)
            .background(fileColor(name), in: RoundedRectangle(cornerRadius: 6))
    }
}

private struct RepositoryFooter: View {
    let url: URL

    var body: some View {
        HStack(spacing: 0) {
            Text("发现新资料？向").foregroundStyle(.secondary)
            Link("GitHub 仓库", destination: url).foregroundStyle(Color(red: 66 / 255, green: 165 / 255, blue: 245 / 255))
            Text("提 PR 或向开发者").foregroundStyle(.secondary)
            Link("联系", destination: URL(string: "mailto:1793838025@qq.com")!).foregroundStyle(Color(red: 66 / 255, green: 165 / 255, blue: 245 / 255))
            Text("资料").foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 24)
    }
}

struct RepositoryDownloadsView: View {
    @Environment(\.dismiss) private var dismiss
    let service: StudyRepositoryService
    @State private var files: [DownloadedStudyFile] = []
    @State private var selectedIDs: Set<String> = []
    @State private var isManaging = false
    @State private var previewURL: URL?
    @State private var showBatchConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                downloadsHeader
                if files.isEmpty {
                    VStack(spacing: 8) {
                        Text("暂无下载文件").font(.body)
                        Text("浏览学习资料时可下载文件").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(files) { file in
                                DownloadedFileRow(
                                    file: file,
                                    isManaging: isManaging,
                                    isSelected: selectedIDs.contains(file.id),
                                    open: { previewURL = file.localURL },
                                    toggle: { toggle(file.id) },
                                    delete: { Task { await delete(ids: Set([file.id])) } }
                                )
                            }
                        }
                    }
                    if isManaging {
                        HStack {
                            Button(selectedIDs.count == files.count ? "取消全选" : "全选") {
                                selectedIDs = selectedIDs.count == files.count ? [] : Set(files.map(\.id))
                            }
                            Spacer()
                            Button("删除所选", role: .destructive) { showBatchConfirmation = true }
                                .disabled(selectedIDs.isEmpty)
                        }
                        .padding(12)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                        .padding(12)
                    }
                }
            }
        }
        .quickLookPreview($previewURL)
        .task { await reload() }
        .confirmationDialog("删除选中的 \(selectedIDs.count) 个文件？", isPresented: $showBatchConfirmation) {
            Button("删除", role: .destructive) { Task { await delete(ids: selectedIDs) } }
            Button("取消", role: .cancel) {}
        }
        .alert("操作失败", isPresented: Binding(
            get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
        )) { Button("知道了", role: .cancel) {} } message: { Text(errorMessage ?? "") }
    }

    private var downloadsHeader: some View {
        HStack(spacing: 0) {
            AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "返回") { dismiss() }
            Text("已下载文件").font(.title2).fontWeight(.semibold).frame(maxWidth: .infinity, alignment: .leading)
            if !files.isEmpty {
                Button(isManaging ? "完成" : "管理") {
                    isManaging.toggle()
                    if !isManaging { selectedIDs.removeAll() }
                }
                .buttonStyle(.plain)
                .frame(height: 48)
                .padding(.horizontal, 8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 12)
    }

    private func toggle(_ id: String) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    private func reload() async {
        do {
            files = try await service.downloadedFiles()
            selectedIDs.formIntersection(files.map(\.id))
        } catch { errorMessage = "无法读取下载记录。" }
    }

    private func delete(ids: Set<String>) async {
        do {
            try await service.deleteDownloadedFiles(ids: ids)
            await reload()
        } catch { errorMessage = "无法删除所选文件。" }
    }
}

private struct DownloadedFileRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let file: DownloadedStudyFile
    let isManaging: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggle: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if isManaging {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
            }
            RepositoryFileBadge(name: file.name)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name).lineLimit(2)
                Text("\(formatByteCount(file.size)) · \(file.path)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isManaging {
                Button(action: open) { Image(systemName: "doc.text.magnifyingglass") }.buttonStyle(.plain)
                ShareLink(item: file.localURL) { Image(systemName: "square.and.arrow.up") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("用其他 App 打开或分享")
                Button(action: delete) { Image(systemName: "trash").foregroundStyle(AndroidParityPalette.error) }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AndroidParityPalette.raisedSurface(colorScheme), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onTapGesture { isManaging ? toggle() : open() }
    }
}

func formatByteCount(_ bytes: Int64) -> String {
    switch bytes {
    case ..<1024: "\(bytes)B"
    case ..<(1024 * 1024): "\(bytes / 1024)KB"
    case ..<(1024 * 1024 * 1024): "\(bytes / (1024 * 1024))MB"
    default: "\(bytes / (1024 * 1024 * 1024))GB"
    }
}

private func fileType(_ name: String) -> String {
    switch URL(fileURLWithPath: name).pathExtension.lowercased() {
    case "pdf": "PDF"
    case "doc", "docx": "DOC"
    case "ppt", "pptx": "PPT"
    case "xls", "xlsx", "csv": "XLS"
    case "png", "jpg", "jpeg", "gif": "IMG"
    case "svg": "SVG"
    case "zip", "rar", "7z": "ZIP"
    case "apk": "APK"
    default: "FILE"
    }
}

private func fileColor(_ name: String) -> Color {
    switch fileType(name) {
    case "PDF": Color(red: 229 / 255, green: 57 / 255, blue: 53 / 255)
    case "DOC": Color(red: 21 / 255, green: 101 / 255, blue: 192 / 255)
    case "PPT": Color(red: 230 / 255, green: 81 / 255, blue: 0)
    case "XLS": Color(red: 46 / 255, green: 125 / 255, blue: 50 / 255)
    case "IMG": Color(red: 142 / 255, green: 36 / 255, blue: 170 / 255)
    case "SVG": Color(red: 255 / 255, green: 112 / 255, blue: 67 / 255)
    case "ZIP": Color(red: 121 / 255, green: 85 / 255, blue: 72 / 255)
    case "APK": Color(red: 0, green: 150 / 255, blue: 136 / 255)
    default: Color(red: 117 / 255, green: 117 / 255, blue: 117 / 255)
    }
}
