import SwiftUI

struct PhoneBookView: View {
    @State private var selectedCategory = PhoneBookDirectory.sections[0].title
    @State private var searchQuery = ""

    private var isFiltering: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var visibleEntries: [PhoneBookEntry] {
        if isFiltering { return PhoneBookDirectory.search(searchQuery) }
        return PhoneBookDirectory.sections.first { $0.title == selectedCategory }?.entries ?? []
    }

    var body: some View {
        List {
            if !isFiltering {
                Section {
                    Picker("分类", selection: $selectedCategory) {
                        ForEach(PhoneBookDirectory.sections) { section in
                            Text(section.title).tag(section.title)
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("phone.category")
                }
            }

            if visibleEntries.isEmpty {
                ContentUnavailableView.search(text: searchQuery)
            } else {
                Section(isFiltering ? "搜索结果" : selectedCategory) {
                    ForEach(visibleEntries) { entry in
                        PhoneBookEntryRow(entry: entry, showsCategory: isFiltering)
                    }
                }
            }

            Section {
                Text(PhoneBookDirectory.sourceDescription)
                    .font(.footnote)
                    .foregroundStyle(Color.secondary)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("电话本")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .background(NativeNavigationGestureBridge())
        .searchable(text: $searchQuery, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索电话或部门")
        .accessibilityIdentifier("phone.screen")
    }
}

private struct PhoneBookEntryRow: View {
    @Environment(\.openURL) private var openURL
    @State private var showsDialConfirmation = false
    let entry: PhoneBookEntry
    let showsCategory: Bool

    var body: some View {
        Button {
            showsDialConfirmation = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text(entry.name)
                    .font(.headline)
                    .foregroundStyle(Color.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if showsCategory {
                    Text(entry.category).font(.caption).foregroundStyle(Color.secondary)
                }
                ForEach(entry.numbers) { number in
                    Text(number.dialActionTitle)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("phone.entry.\(entry.id)")
        .accessibilityHint("选择号码后拨打")
        .confirmationDialog(
            entry.numbers.count > 1 ? "请选择校区" : "拨打电话",
            isPresented: $showsDialConfirmation,
            titleVisibility: .visible
        ) {
            ForEach(entry.numbers) { number in
                Button(number.dialActionTitle) {
                    if let url = number.dialURL { openURL(url) }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(entry.name)
        }
    }
}
