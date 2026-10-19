import SwiftUI

struct ContributorEntry: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case partner
        case developer(qq: String)
    }

    let name: String
    let description: String
    let kind: Kind

    var id: String {
        switch kind {
        case .partner: "partner-\(name)"
        case let .developer(qq): "developer-\(qq)"
        }
    }

    var qq: String? {
        guard case let .developer(qq) = kind else { return nil }
        return qq
    }

    var avatarURL: URL? {
        guard let qq else { return nil }
        return URL(string: "https://q1.qlogo.cn/g?b=qq&nk=\(qq)&s=640")
    }

    var contactURL: URL? {
        guard let qq else { return nil }
        return URL(string: "mqqapi://card/show_pslcard?&uin=\(qq)")
    }
}

enum ContributorsCatalog {
    static let partners = [
        ContributorEntry(
            name: "Hello~",
            description: "We are waiting for you!\nGet connection with us now!\nClick me for more info!",
            kind: .partner
        )
    ]

    static let developers = [
        ContributorEntry(name: "s1nk", description: "架构规划、页面设计、爬虫", kind: .developer(qq: "468766131")),
        ContributorEntry(name: "😓😢😥😰", description: "架构规划、小组件", kind: .developer(qq: "330771794")),
        ContributorEntry(name: "\u{200B}", description: "页面设计、交互设计、新技术探索", kind: .developer(qq: "257314409")),
        ContributorEntry(name: "堂吉诃德", description: "爬虫、交互设计", kind: .developer(qq: "3148336396")),
        ContributorEntry(name: "Yukon", description: "架构规划、爬虫", kind: .developer(qq: "605606366")),
        ContributorEntry(name: "MuxYang（25级）", description: "充值系统维护、MiuixUI 开发", kind: .developer(qq: "32142587")),
        ContributorEntry(name: "InChange-Jiang（25级）", description: "学习通日历开发、RadiantUI 开发", kind: .developer(qq: "2719904894")),
        ContributorEntry(name: "Himekawa", description: "iOS开发与维护", kind: .developer(qq: "1705945565"))
    ]
}

struct ContributorsView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @State private var rows = ContributorRows.shuffled(using: ContributorsCatalog.developers)
    @State private var selected: ContributorEntry?
    @State private var informationMessage: String?

    var body: some View {
        AndroidScreen {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    AndroidHeader(title: "贡献名单", large: true)
                        .accessibilityIdentifier("contributors.screen")
                    Text("轻点查看贡献 · 双击打开 QQ")
                        .font(.subheadline).foregroundStyle(.secondary)
                        .padding(.horizontal, 24)
                    VStack(spacing: 12) {
                        ForEach(rows.indices, id: \.self) { row in
                            ContributorAvatarRow(
                                entries: rows[row], row: row, selectedID: selected?.id,
                                select: { selected = $0 }, open: open
                            )
                        }
                    }
                    if let selected {
                        AndroidCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(selected.name).font(.title2.bold())
                                Text(selected.description).font(.body)
                                Text("QQ：\(selected.qq ?? "")").font(.callout).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                        }
                        .padding(.horizontal, 16)
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("contributors.detail")
                    } else {
                        Text("每一份贡献，都让校园生活更轻松。")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .padding(.horizontal, 24)
                    }
                    Text("加入我们").font(.title3.bold()).padding(.horizontal, 24)
                    ForEach(ContributorsCatalog.partners) { entry in
                        Button { informationMessage = "请联系任意一位小伙伴" } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(entry.name).font(.headline)
                                Text(entry.description).font(.subheadline).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading).padding(24)
                            .background(AndroidParityPalette.surface(colorScheme), in: RoundedRectangle(cornerRadius: 24))
                        }
                        .buttonStyle(SettingsPressFeedbackStyle(cornerRadius: 24))
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
        }
        .alert("打开 QQ", isPresented: Binding(
            get: { informationMessage != nil },
            set: { if !$0 { informationMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { informationMessage = nil }
        } message: { Text(informationMessage ?? "") }
    }

    private func open(_ entry: ContributorEntry) {
        guard let url = entry.contactURL else { return }
        openURL(url) { accepted in
            if !accepted { informationMessage = "未能打开 QQ，请手动搜索 QQ：\(entry.qq ?? "")" }
        }
    }
}

private struct ContributorAvatarRow: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var avatarSize: CGFloat = 72
    @State private var clock = ContributorMarqueeClock()
    @State private var manuallyPaused = false
    let entries: [ContributorEntry]
    let row: Int
    let selectedID: String?
    let select: (ContributorEntry) -> Void
    let open: (ContributorEntry) -> Void

    private var cellWidth: CGFloat { avatarSize + 24 }
    private var span: CGFloat { CGFloat(entries.count) * (cellWidth + 16) }
    private var staticBrowsing: Bool { reduceMotion || voiceOver }

    var body: some View {
        VStack(spacing: 0) {
            if staticBrowsing {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 16) {
                        ForEach(entries) { avatar($0) }
                    }.padding(.horizontal, 24)
                }
            } else if !entries.isEmpty {
                GeometryReader { geometry in
                    TimelineView(.animation(minimumInterval: 1.0 / 30, paused: clock.isPaused)) { context in
                        let phase = CGFloat(clock.distance(at: context.date)).truncatingRemainder(dividingBy: span)
                        let copies = max(2, Int(ceil(geometry.size.width / span)) + 1)
                        HStack(alignment: .top, spacing: 16) {
                            ForEach(0..<copies, id: \.self) { copy in
                                ForEach(entries) { entry in
                                    avatar(entry)
                                }
                            }
                        }
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(width: geometry.size.width, alignment: .leading)
                        .offset(x: row == 0 ? -phase : phase - span)
                    }
                }
                .frame(height: avatarSize + 56)
                .clipped()
            }
            if manuallyPaused && !staticBrowsing {
                Button {
                    manuallyPaused = false
                    updatePlayback()
                } label: { Label("继续滚动", systemImage: "play.fill").font(.caption) }
                    .buttonStyle(SettingsPressFeedbackStyle())
                    .accessibilityIdentifier("contributors.resume.\(row)")
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("contributors.row.\(row)")
        .accessibilityValue(staticBrowsing ? "手动浏览" : (clock.isPaused ? "已暂停" : (row == 0 ? "向左滚动" : "向右滚动")))
        .onChange(of: scenePhase) { _, _ in updatePlayback() }
        .onChange(of: staticBrowsing) { _, _ in updatePlayback() }
        .onAppear { updatePlayback() }
        .onDisappear { clock.setPaused(true) }
    }

    private func avatar(_ entry: ContributorEntry) -> some View {
        Button {
            manuallyPaused = true
            updatePlayback()
            select(entry)
        } label: {
            VStack(spacing: 8) {
                AsyncImage(url: entry.avatarURL) { phase in
                    if case let .success(image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        ZStack {
                            AndroidParityPalette.primaryContainer(colorScheme)
                            Image(systemName: "person.fill").font(.title2)
                        }
                    }
                }
                .frame(width: avatarSize, height: avatarSize).clipShape(Circle())
                .overlay { Circle().strokeBorder(selectedID == entry.id ? AndroidParityPalette.brand : .clear, lineWidth: 3) }
                Text(entry.name).font(.caption).lineLimit(2).multilineTextAlignment(.center)
            }
            .frame(width: cellWidth)
            .contentShape(Rectangle())
        }
        .buttonStyle(SettingsPressFeedbackStyle(cornerRadius: 16))
        .simultaneousGesture(TapGesture(count: 2).onEnded { open(entry) })
        .accessibilityLabel(entry.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "QQ \(entry.qq ?? "")" : entry.name)
        .accessibilityHint(voiceOver ? "激活查看贡献，也可使用打开 QQ 操作" : "轻点查看贡献，双击打开 QQ")
        .accessibilityIdentifier("contributors.avatar.\(entry.qq ?? entry.id)")
        .accessibilityAction(named: "打开 QQ") { open(entry) }
    }

    private func updatePlayback() {
        clock.setPaused(manuallyPaused || staticBrowsing || scenePhase != .active)
    }
}
