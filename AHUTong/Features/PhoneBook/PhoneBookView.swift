import SwiftUI

struct PhoneBookView: View {
    @Environment(\.openURL) private var openURL
    @State private var selectedCategory = PhoneBookDirectory.sections[0].title
    @State private var searchQuery = ""
    @State private var pendingEntry: PhoneBookEntry?

    private var visibleEntries: [PhoneBookEntry] {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return PhoneBookDirectory.sections
                .first(where: { $0.title == selectedCategory })?
                .entries ?? []
        }
        return PhoneBookDirectory.search(searchQuery)
    }

    var body: some View {
        List {
            if searchQuery.isEmpty {
                categoryPicker
            }

            Section {
                if visibleEntries.isEmpty {
                    ContentUnavailableView.search(text: searchQuery)
                } else {
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
            } header: {
                Text(searchQuery.isEmpty ? selectedCategory : "搜索结果")
            }

            Section("数据来源") {
                Text(PhoneBookDirectory.sourceDescription)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("校园电话本")
        .searchable(text: $searchQuery, prompt: "搜索部门或号码")
        .confirmationDialog(
            pendingEntry.map { "拨打 \($0.name)？" } ?? "确认拨号",
            isPresented: Binding(
                get: { pendingEntry != nil },
                set: { if !$0 { pendingEntry = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingEntry {
                ForEach(pendingEntry.numbers) { number in
                    Button(dialLabel(for: number)) {
                        if let url = number.dialURL {
                            openURL(url)
                        }
                        self.pendingEntry = nil
                    }
                }
            }
            Button("取消", role: .cancel) { pendingEntry = nil }
        } message: {
            Text("系统将打开电话应用，拨号前仍可取消。")
        }
    }

    private var categoryPicker: some View {
        Section("分类") {
            ScrollView(.horizontal) {
                HStack {
                    ForEach(PhoneBookDirectory.sections) { section in
                        Button(section.title) {
                            selectedCategory = section.title
                        }
                        .buttonStyle(.bordered)
                        .tint(section.title == selectedCategory ? .accentColor : .secondary)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .listRowInsets(EdgeInsets())
            .padding(.vertical, 8)
        }
    }

    private func dialLabel(for number: CampusPhoneNumber) -> String {
        if let campus = number.campus {
            return "\(campus.rawValue) · \(number.displayNumber)"
        }
        return number.displayNumber
    }
}

private struct PhoneBookEntryRow: View {
    let entry: PhoneBookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.name)
                .font(.headline)
            ForEach(entry.numbers) { number in
                HStack(spacing: 6) {
                    if let campus = number.campus {
                        Text(campus.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                    Text(number.displayNumber)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}
