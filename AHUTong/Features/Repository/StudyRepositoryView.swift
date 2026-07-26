import Foundation
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
        currentPath = currentPath.split(separator: "/").dropLast().joined(separator: "/")
        await load()
    }

    func navigate(to path: String) async {
        guard path != currentPath else { return }
        currentPath = path
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

    func download(
        _ item: GitHubContentItem,
        accelerationSource: RepositoryAccelerationSource
    ) async {
        guard downloadProgress[item.id] == nil else { return }
        downloadProgress[item.id] = 0
        do {
            _ = try await service.download(
                repositoryID: selectedRepositoryID,
                item: item,
                accelerationSource: accelerationSource
            ) { [weak self] value in
                await MainActor.run { self?.downloadProgress[item.id] = value }
            }
            downloadProgress[item.id] = nil
            await refreshDownloads()
        } catch is CancellationError {
            downloadProgress[item.id] = nil
        } catch {
            downloadProgress[item.id] = nil
            alertMessage = (error as? LocalizedError)?.errorDescription
                ?? "下载失败，请稍后重试。"
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
    @AppStorage(RepositoryAccelerationPreferences.key)
    private var accelerationSourceID = RepositoryAccelerationPreferences.defaultSource.rawValue
    @StateObject private var model: StudyRepositoryViewModel
    @State private var previewURL: URL?
    @State private var markdownRequest: RepositoryMarkdownRequest?
    @State private var showsRepositorySelector = true
    @State private var showsRepositorySettings = false

    init(service: StudyRepositoryService = .live()) {
        _model = StateObject(wrappedValue: StudyRepositoryViewModel(service: service))
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                repositoryHeader
                RepositoryBreadcrumb(
                    currentPath: currentVirtualPath,
                    onPathClick: navigate(to:)
                )
                if showsRepositorySelector {
                    repositorySelector
                } else {
                    directoryView
                }
            }
        }
        .quickLookPreview($previewURL)
        .fullScreenCover(isPresented: $showsRepositorySettings) {
            RepositoryAccelerationSettingsView()
        }
        .overlay {
            if let markdownRequest {
                RepositoryMarkdownReaderView(
                    request: markdownRequest,
                    service: model.service,
                    onDismiss: { self.markdownRequest = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
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
            Text("学习资料")
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
                Image(systemName: "arrow.down.circle")
                    .font(.system(size: 21))
                    .foregroundStyle(.tint)
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("repository.downloads")
            .accessibilityLabel("已下载")
            AndroidIconButton(systemName: "slider.horizontal.3", accessibilityLabel: "学习资料设置") {
                showsRepositorySettings = true
            }
            .accessibilityIdentifier("repository.settings")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 10)
    }

    private var currentVirtualPath: String {
        guard !showsRepositorySelector else { return "" }
        return RepositoryPathPresentation.virtualPath(
            repositoryID: model.selectedRepositoryID,
            relativePath: model.currentPath
        )
    }

    private var repositorySelector: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
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
            .padding(.vertical, 6)
            .padding(.bottom, 80)
        }
        .scrollIndicators(.hidden)
    }

    private var directoryView: some View {
        VStack(spacing: 0) {
            switch model.state {
            case .idle, .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .loaded(snapshot):
                ScrollView {
                    LazyVStack(spacing: 2) {
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
                                download: {
                                    Task {
                                        await model.download(
                                            item,
                                            accelerationSource: selectedAccelerationSource
                                        )
                                    }
                                },
                                open: {
                                    open(
                                        item: item,
                                        downloaded: model.downloadedFile(for: item)
                                    )
                                }
                            )
                        }
                        RepositoryFooter(url: model.selectedRepository.githubURL)
                    }
                    .padding(.vertical, 6)
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

    private var selectedAccelerationSource: RepositoryAccelerationSource {
        RepositoryAccelerationSource(rawValue: accelerationSourceID)
            ?? RepositoryAccelerationPreferences.defaultSource
    }

    private func navigate(to virtualPath: String) {
        guard virtualPath != currentVirtualPath else { return }
        guard !virtualPath.isEmpty else {
            showsRepositorySelector = true
            return
        }
        guard let location = RepositoryPathPresentation.location(for: virtualPath) else {
            return
        }
        showsRepositorySelector = false
        Task {
            if location.repositoryID != model.selectedRepositoryID {
                await model.selectRepository(location.repositoryID)
            }
            await model.navigate(to: location.relativePath)
        }
    }

    private func open(
        item: GitHubContentItem,
        downloaded: DownloadedStudyFile?
    ) {
        if RepositoryMarkdownSupport.isMarkdownFile(item.name) {
            if let downloaded {
                markdownRequest = .local(downloaded)
            } else {
                markdownRequest = .remote(
                    repositoryID: model.selectedRepositoryID,
                    item: item,
                    accelerationSource: selectedAccelerationSource
                )
            }
        } else if let downloaded {
            previewURL = downloaded.localURL
        }
    }
}

private enum RepositoryMarkdownRequest: Identifiable {
    case remote(
        repositoryID: String,
        item: GitHubContentItem,
        accelerationSource: RepositoryAccelerationSource
    )
    case local(DownloadedStudyFile)

    var id: String {
        switch self {
        case let .remote(repositoryID, item, _):
            "remote:\(repositoryID):\(item.path)"
        case let .local(file):
            "local:\(file.id)"
        }
    }

    var title: String {
        switch self {
        case let .remote(_, item, _): item.name
        case let .local(file): file.name
        }
    }

    func load(using service: StudyRepositoryService) async throws -> RepositoryMarkdownDocument {
        switch self {
        case let .remote(repositoryID, item, accelerationSource):
            try await service.loadRemoteMarkdown(
                repositoryID: repositoryID,
                item: item,
                accelerationSource: accelerationSource
            )
        case let .local(file):
            try await service.loadLocalMarkdown(file)
        }
    }
}

private struct RepositoryMarkdownReaderView: View {
    @Environment(\.colorScheme) private var colorScheme
    let request: RepositoryMarkdownRequest
    let service: StudyRepositoryService
    let onDismiss: () -> Void
    @State private var state: LoadableState<RepositoryMarkdownDocument> = .idle

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Text(request.title)
                        .font(.headline)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("关闭", action: onDismiss)
                        .font(.subheadline.weight(.semibold))
                        .buttonStyle(.plain)
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }

                Group {
                    switch state {
                    case .idle, .loading:
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("正在加载 Markdown…")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                    case .empty:
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 30))
                                .foregroundStyle(.secondary)
                            Text("Markdown 内容为空")
                                .font(.headline)
                            Text("这个文件目前没有可阅读的正文。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 160)
                    case let .failed(error):
                        VStack(spacing: 10) {
                            Label("Markdown 加载失败", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                                .foregroundStyle(AndroidParityPalette.error)
                            Text(error.message)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                            Button("重试") { Task { await load() } }
                                .buttonStyle(.borderless)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: 160)
                    case let .loaded(document):
                        ScrollView {
                            Text(renderedMarkdown(document.content))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .textSelection(.enabled)
                                .accessibilityLabel("Markdown 正文")
                        }
                        .frame(maxHeight: 420)
                    }
                }
            }
            .padding(18)
            .background(
                AndroidParityPalette.raisedSurface(colorScheme),
                in: RoundedRectangle(cornerRadius: 20, style: .continuous)
            )
            .padding(.horizontal, 24)
        }
        .task(id: request.id) { await load() }
        .accessibilityIdentifier("repository.markdown-dialog")
    }

    private func load() async {
        state = .loading
        do {
            let document = try await request.load(using: service)
            guard !Task.isCancelled else { return }
            state = document.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? .empty
                : .loaded(document)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(
                AppErrorState(
                    title: "Markdown 加载失败",
                    message: (error as? LocalizedError)?.errorDescription
                        ?? "请检查网络或切换 GitHub 加速源后重试。"
                )
            )
        }
    }

    private func renderedMarkdown(_ content: String) -> AttributedString {
        (try? AttributedString(
            markdown: content,
            options: .init(
                interpretedSyntax: .full,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(content)
    }
}

private struct RepositoryAccelerationSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage(RepositoryAccelerationPreferences.key)
    private var selectedSourceID = RepositoryAccelerationPreferences.defaultSource.rawValue

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "返回") {
                        dismiss()
                    }
                    Text("学习资料设置")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("GitHub 加速源")
                            .font(.headline)
                            .fontWeight(.bold)
                            .padding(.horizontal, 8)

                        VStack(spacing: 2) {
                            ForEach(RepositoryAccelerationSource.allCases) { source in
                                accelerationSourceRow(source)
                            }
                        }
                        .background(
                            AndroidParityPalette.raisedSurface(colorScheme),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .scrollIndicators(.hidden)
            }
        }
    }

    private func accelerationSourceRow(
        _ source: RepositoryAccelerationSource
    ) -> some View {
        let selected = selectedSourceID == source.rawValue
        return Button {
            selectedSourceID = source.rawValue
        } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(source.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(source.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.tint)
                        .accessibilityLabel("已选择")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(selected ? selectedSourceColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("repository.source.\(source.rawValue)")
    }

    private var selectedSourceColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.24)
            : Color.accentColor.opacity(0.12)
    }
}

private struct RepositoryBreadcrumb: View {
    @Environment(\.colorScheme) private var colorScheme
    let currentPath: String
    let onPathClick: (String) -> Void

    private var items: [RepositoryBreadcrumbItem] {
        RepositoryPathPresentation.breadcrumbs(for: currentPath)
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        breadcrumbChip(item)
                            .id(item.id)
                        if index < items.count - 1 {
                            Text("›")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
            }
            .scrollIndicators(.hidden)
            .onAppear {
                scrollToCurrent(using: proxy, animated: false)
            }
            .onChange(of: currentPath) {
                scrollToCurrent(using: proxy, animated: true)
            }
        }
    }

    @ViewBuilder
    private func breadcrumbChip(_ item: RepositoryBreadcrumbItem) -> some View {
        let isSelected = item.path == currentPath
        Button {
            if !isSelected { onPathClick(item.path) }
        } label: {
            Text(item.label)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? selectedTextColor : Color.secondary)
                .lineLimit(1)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                    isSelected ? selectedChipColor : chipColor,
                    in: Capsule()
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("repository.breadcrumb.\(item.id)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var chipColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.08)
            : Color(red: 245 / 255, green: 246 / 255, blue: 251 / 255)
    }

    private var selectedChipColor: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.22)
            : Color(red: 1, green: 241 / 255, blue: 200 / 255)
    }

    private var selectedTextColor: Color {
        colorScheme == .dark
            ? .accentColor
            : Color(red: 218 / 255, green: 154 / 255, blue: 0)
    }

    private func scrollToCurrent(
        using proxy: ScrollViewProxy,
        animated: Bool
    ) {
        guard let id = items.last?.id else { return }
        if animated {
            withAnimation { proxy.scrollTo(id, anchor: .trailing) }
        } else {
            proxy.scrollTo(id, anchor: .trailing)
        }
    }
}

private struct RepositorySelectorRow: View {
    let repository: StudyRepositoryConfiguration

    var body: some View {
        HStack(spacing: 18) {
            Image(systemName: "folder")
                .font(.system(size: 42))
                .foregroundStyle(AndroidParityPalette.folder)
                .frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 3) {
                Text(repository.name)
                    .font(.title3)
                    .lineLimit(1)
                Text(repository.repository)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: "chevron.right")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 44)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 18)
    }
}

private struct RepositoryContentRow: View {
    let item: GitHubContentItem
    let downloaded: DownloadedStudyFile?
    let progress: Double?
    let openDirectory: () -> Void
    let download: () -> Void
    let open: () -> Void

    var body: some View {
        HStack(spacing: 18) {
            if item.isDirectory {
                Image(systemName: "folder")
                    .font(.system(size: 42))
                    .foregroundStyle(AndroidParityPalette.folder)
                    .frame(width: 42, height: 42)
            } else {
                RepositoryFileBadge(name: item.name)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.title3)
                        .lineLimit(1)
                    if !item.isDirectory, downloaded != nil {
                        Image(systemName: "checkmark.circle")
                            .font(.system(size: 18))
                            .foregroundStyle(AndroidParityPalette.success)
                            .accessibilityLabel("已下载")
                    }
                }
                Text(item.isDirectory ? "目录" : formatByteCount(item.size))
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Group {
                if item.isDirectory {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.secondary)
                } else if let progress {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("下载进度")
                        .accessibilityValue("\(Int(progress * 100))%")
                } else if downloaded != nil {
                    Button(action: open) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 20))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("打开")
                } else {
                    Button(action: download) {
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 21))
                            .foregroundStyle(.tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("下载")
                }
            }
            .frame(width: 44, height: 44)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 18)
        .onTapGesture {
            if item.isDirectory { openDirectory() }
            else if downloaded != nil || RepositoryMarkdownSupport.isMarkdownFile(item.name) {
                open()
            }
        }
    }
}

private struct RepositoryFileBadge: View {
    @Environment(\.colorScheme) private var colorScheme
    let name: String

    var body: some View {
        Text(fileType(name))
            .font(.caption2)
            .fontWeight(.bold)
            .foregroundStyle(colorScheme == .dark ? Color.white : fileColor(name))
            .frame(width: 40, height: 40)
            .background(
                fileColor(name).opacity(colorScheme == .dark ? 0.88 : 0.14),
                in: RoundedRectangle(cornerRadius: 12, style: .continuous)
            )
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
    @State private var markdownRequest: RepositoryMarkdownRequest?
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
                        LazyVStack(spacing: 2) {
                            ForEach(files) { file in
                                DownloadedFileRow(
                                    file: file,
                                    isManaging: isManaging,
                                    isSelected: selectedIDs.contains(file.id),
                                    open: { open(file) },
                                    toggle: { toggle(file.id) },
                                    delete: { Task { await delete(ids: Set([file.id])) } }
                                )
                            }
                        }
                        .padding(.vertical, 6)
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
        .overlay {
            if let markdownRequest {
                RepositoryMarkdownReaderView(
                    request: markdownRequest,
                    service: service,
                    onDismiss: { self.markdownRequest = nil }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
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

    private func open(_ file: DownloadedStudyFile) {
        if RepositoryMarkdownSupport.isMarkdownFile(file.name) {
            markdownRequest = .local(file)
        } else {
            previewURL = file.localURL
        }
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
    let file: DownloadedStudyFile
    let isManaging: Bool
    let isSelected: Bool
    let open: () -> Void
    let toggle: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            if isManaging {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 24))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 24, height: 24)
                Spacer().frame(width: 8)
            }
            RepositoryFileBadge(name: file.name)
            Spacer().frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(file.name)
                    .font(.headline)
                    .lineLimit(2)
                Text(
                    "\(formatByteCount(file.size)) · \(RepositoryPathPresentation.formatDisplayPath(repositoryID: file.repositoryID, relativePath: file.path))"
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !isManaging {
                Button(action: open) {
                    Image(systemName: "arrow.up.forward.app")
                        .font(.system(size: 20))
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("打开")
                .padding(.leading, 4)
                Button(action: delete) {
                    Image(systemName: "trash")
                        .font(.system(size: 20))
                        .foregroundStyle(AndroidParityPalette.error)
                        .frame(width: 40, height: 40)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("删除")
                .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 16)
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 18)
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
    case "md", "markdown", "mdown", "mkd": "MD"
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
    case "MD": Color(red: 69 / 255, green: 90 / 255, blue: 100 / 255)
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
