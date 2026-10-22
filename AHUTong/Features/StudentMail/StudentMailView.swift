import QuickLook
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class StudentMailViewModel: ObservableObject {
    @Published var folders: [StudentMailFolder] = []
    @Published var messages: [StudentMailMessage] = []
    @Published var selectedFolder = 1
    @Published var unreadOnly = false
    @Published var account = ""
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var total = 0
    let client: StudentMailClient
    let demo: Bool
    private var requestID = UUID()

    init(owner: String, campus: any CampusCoreAPI, demo: Bool = AppRuntime.isDemoSession) {
        client = StudentMailClient(owner: owner, campus: campus)
        self.demo = demo
    }

    var folderName: String { folders.first { $0.id == selectedFolder }?.name ?? "收件箱" }

    func load(reset: Bool = true) async {
        let id = UUID()
        requestID = id
        isLoading = true
        errorMessage = nil
        var keepsLoading = false
        defer { if requestID == id && !keepsLoading { isLoading = false } }
        do {
            if demo {
                switch DemoDataState.current {
                case .loading:
                    keepsLoading = true
                    return
                case .error: throw StudentMailError.unavailable
                case .empty:
                    folders = Self.fixtureFolders
                    messages = []
                    total = 0
                    account = "student@example.test"
                    return
                case .normal: break
                }
                account = "student@example.test"
                folders = Self.fixtureFolders
                messages = selectedFolder == 1 ? Self.fixtureMessages.filter { !unreadOnly || !$0.isRead } : []
                total = messages.count
                return
            }
            let email = try await client.connect()
            let loadedFolders = try await client.folders()
            let page = try await client.messages(folder: selectedFolder, start: reset ? 0 : messages.count, unread: unreadOnly)
            guard requestID == id, !Task.isCancelled else { return }
            account = email
            folders = loadedFolders
            if reset { messages = page.messages }
            else {
                let existing = Set(messages.map(\.id))
                messages += page.messages.filter { !existing.contains($0.id) }
            }
            total = page.total
        } catch {
            guard requestID == id, !Task.isCancelled else { return }
            errorMessage = Self.message(for: error)
        }
    }

    func reconnect() async {
        if !demo { await client.invalidate() }
        messages = []
        await load()
    }

    func detail(_ message: StudentMailMessage) async throws -> StudentMailDetail {
        if demo {
            return StudentMailDetail(id: message.id, subject: message.subject, from: [message.sender],
                to: ["student@example.test"], cc: [], text: "这是一封用于界面验证的合成邮件。\n\n校园邮箱支持切换文件夹、筛选未读、阅读、写信、回复与草稿。\n测试不会访问真实邮箱或发送邮件。", attachments: [])
        }
        return try await client.detail(id: message.id)
    }

    func draft(_ message: StudentMailMessage) async throws -> StudentMailDraft {
        if demo { return StudentMailDraft(to: "reader@example.test", subject: message.subject, body: "草稿内容") }
        return try await client.restoreDraft(id: message.id)
    }

    func contacts() async throws -> [StudentMailContact] {
        if demo { return [StudentMailContact(name: "测试联系人", email: "reader@example.test")] }
        return try await client.contacts()
    }

    static func message(for error: Error) -> String {
        // Never surface transport URLs, raw school response text, or session values.
        if let error = error as? StudentMailError { return error.localizedDescription }
        if (error as? URLError)?.code == .notConnectedToInternet { return "请检查网络连接后重试" }
        return StudentMailError.unavailable.localizedDescription
    }

    static let fixtureFolders = [
        StudentMailFolder(id: 1, name: "收件箱", total: 2, unread: 1),
        StudentMailFolder(id: 2, name: "草稿箱", total: 0, unread: 0),
        StudentMailFolder(id: 3, name: "已发送", total: 0, unread: 0),
        StudentMailFolder(id: 4, name: "已删除", total: 0, unread: 0)
    ]
    static let fixtureMessages = [
        StudentMailMessage(id: "fixture-unread", folderID: 1, subject: "校园邮箱使用提示",
            sender: "测试联系人 <reader@example.test>", summary: "这是合成邮件，用于验证原生列表和阅读界面。",
            date: "2026-10-22 09:30", isRead: false, attachments: []),
        StudentMailMessage(id: "fixture-read", folderID: 1, subject: "课程安排确认",
            sender: "teacher@example.test", summary: "请查看本周的课程安排。",
            date: "2026-10-21 17:26", isRead: true, attachments: [])
    ]
}

struct StudentMailView: View {
    @StateObject private var model: StudentMailViewModel
    @State private var query = ""
    @State private var draft: StudentMailDraft?

    init(appModel: AppModel) {
        let owner = if case let .authenticated(user) = appModel.sessionState { user.studentID } else { "" }
        _model = StateObject(wrappedValue: StudentMailViewModel(owner: owner, campus: appModel.campusAPI))
    }

    private var visible: [StudentMailMessage] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.messages.filter { term.isEmpty || ($0.subject + $0.sender + $0.summary).localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        List {
            if model.isLoading && model.messages.isEmpty { ProgressView("正在连接校园邮箱…") }
            if let error = model.errorMessage {
                Section {
                    Text(error).foregroundStyle(.secondary)
                    Button("重试") { Task { await model.load() } }.accessibilityIdentifier("mail.retry")
                }
            }
            if !model.account.isEmpty {
                Section {
                    LabeledContent("邮箱", value: model.account).font(.subheadline).textSelection(.enabled)
                    Toggle("只看未读", isOn: $model.unreadOnly)
                        .accessibilityIdentifier("mail.unread-only")
                }
            }
            if visible.isEmpty && !model.isLoading && model.errorMessage == nil {
                ContentUnavailableView(query.isEmpty ? "暂无邮件" : "没有匹配的邮件",
                    systemImage: "envelope.open", description: Text(query.isEmpty ? "下拉刷新，或切换文件夹查看。" : "试试其他关键词。"))
            } else {
                Section(model.folderName) {
                    ForEach(visible) { message in
                        NavigationLink {
                            StudentMailDetailView(model: model, message: message)
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Circle().fill(message.isRead ? .clear : Color.accentColor).frame(width: 7, height: 7).padding(.top, 7)
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(message.sender).font(.subheadline).lineLimit(1)
                                        Spacer()
                                        if !message.attachments.isEmpty { Image(systemName: "paperclip").foregroundStyle(.secondary) }
                                    }
                                    Text(message.title).fontWeight(message.isRead ? .regular : .semibold).lineLimit(2)
                                    Text(message.summary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    Text(message.date).font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(.vertical, 3)
                        }
                        .accessibilityIdentifier("mail.message.\(message.id)")
                    }
                    if model.messages.count < model.total {
                        Button("加载更多") { Task { await model.load(reset: false) } }.disabled(model.isLoading)
                    }
                }
            }
        }
        .navigationTitle("校园邮箱")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .searchable(text: $query, prompt: "筛选已加载邮件")
        .refreshable { await model.load() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Picker("文件夹", selection: $model.selectedFolder) {
                        ForEach(model.folders) { folder in
                            Text(folder.unread > 0 ? "\(folder.name)（\(folder.unread)）" : folder.name).tag(folder.id)
                        }
                    }
                    Button("重新连接", systemImage: "arrow.clockwise") { Task { await model.reconnect() } }
                    NavigationLink("邮箱网页版", destination: StudentMailWebView(client: model.client))
                } label: { Label("文件夹", systemImage: "folder") }
                .accessibilityIdentifier("mail.folders")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("写信", systemImage: "square.and.pencil") { draft = StudentMailDraft() }
                    .disabled(model.account.isEmpty).accessibilityIdentifier("mail.compose")
            }
        }
        .sheet(item: $draft, onDismiss: { Task { await model.load() } }) { value in
            StudentMailComposeView(model: model, initial: value)
        }
        .onChange(of: model.selectedFolder) { _, _ in query = ""; Task { await model.load() } }
        .onChange(of: model.unreadOnly) { _, _ in Task { await model.load() } }
        .task { await model.load() }
        .accessibilityIdentifier("mail.screen")
    }
}

private struct StudentMailDetailView: View {
    @ObservedObject var model: StudentMailViewModel
    let message: StudentMailMessage
    @State private var detail: StudentMailDetail?
    @State private var error: String?
    @State private var draft: StudentMailDraft?
    @State private var isWorking = false
    @State private var confirmsDelete = false
    @State private var preview: URL?
    @State private var downloadFolder: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let error {
                Text(error).foregroundStyle(.secondary)
                Button("重试") { Task { await loadDetail() } }
            }
            if let detail {
                Section {
                    Text(detail.subject.isEmpty ? "（无主题）" : detail.subject).font(.title3.bold()).textSelection(.enabled)
                    LabeledContent("发件人", value: detail.from.joined(separator: "; "))
                    LabeledContent("收件人", value: detail.to.joined(separator: "; "))
                    if !detail.cc.isEmpty { LabeledContent("抄送", value: detail.cc.joined(separator: "; ")) }
                }.font(.subheadline)
                Section {
                    Text(detail.text.isEmpty ? "（无正文）" : detail.text)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("mail.detail.body")
                } footer: {
                    Text("正文以文本显示，不自动加载外部图片。")
                }
                if !detail.attachments.isEmpty {
                    Section("附件") {
                        ForEach(detail.attachments) { attachment in
                            Button {
                                perform {
                                    let file = try await model.client.download(attachment)
                                    downloadFolder = file.deletingLastPathComponent()
                                    preview = file
                                }
                            } label: {
                                Label("\(attachment.name) · \(attachment.sizeText)", systemImage: "paperclip")
                            }
                        }
                    }
                }
            } else if error == nil { ProgressView("正在读取邮件…") }
        }
        .navigationTitle("邮件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if message.folderID == 2 {
                        Button("继续编辑草稿", systemImage: "square.and.pencil") {
                            perform { draft = try await model.draft(message) }
                        }
                    } else {
                        Button("回复", systemImage: "arrowshape.turn.up.left") { makeReply(forward: false) }
                        Button("转发", systemImage: "arrowshape.turn.up.right") { makeReply(forward: true) }
                    }
                    if message.folderID != 1 {
                        Button("移到收件箱", systemImage: "tray") { move(to: 1) }
                    }
                    if message.folderID != 4 {
                        Button("移到已删除", systemImage: "trash", role: .destructive) { confirmsDelete = true }
                    }
                } label: { Label("邮件操作", systemImage: "ellipsis.circle") }
                .disabled(detail == nil || isWorking)
                .accessibilityIdentifier("mail.detail.actions")
            }
        }
        .overlay { if isWorking { ProgressView().padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
        .confirmationDialog("移到已删除？", isPresented: $confirmsDelete, titleVisibility: .visible) {
            Button("移到已删除", role: .destructive) { move(to: 4) }
        }
        .sheet(item: $draft) { StudentMailComposeView(model: model, initial: $0) }
        .quickLookPreview($preview)
        .onChange(of: preview) { _, value in if value == nil { removeDownload() } }
        .onDisappear { if preview == nil { removeDownload() } }
        .task { await loadDetail() }
        .accessibilityIdentifier("mail.detail")
    }

    private func makeReply(forward: Bool) {
        guard let detail else { return }
        let prefix = forward ? "转发：" : "回复："
        let recipient = forward ? "" : detail.from.first.map(StudentMailProtocol.recipient) ?? ""
        draft = StudentMailDraft(to: recipient, subject: prefix + detail.subject,
            body: "\n\n—— 原邮件 ——\n发件人：\(detail.from.joined(separator: "; "))\n主题：\(detail.subject)\n\n\(detail.text)")
    }
    private func loadDetail() async {
        error = nil
        do { detail = try await model.detail(message) }
        catch { if !Task.isCancelled { self.error = StudentMailViewModel.message(for: error) } }
    }
    private func move(to folder: Int) {
        perform {
            if !model.demo { try await model.client.move(id: message.id, to: folder) }
            await model.load()
            dismiss()
        }
    }
    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do { try await operation() }
            catch { self.error = StudentMailViewModel.message(for: error) }
        }
    }
    private func removeDownload() {
        if let downloadFolder { try? FileManager.default.removeItem(at: downloadFolder) }
        downloadFolder = nil
    }
}

private struct StudentMailComposeView: View {
    @ObservedObject var model: StudentMailViewModel
    @State private var draft: StudentMailDraft
    @State private var isWorking = false
    @State private var error: String?
    @State private var uncertain = false
    @State private var showsContacts = false
    @State private var showsImporter = false
    @State private var confirmsSend = false
    @State private var confirmsClose = false
    @Environment(\.dismiss) private var dismiss

    init(model: StudentMailViewModel, initial: StudentMailDraft) {
        self.model = model
        _draft = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error { Section { Text(error).foregroundStyle(.secondary) }.accessibilityIdentifier("mail.compose.error") }
                if draft.unsupportedResources { Text(StudentMailError.unsupportedDraft.localizedDescription).foregroundStyle(.secondary) }
                Section {
                    TextField("收件人", text: $draft.to).accessibilityIdentifier("mail.compose.to")
                    TextField("抄送", text: $draft.cc)
                    TextField("密送", text: $draft.bcc)
                    Button("选择联系人", systemImage: "person.crop.circle.badge.plus") { showsContacts = true }
                        .accessibilityIdentifier("mail.compose.contacts")
                }
                .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                Section {
                    TextField("主题", text: $draft.subject).accessibilityIdentifier("mail.compose.subject")
                    TextEditor(text: Binding(get: { draft.body }, set: { draft.body = $0; draft.originalHTML = nil }))
                        .frame(minHeight: 220).accessibilityIdentifier("mail.compose.body")
                }
                Section {
                    ForEach(draft.attachments) { attachment in
                        HStack {
                            Label(attachment.name, systemImage: "paperclip")
                            Spacer()
                            Button("移除", systemImage: "xmark.circle") {
                                perform {
                                    draft = try await model.client.removeAttachment(draft, id: attachment.id)
                                }
                            }.labelStyle(.iconOnly)
                        }
                    }
                    Button("添加附件", systemImage: "paperclip") { showsImporter = true }
                        .disabled(model.demo).accessibilityIdentifier("mail.compose.add-attachment")
                } header: { Text("附件") } footer: { Text("单个附件不超过 20 MB。") }
            }
            .disabled(isWorking || uncertain || draft.unsupportedResources)
            .navigationTitle("写信")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        if draft.to.isEmpty && draft.subject.isEmpty && draft.body.isEmpty { dismiss() }
                        else { confirmsClose = true }
                    }.disabled(isWorking)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("发送", systemImage: "paperplane") { confirmsSend = true }
                        .disabled(!draft.canSend || isWorking || uncertain)
                        .accessibilityIdentifier("mail.compose.send")
                }
                if draft.unsupportedResources {
                    ToolbarItem(placement: .bottomBar) {
                        NavigationLink("在网页版继续编辑", destination: StudentMailWebView(client: model.client))
                    }
                }
            }
            .interactiveDismissDisabled(isWorking || !draft.body.isEmpty || !draft.subject.isEmpty || !draft.to.isEmpty)
            .overlay { if isWorking { ProgressView("正在处理…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .confirmationDialog("发送这封邮件？", isPresented: $confirmsSend, titleVisibility: .visible) {
                Button("发送") { perform { if !model.demo { try await model.client.save(draft, deliver: true) }; dismiss() } }
            }
            .confirmationDialog("保存草稿后退出？", isPresented: $confirmsClose, titleVisibility: .visible) {
                if !uncertain && !draft.unsupportedResources {
                    Button("保存草稿") { perform { if !model.demo { try await model.client.save(draft, deliver: false) }; dismiss() } }
                }
                Button("放弃更改", role: .destructive) { dismiss() }
            }
            .sheet(isPresented: $showsContacts) {
                StudentMailContactsView(model: model) { contact in
                    draft.to = StudentMailProtocol.addresses(draft.to + ";" + contact.email).joined(separator: "; ")
                    showsContacts = false
                }
            }
            .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data, .content, .item]) { result in
                switch result {
                case let .success(url):
                    perform {
                        let scoped = url.startAccessingSecurityScopedResource()
                        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.preferredMIMEType ?? "application/octet-stream"
                        draft = try await model.client.upload(draft, file: url, name: url.lastPathComponent, contentType: type)
                    }
                case .failure: error = "无法读取附件，请重新选择"
                }
            }
        }
        .accessibilityIdentifier("mail.compose.screen")
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) {
        isWorking = true
        error = nil
        Task {
            defer { isWorking = false }
            do { try await operation() }
            catch {
                self.error = StudentMailViewModel.message(for: error)
                uncertain = [.deliveryUncertain, .draftUncertain].contains(error as? StudentMailError)
            }
        }
    }
}

private struct StudentMailContactsView: View {
    @ObservedObject var model: StudentMailViewModel
    let select: (StudentMailContact) -> Void
    @State private var contacts: [StudentMailContact] = []
    @State private var query = ""
    @State private var error: String?
    @State private var loading = true
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                if loading { ProgressView("正在读取联系人…") }
                if let error { Text(error).foregroundStyle(.secondary) }
                ForEach(contacts.filter { query.isEmpty || ($0.name + $0.email).localizedCaseInsensitiveContains(query) }) { contact in
                    Button { select(contact) } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(contact.name).foregroundStyle(.primary)
                            Text(contact.email).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }.accessibilityIdentifier("mail.contact.\(contact.id)")
                }
                if !loading && contacts.isEmpty && error == nil { ContentUnavailableView("暂无联系人", systemImage: "person.crop.circle") }
            }
            .navigationTitle("联系人")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "姓名或邮箱")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } } }
            .task {
                defer { loading = false }
                do { contacts = try await model.contacts() }
                catch { self.error = StudentMailViewModel.message(for: error) }
            }
        }
    }
}
