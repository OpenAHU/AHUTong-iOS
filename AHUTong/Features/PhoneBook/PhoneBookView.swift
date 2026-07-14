import SwiftUI

struct PhoneBookView: View {
    @Environment(\.openURL) private var openURL
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectedCategory = PhoneBookDirectory.sections[0].title
    @State private var searchQuery = ""
    @State private var isSearchActive = false
    @State private var pendingEntry: PhoneBookEntry?

    private var visibleEntries: [PhoneBookEntry] {
        if isSearchActive {
            return searchQuery.isEmpty ? [] : PhoneBookDirectory.search(searchQuery)
        }
        return PhoneBookDirectory.sections
            .first(where: { $0.title == selectedCategory })?
            .entries ?? []
    }

    var body: some View {
        AndroidScreen {
            VStack(spacing: 0) {
                header

                if !isSearchActive {
                    categories
                        .padding(.bottom, 24)
                }

                ScrollView {
                    if visibleEntries.isEmpty && isSearchActive && !searchQuery.isEmpty {
                        AndroidEmptyState(text: "未找到相关结果")
                    } else {
                        LazyVStack(spacing: 2) {
                            ForEach(visibleEntries) { entry in
                                Button {
                                    pendingEntry = entry
                                } label: {
                                    PhoneBookEntryRow(entry: entry)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("phone.entry.\(entry.id)")
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
                        .padding(.horizontal, 16)
                    }
                }
                .scrollIndicators(.hidden)
            }

            if let pendingEntry {
                Color.black.opacity(0.28).ignoresSafeArea()
                    .onTapGesture { self.pendingEntry = nil }
                AndroidDialDialog(entry: pendingEntry) { number in
                    if let url = number.dialURL { openURL(url) }
                    self.pendingEntry = nil
                }
                .padding(32)
            }
        }
    }

    @ViewBuilder
    private var header: some View {
        if isSearchActive {
            HStack(spacing: 0) {
                AndroidIconButton(systemName: "arrow.left", accessibilityLabel: "关闭搜索") {
                    isSearchActive = false
                    searchQuery = ""
                }
                AndroidSearchField(text: $searchQuery, prompt: "搜索电话或部门")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        } else {
            AndroidHeader(title: "电话本") {
                AndroidIconButton(systemName: "magnifyingglass", accessibilityLabel: "搜索电话或部门") {
                    isSearchActive = true
                }
            }
            .padding(.top, 20)
        }
    }

    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(PhoneBookDirectory.sections) { section in
                    Button(section.title) {
                        selectedCategory = section.title
                    }
                    .buttonStyle(.plain)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        section.title == selectedCategory
                            ? AndroidParityPalette.primaryContainer(colorScheme)
                            : .clear,
                        in: Capsule(style: .continuous)
                    )
                }
            }
            .padding(8)
        }
        .scrollIndicators(.hidden)
        .background(AndroidParityPalette.surface(colorScheme), in: Capsule(style: .continuous))
        .padding(.horizontal, 16)
    }
}

private struct PhoneBookEntryRow: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: PhoneBookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.name).font(.headline)
            HStack(spacing: 8) {
                ForEach(entry.numbers) { number in
                    if entry.numbers.count > 1, let campus = number.campus {
                        Text(campus.rawValue)
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 2)
                            .background(
                                AndroidParityPalette.primaryContainer(colorScheme),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                            )
                    }
                    Text(number.localNumber)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(AndroidParityPalette.secondaryText(colorScheme))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(AndroidParityPalette.surface(colorScheme))
        .contentShape(Rectangle())
    }
}

private struct AndroidDialDialog: View {
    @Environment(\.colorScheme) private var colorScheme
    let entry: PhoneBookEntry
    let dial: (CampusPhoneNumber) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Text(entry.numbers.count > 1 ? "请选择校区" : "拨打 \(entry.name)？")
                .font(.title2)
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(24)

            Rectangle()
                .fill(AndroidParityPalette.separator(colorScheme))
                .frame(height: 2)

            HStack(spacing: 0) {
                ForEach(Array(entry.numbers.enumerated()), id: \.offset) { index, number in
                    if index > 0 {
                        Rectangle()
                            .fill(AndroidParityPalette.separator(colorScheme))
                            .frame(width: 2)
                    }
                    Button(number.campus.map { "\($0.rawValue)校区" } ?? number.localNumber) {
                        dial(number)
                    }
                    .buttonStyle(.plain)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(
            AndroidParityPalette.background(colorScheme),
            in: RoundedRectangle(cornerRadius: 32, style: .continuous)
        )
        .accessibilityIdentifier("phone.dial-dialog")
    }
}
