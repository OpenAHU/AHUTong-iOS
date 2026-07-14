import SwiftUI

enum AndroidParityPalette {
    static let brand = Color(red: 0 / 255, green: 127 / 255, blue: 172 / 255)
    static let accent = Color(red: 0 / 255, green: 136 / 255, blue: 255 / 255)
    static let systemTheme = Color(red: 103 / 255, green: 80 / 255, blue: 164 / 255)
    static let primaryTone90 = Color(red: 234 / 255, green: 221 / 255, blue: 255 / 255)
    static let primaryTone80 = Color(red: 208 / 255, green: 188 / 255, blue: 255 / 255)
    static let liquidToggle = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let folder = Color(red: 255 / 255, green: 179 / 255, blue: 0 / 255)
    static let success = Color(red: 76 / 255, green: 175 / 255, blue: 80 / 255)
    static let warning = Color(red: 255 / 255, green: 179 / 255, blue: 0 / 255)
    static let error = Color(red: 255 / 255, green: 82 / 255, blue: 82 / 255)

    static func background(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 26 / 255, green: 26 / 255, blue: 26 / 255)
            : Color(red: 248 / 255, green: 247 / 255, blue: 253 / 255)
    }

    static func surface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 48 / 255, green: 48 / 255, blue: 48 / 255)
            : .white
    }

    static func raisedSurface(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 42 / 255, green: 42 / 255, blue: 42 / 255)
            : Color(red: 252 / 255, green: 252 / 255, blue: 252 / 255)
    }

    static func primaryContainer(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 35 / 255, green: 68 / 255, blue: 82 / 255)
            : Color(red: 216 / 255, green: 224 / 255, blue: 255 / 255)
    }

    static func secondaryText(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 201 / 255, green: 201 / 255, blue: 201 / 255)
            : Color(red: 92 / 255, green: 92 / 255, blue: 92 / 255)
    }

    static func separator(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 72 / 255, green: 72 / 255, blue: 72 / 255)
            : Color(red: 214 / 255, green: 214 / 255, blue: 214 / 255)
    }
}

enum AndroidThemeColor {
    static let options: [(value: String, name: String)] = [
        ("default", "默认"),
        ("#FF4A90E2", "极光蓝"),
        ("#FFE07A9F", "樱花粉"),
        ("#FFF4A261", "落日橙"),
        ("#FF5C6BC0", "靛夜蓝"),
        ("#FF6A994E", "苔藓绿"),
        ("#FF9B7EDE", "薰衣草紫"),
        ("#FFD64550", "绯红花"),
        ("#FF4CC9F0", "天空青"),
        ("#FF2E8B57", "森林翡翠"),
        ("#FF6A4C93", "午夜紫"),
        ("#FFFF6F61", "珊瑚粉"),
        ("#FF7ED9C3", "北极薄荷")
    ]

    static func color(for value: String) -> Color {
        if value == "default" { return AndroidParityPalette.systemTheme }
        if value == "blue" { return AndroidParityPalette.brand }
        if value == "green" { return .green }
        if value == "purple" { return .purple }
        if value == "orange" { return .orange }

        let components = rgbComponents(for: value)
        return Color(red: components.red, green: components.green, blue: components.blue)
    }

    static func rgbComponents(for value: String) -> (red: Double, green: Double, blue: Double) {
        let hex = value.hasPrefix("#") ? String(value.dropFirst()) : value
        guard let raw = UInt64(hex, radix: 16) else { return (0, 127 / 255, 172 / 255) }
        let rgb = hex.count == 8 ? raw & 0x00FF_FFFF : raw
        return (
            Double((rgb >> 16) & 0xFF) / 255,
            Double((rgb >> 8) & 0xFF) / 255,
            Double(rgb & 0xFF) / 255
        )
    }
}

struct AndroidScreen<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        ZStack {
            AndroidParityPalette.background(colorScheme).ignoresSafeArea()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AndroidParityPalette.background(colorScheme).ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct AndroidHeader<Actions: View>: View {
    let title: String
    var large = false
    private let actions: Actions

    init(title: String, large: Bool = false, @ViewBuilder actions: () -> Actions) {
        self.title = title
        self.large = large
        self.actions = actions()
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(large ? .largeTitle : .title2)
                .fontWeight(large ? .regular : .semibold)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            actions
        }
        .padding(.horizontal, large ? 24 : 16)
        .padding(.top, large ? 32 : 12)
        .padding(.bottom, large ? 8 : 12)
    }
}

extension AndroidHeader where Actions == EmptyView {
    init(title: String, large: Bool = false) {
        self.init(title: title, large: large) { EmptyView() }
    }
}

struct AndroidIconButton: View {
    let systemName: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 20, weight: .regular))
                .frame(width: 48, height: 48)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

struct AndroidCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    let radius: CGFloat
    let background: Color?
    private let content: Content

    init(
        radius: CGFloat = 16,
        background: Color? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.radius = radius
        self.background = background
        self.content = content()
    }

    var body: some View {
        content
            .background(
                background ?? AndroidParityPalette.surface(colorScheme),
                in: RoundedRectangle(cornerRadius: radius, style: .continuous)
            )
    }
}

struct AndroidSearchField: View {
    @Binding var text: String
    let prompt: String
    var onSubmit: () -> Void = {}

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit(onSubmit)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清空")
            }
        }
        .frame(height: 56)
        .padding(.horizontal, 16)
        .background(.clear)
    }
}

struct AndroidSectionTitle: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.headline)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
            .padding(.bottom, 8)
    }
}

struct AndroidEmptyState: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(48)
    }
}

struct LiquidGlassBottomBar: View {
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("visual.liquid-glass") private var liquidGlass = true
    @Binding var selection: AppTab
    @Namespace private var glassNamespace

    var body: some View {
        Group {
            if liquidGlass {
                if #available(iOS 26.0, *) {
                    nativeLiquidGlassBar
                } else {
                    legacyMaterialBar
                }
            } else {
                opaqueBar
            }
        }
        .padding(.horizontal, 36)
        .padding(.bottom, 16)
    }

    @available(iOS 26.0, *)
    private var nativeLiquidGlassBar: some View {
        GlassEffectContainer(spacing: 10) {
            tabItems(nativeGlass: true)
                .padding(4)
                .frame(height: 64)
                .glassEffect(.regular.interactive(), in: Capsule(style: .continuous))
                .glassEffectID("bottom-navigation", in: glassNamespace)
        }
    }

    private var legacyMaterialBar: some View {
        tabItems(nativeGlass: false)
            .padding(4)
            .frame(height: 64)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.06))
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 16, y: 6)
    }

    private var opaqueBar: some View {
        tabItems(nativeGlass: false)
            .padding(4)
            .frame(height: 64)
            .background(Capsule(style: .continuous).fill(AndroidParityPalette.surface(colorScheme)))
            .overlay {
                Capsule(style: .continuous)
                    .stroke(colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.06))
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 16, y: 6)
    }

    private func tabItems(nativeGlass: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                Button {
                    withAnimation(.snappy(duration: 0.32)) {
                        selection = tab
                    }
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tab.systemImage)
                            .font(.system(size: 20, weight: .regular))
                        Text(tab.title)
                            .font(.caption2)
                    }
                    .foregroundStyle(selection == tab ? AndroidParityPalette.accent : .primary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        if selection == tab {
                            selectedTabBackground(nativeGlass: nativeGlass)
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("tab.\(tab.rawValue)")
                .accessibilityValue(selection == tab ? "已选择" : "")
                .accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }
    }

    @ViewBuilder
    private func selectedTabBackground(nativeGlass: Bool) -> some View {
        if #available(iOS 26.0, *), nativeGlass {
            Capsule(style: .continuous)
                .fill(.clear)
                .glassEffect(
                    .regular.tint(AndroidParityPalette.accent.opacity(0.18)).interactive(),
                    in: Capsule(style: .continuous)
                )
                .glassEffectID("selected-tab", in: glassNamespace)
        } else {
            Capsule(style: .continuous)
                .fill(AndroidParityPalette.accent.opacity(0.12))
                .matchedGeometryEffect(id: "selected-tab", in: glassNamespace)
        }
    }
}

private struct AndroidDetailScreenModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(.hidden, for: .navigationBar)
            .preference(key: AndroidDetailVisibilityKey.self, value: true)
    }
}

struct AndroidDetailVisibilityKey: PreferenceKey {
    static let defaultValue = false

    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

extension View {
    func androidDetailScreen() -> some View {
        modifier(AndroidDetailScreenModifier())
    }
}
